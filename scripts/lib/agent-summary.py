#!/usr/bin/env python3
"""Print job runtime and reported API cost or a token-based list-price estimate."""

from __future__ import annotations

import argparse
import json
import re
from decimal import Decimal, InvalidOperation
from datetime import datetime, timezone
from pathlib import Path


# OpenAI Standard, short-context USD per 1M tokens, checked 2026-11-11:
# https://developers.openai.com/api/docs/pricing
# Order: ordinary input, cached input, 30-minute cache writes, output.
CODEX_PRICES = {
    "gpt-6-astra": tuple(map(Decimal, ("10", "1", "12.5", "50"))),
    "gpt-6.1-sol": tuple(map(Decimal, ("2", "0.1", "2.5", "10"))),
    "gpt-6.1-terra": tuple(map(Decimal, ("1", "0.05", "1.25", "5"))),
    "gpt-6-luna": tuple(map(Decimal, ("0.1", "0.01", "0.125", "0.5"))),
}


# Azure Global Standard USD/1M tokens, checked 2026-11-11. Same category order.
# Sources and assumptions: docs/agent-costs.md.
AZURE_PRICES = {
    "FW-Kimi-K3.1-Pro": tuple(map(Decimal, ("2.05", "0.20", "0", "10.35"))),
    "DeepSeek-V4.1-Flash": tuple(map(Decimal, ("0.30", "0.006", "0", "1.20"))),
    "DeepSeek-V4.1-Flash-1017": tuple(map(Decimal, ("0.30", "0.006", "0", "1.20"))),
}
AZURE_ALIASES = {
    "kimi-k3.1-pro": "FW-Kimi-K3.1-Pro",
    "azure-kimi/kimi-k3.1-pro": "FW-Kimi-K3.1-Pro",
    "azure-deepseek/deepseek-v4.1-flash": "DeepSeek-V4.1-Flash",
    "azure-deepseek/deepseek-v4.1-flash-1017": "DeepSeek-V4.1-Flash-1017",
}


def json_events(log: Path):
    if not log.is_file():
        return
    with log.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(event, dict):
                yield event


def token_counts(usage, keys: tuple[str, ...]) -> tuple[int, ...] | None:
    """Read disjoint input/cache/write/output counts; require input and output."""
    if not isinstance(usage, dict):
        return None
    counts = tuple(usage.get(key, 0 if i in (1, 2) else None)
                   for i, key in enumerate(keys))
    return counts if all(type(value) is int and value >= 0 for value in counts) else None


def token_cost(counts, prices) -> Decimal:
    return sum((count * price for count, price in zip(counts, prices)), Decimal(0)) / 1_000_000


def azure_model(model: str | None) -> str | None:
    return AZURE_ALIASES.get(model, model) if isinstance(model, str) else None


def azure_run_model(log: Path) -> str | None:
    # submit-agent.sh truncates model slugs to 32 characters. Only accept a
    # collision when all matching deployments have identical prices.
    matches = set()
    for alias, model in AZURE_ALIASES.items():
        slug = re.sub(r"[^a-z0-9]+", "-", alias.lower())[:32].rstrip("-")
        if re.search(rf"-{re.escape(slug)}-\d+$", log.parent.name):
            matches.add(model)
    if matches and len({AZURE_PRICES[model] for model in matches}) == 1:
        return sorted(matches)[0]
    return None


def antigravity_cost(log: Path, model: str | None, started_at: int = 0):
    final = None
    selected = model
    for event in json_events(log):
        init = event.get("init")
        if selected is None and event.get("event") == "init" and isinstance(init, dict):
            selected = init.get("model")
        result = event.get("result")
        if event.get("event") == "result" and isinstance(result, dict):
            counts = token_counts(result.get("usage"), (
                "input_tokens", "cache_read_tokens", "cache_write_tokens", "output_tokens"))
            if counts is not None:
                final = counts
    if not isinstance(selected, str) or selected not in {"gemini-4-argon", "gemini-4-argon-low",
                        "gemini-4-argon-medium", "gemini-4-argon-high"} or final is None:
        return None
    # input_tokens excludes cache reads; output_tokens already includes thinking.
    # Argon supports implicit caching only; don't guess a cache-write tariff.
    if final[2]:
        return None
    date = datetime.fromtimestamp(started_at if started_at > 0 else log.stat().st_mtime,
                                  timezone.utc)
    promotional = date < datetime(2026, 12, 1, tzinfo=timezone.utc)
    prices = tuple(map(Decimal, ("2", "0.1", "0", "10") if promotional
                       else ("4", "0.2", "0", "20")))
    period = "through 2026-11-30" if promotional else "from 2026-12-01"
    return token_cost(final, prices), f"estimated from final Antigravity usage; Gemini Standard {period}"


