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
    task_fields = {"translation_directions", "monolingual_tasks"} & required
    optional_fields = task_fields | ({"training_data"} & required)
    missing = required - config.keys() - optional_fields
    unknown = config.keys() - required
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
        config.setdefault("training_data", [])
        if not isinstance(config["training_data"], list):
            raise ValueError("training_data must be a list")
        train_root = (Path(__file__).resolve().parents[1] / "data/train").resolve()
        lines = []
        for item in config["training_data"]:
            if not isinstance(item, dict) or set(item) != {"host_path", "agent_path"}:
                raise ValueError("Each training_data entry needs host_path and agent_path")
            host_path, agent_path = item["host_path"], item["agent_path"]
            if not all(isinstance(p, str) and p.strip() and Path(p).is_absolute()
                       for p in (host_path, agent_path)):
                raise ValueError("training_data paths must be nonempty absolute paths")
            host = Path(host_path).resolve()
            if not host.is_relative_to(train_root) or not host.exists():
                raise ValueError(f"Training data is missing or outside {train_root}: {host_path}")
            expected = Path("/data/train") / host.relative_to(train_root)
            if Path(agent_path) != expected:
                raise ValueError(f"agent_path for {host_path} must be {expected}")
            lines.append(f"  - `{agent_path}` (host: `{host_path}`)")
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
