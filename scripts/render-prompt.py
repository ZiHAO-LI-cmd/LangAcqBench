#!/usr/bin/env python3
"""Render named {placeholders} without interpreting Markdown/JSON braces."""
import argparse
import json
import math
from pathlib import Path
import re

TOKEN = re.compile(r"(?<!\{)\{([a-z_][a-z0-9_]*)\}(?!\})")


def render(template, config):
    if not isinstance(config, dict):
        raise ValueError("Experiment config must be a JSON object")
    required = set(TOKEN.findall(template))
    missing = required - config.keys()
    unknown = config.keys() - required
    if missing:
        raise ValueError("Missing config fields: " + ", ".join(sorted(missing)))
    if unknown:
        raise ValueError("Unknown config fields: " + ", ".join(sorted(unknown)))
    values = {}
    for key in required:
        value = config[key]
        if key == "num_hours":
            if (isinstance(value, bool) or not isinstance(value, (int, float))
                    or not math.isfinite(value) or value <= 0):
                raise ValueError("num_hours must be a positive finite number")
            value = str(value)
        elif isinstance(value, list):
            if not value or not all(isinstance(v, str) and v.strip() for v in value):
                raise ValueError(f"{key} must be a nonempty list of nonempty strings")
            value = ", ".join(value)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{key} must be a nonempty string")
        if TOKEN.search(value):
            raise ValueError(f"Unresolved placeholder in config field: {key}")
        values[key] = value
    return TOKEN.sub(lambda match: values[match.group(1)], template)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", type=Path, default=Path("prompt.md"))
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.resolve() in {args.template.resolve(), args.config.resolve()}:
        parser.error("Output must not overwrite the template or config")
    try:
        result = render(args.template.read_text(encoding="utf-8"),
                        json.loads(args.config.read_text(encoding="utf-8")))
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(result, encoding="utf-8")


if __name__ == "__main__":
    main()
