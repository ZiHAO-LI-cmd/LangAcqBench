#!/usr/bin/env python3
"""Render named {placeholders} without interpreting Markdown/JSON braces."""
import argparse
import json
import math
from pathlib import Path
import re

from experiment_config import REPO_ROOT, experiment_mode, training_entries

TOKEN = re.compile(r"(?<!\{)\{([a-z_][a-z0-9_]*)\}(?!\})")


def render(template, config):
    mode = experiment_mode(config)
    required = set(TOKEN.findall(template))
    task_fields = {"translation_directions", "monolingual_tasks"} & required
    optional_fields = task_fields | ({"training_data"} & required)
    missing = required - config.keys() - optional_fields
    unknown = config.keys() - required - {"experiment_mode"}
    if missing:
        raise ValueError("Missing config fields: " + ", ".join(sorted(missing)))
    if unknown:
        raise ValueError("Unknown config fields: " + ", ".join(sorted(unknown)))
    config = dict(config)
    for key in task_fields:
        config.setdefault(key, [])
        value = config[key]
        if not isinstance(value, list) or any(not isinstance(v, str) or not v.strip() for v in value):
            raise ValueError(f"{key} must be a list of nonempty strings")
    if task_fields and not any(config[key] for key in task_fields):
        raise ValueError("At least one translation direction or monolingual task is required")
    if "training_data" in required:
        lines = []
        for host, agent in training_entries(config):
            lines.append(f"  - `{agent}`" if mode == "train_only"
                         else f"  - `{agent}` (host: `{host}`)")
        config["training_data"] = "\n".join(lines) if lines else "  - none specified"
    values = {}
    for key in required:
        value = config[key]
        if key == "num_hours":
            if (isinstance(value, bool) or not isinstance(value, (int, float))
                    or not math.isfinite(value) or value <= 0):
                raise ValueError("num_hours must be a positive finite number")
            value = str(value)
        elif key in task_fields:
            value = ", ".join(value) if value else "none"
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
    parser.add_argument("--template", type=Path, help="Defaults to the template selected by experiment_mode")
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text(encoding="utf-8"))
        mode = experiment_mode(config)
        template = args.template or REPO_ROOT / ("prompt.train-only.md" if mode == "train_only" else "prompt.md")
        if args.output.resolve() in {template.resolve(), args.config.resolve()}:
            parser.error("Output must not overwrite the template or config")
        result = render(template.read_text(encoding="utf-8"), config)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(result, encoding="utf-8")


if __name__ == "__main__":
    main()