def kimi_cost(log: Path, model: str | None):
    # Use the session named by this job, not every session in its private home.
    session_ids = {event["session_id"] for event in json_events(log)
                   if event.get("type") == "session.resume_hint"
                   and isinstance(event.get("session_id"), str)}
    sessions = log.parent / "home/.kimi-code/sessions"
    session_dirs = [path for path in sessions.glob("*/*") if path.is_dir()]
    if session_ids:
        session_dirs = [path for path in session_dirs if path.name in session_ids]
        if {path.name for path in session_dirs} != session_ids:
            return None
    elif len(session_dirs) != 1:
        return None
    wires = [wire for path in session_dirs for wire in path.glob("agents/*/wire.jsonl")]
    total = Decimal(0)
    found = False
    for wire in wires:
        models = {}
        for event in json_events(wire):
            if event.get("type") == "llm.request":
                alias, actual = event.get("modelAlias"), event.get("model")
                if isinstance(alias, str) and isinstance(actual, str):
                    models[alias] = actual
            if event.get("type") != "usage.record":
                continue
            if event.get("agentId", wire.parent.name) != wire.parent.name:
                continue
            counts = token_counts(event.get("usage"), (
                "inputOther", "inputCacheRead", "inputCacheCreation", "output"))
            if isinstance(event.get("usage"), dict) and "inputCacheRead" not in event["usage"]:
                counts = None  # Kimi uses an absent cache-read count for unknown usage.
            alias = event.get("model")
            actual = azure_model(models.get(alias, alias or model) if isinstance(alias, str) else model)
            prices = AZURE_PRICES.get(actual)
            if counts is None or prices is None or counts[2]:
                # No verified separate Azure cache-creation tariff is pinned.
                return None  # Don't present a partial sum as the full job cost.
            # Both 'turn' and 'session' records are per-request deltas; session
            # includes compaction. Nested copies in other event types are ignored.
            total += token_cost(counts, prices)
            found = True
    return (total, "estimated from Kimi usage.record events; Azure Global Standard") if found else None


def opencode_cost(log: Path, model: str | None):
    actual = azure_model(model) if model is not None else azure_run_model(log)
    prices = AZURE_PRICES.get(actual)
    total = Decimal(0)
    found = estimated = False
    for event in json_events(log):
        part = event.get("part")
        if event.get("type") != "step_finish" or not isinstance(part, dict):
            continue
        value = part.get("cost")
        try:
            amount = Decimal(str(value)) if value is not None and not isinstance(value, bool) else None
        except InvalidOperation:
            amount = None
        if amount is not None and (not amount.is_finite() or amount < 0):
            amount = None
        if amount is not None and amount > 0:
            total += amount
            found = True
            continue
        usage = part.get("tokens")
        counts = None
        if isinstance(usage, dict) and isinstance(usage.get("cache", {}), dict):
            counts = token_counts(dict(usage, **{
                "read": usage.get("cache", {}).get("read", 0),
                "write": usage.get("cache", {}).get("write", 0),
            }), ("input", "read", "write", "output"))
            reasoning = usage.get("reasoning", 0)
            if type(reasoning) is not int or reasoning < 0:
                counts = None
            elif counts is not None:
                # OpenCode records visible output and reasoning separately.
                counts = (*counts[:3], counts[3] + reasoning)
        if counts is not None and any(counts):
            if prices is None or counts[2]:
                return None  # Zero with billable tokens is not proof of free use.
            total += token_cost(counts, prices)
            estimated = True
        elif amount is None or (usage is not None and counts is None):
            return None
        found = True
    if not found:
        return None
    basis = "estimated from OpenCode usage (zero/missing step costs); Azure Global Standard" if estimated else "agent-reported"
    return total, basis


