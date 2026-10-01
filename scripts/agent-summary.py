#!/usr/bin/env python3
"""Print the final runtime and agent-reported API cost for a Slurm job."""

from __future__ import annotations

import argparse
import json
from decimal import Decimal, InvalidOperation
from pathlib import Path


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
            elif agent == "claude" and event.get("type") == "result":
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
            total += amount
            found = True

    return total if found else None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("agent", choices=("opencode", "codex", "claude"))
    parser.add_argument("log", type=Path)
    parser.add_argument("started_at", type=int)
    parser.add_argument("ended_at", type=int)
    parser.add_argument("exit_code", type=int)
    args = parser.parse_args()

    elapsed_hours = max(0, args.ended_at - args.started_at) / 3600
    print(f"Job exit code: {args.exit_code}")
    print(f"Job runtime (h): {elapsed_hours:.4f}")
    cost = reported_cost(args.agent, args.log)
    if cost is None:
        print("Agent cost (USD): unavailable (not reported by agent)")
    else:
        print(f"Agent cost (USD): ${cost:.6f} (agent-reported; excludes GPU)")


if __name__ == "__main__":
    main()
