#!/usr/bin/env python3
"""Print job runtime and reported cost, or a token-based Codex cost estimate."""

from __future__ import annotations

import argparse
import json
import re
from decimal import Decimal, InvalidOperation
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
    return sum((count * price for count, price in zip(counts, prices)), Decimal(0)) / 1_000_000


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
    parser.add_argument("--model", help="Codex model ID (or azure/ID); defaults to the run-name suffix")
    args = parser.parse_args()

    elapsed_hours = max(0, args.ended_at - args.started_at) / 3600
    print(f"Job exit code: {args.exit_code}")
    print(f"Job runtime (h): {elapsed_hours:.4f}")
    cost = (codex_cost(args.log, args.model) if args.agent == "codex"
            else reported_cost(args.agent, args.log))
    if cost is None:
        if args.agent == "codex":
            print("Agent cost (USD): unavailable (missing/invalid final usage or unsupported model; "
                  "use --model for a known model ID)")
        else:
            print("Agent cost (USD): unavailable (not reported by agent)")
    elif args.agent == "codex":
        print(f"Agent cost (USD): ${cost:.6f} (estimated from final Codex usage; "
              f"{codex_model(args.log, args.model)}; OpenAI Standard short-context prices, "
              "30m cache writes; excludes GPU)")
    else:
        print(f"Agent cost (USD): ${cost:.6f} (agent-reported; excludes GPU)")


if __name__ == "__main__":
    main()