def codex_model(log: Path, model: str | None) -> str | None:
    if model is not None:
        return model.removeprefix("azure/")
    # submit-agent.sh replaces punctuation with '-'; require the Slurm ID suffix.
    for name in CODEX_PRICES:
        slug = re.sub(r"[^a-z0-9]+", "-", name)
        if re.search(rf"-{re.escape(slug)}-\d+$", log.parent.name):
            return name
    return None


def codex_cost(log: Path, model: str | None) -> Decimal | None:
    prices = CODEX_PRICES.get(codex_model(log, model))
    if prices is None or not log.is_file():
        return None

    counts = None
    with log.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(event, dict) or event.get("type") != "turn.completed":
                continue
            usage = event.get("usage")
            if not isinstance(usage, dict):
                continue
            values = (
                usage.get("input_tokens"),
                usage.get("cached_input_tokens", 0),
                usage.get("cache_write_input_tokens", 0),
                usage.get("output_tokens"),
            )
            if any(type(value) is not int or value < 0 for value in values):
                continue
            input_tokens, cached, writes, output = values
            ordinary = input_tokens - cached - writes
            if ordinary < 0:
                continue
            # Keep the last cumulative usage; reasoning is already in output_tokens.
            counts = (ordinary, cached, writes, output)

    if counts is None:
        return None
    return token_cost(counts, prices)


def reported_cost(agent: str, log: Path) -> Decimal | None:
    if agent == "codex" or not log.is_file():
        return None

    total = Decimal(0)
    found = False
    with log.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(event, dict):
                continue

            if agent == "opencode" and event.get("type") == "step_finish":
                part = event.get("part")
                value = part.get("cost") if isinstance(part, dict) else None
            elif agent in {"claude", "grok"} and event.get("type") == "result":
                value = event.get("total_cost_usd")
            else:
                continue

            if value is None or isinstance(value, bool):
                continue
            try:
                amount = Decimal(str(value))
            except InvalidOperation:
                continue
            if not amount.is_finite() or amount < 0:
                continue
            if agent == "claude":
                # Claude reports cumulative session cost in each result.
                total = amount
            else:
                total += amount
            found = True

    return total if found else None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("agent", choices=("opencode", "codex", "claude", "kimi", "antigravity", "grok"))
    parser.add_argument("log", type=Path)
    parser.add_argument("started_at", type=int)
    parser.add_argument("ended_at", type=int)
    parser.add_argument("exit_code", type=int)
    parser.add_argument("--model", help="Model selector used by the launcher; otherwise infer from job logs/run name")
    args = parser.parse_args()

    elapsed_hours = max(0, args.ended_at - args.started_at) / 3600
    print(f"Job exit code: {args.exit_code}")
    print(f"Job runtime (h): {elapsed_hours:.4f}")
    result = None
    if args.agent == "codex":
        cost = codex_cost(args.log, args.model)
        if cost is not None:
            result = (cost, f"estimated from final Codex usage; {codex_model(args.log, args.model)}; "
                      "OpenAI Standard short-context prices, 30m cache writes")
    elif args.agent == "antigravity":
        result = antigravity_cost(args.log, args.model, args.started_at)
    elif args.agent == "kimi":
        result = kimi_cost(args.log, args.model)
    elif args.agent == "opencode":
        result = opencode_cost(args.log, args.model)
    else:
        cost = reported_cost(args.agent, args.log)
        if cost is not None:
            result = cost, "agent-reported"
    if result is None:
        print("Agent cost (USD): unavailable (missing/invalid usage, unsupported model, or no reported cost; "
              "see docs/agent-costs.md)")
    else:
        cost, basis = result
        print(f"Agent cost (USD): ${cost:.6f} ({basis}; excludes GPU)")


if __name__ == "__main__":
    main()
