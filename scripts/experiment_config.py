"""Shared experiment-mode and training-data validation for agent launchers."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MODES = ("standard", "train_only")


def experiment_mode(config):
    if not isinstance(config, dict):
        raise ValueError("Experiment config must be a JSON object")
    mode = config.get("experiment_mode", "standard")
    if mode not in MODES:
        raise ValueError("experiment_mode must be standard or train_only")
    return mode


def training_entries(config):
    mode = experiment_mode(config)
    entries = config.get("training_data", [])
    if not isinstance(entries, list):
        raise ValueError("training_data must be a list")
    if mode == "train_only" and not entries:
        raise ValueError("train_only requires at least one training_data entry")
    train_root = (REPO_ROOT / "data/train").resolve()
    result = []
    destinations = set()
    for item in entries:
        if not isinstance(item, dict) or set(item) != {"host_path", "agent_path"}:
            raise ValueError("Each training_data entry needs host_path and agent_path")
        host_path, agent_path = item["host_path"], item["agent_path"]
        if not all(isinstance(p, str) and p.strip() and Path(p).is_absolute()
                   for p in (host_path, agent_path)):
            raise ValueError("training_data paths must be nonempty absolute paths")
        host = Path(host_path).resolve(strict=True)
        if not host.is_relative_to(train_root):
            raise ValueError(f"Training data is outside {train_root}: {host_path}")
        expected = Path("/data/train") / host.relative_to(train_root)
        if Path(agent_path) != expected:
            raise ValueError(f"agent_path for {host_path} must be {expected}")
        if str(expected) in destinations:
            raise ValueError(f"Duplicate training_data destination: {expected}")
        destinations.add(str(expected))
        if mode == "train_only":
            # Bind syntax cannot safely represent these characters. Also reject
            # links that would escape the selected training-data directory.
            if any(c in str(host) + str(expected) for c in ":,\n\r"):
                raise ValueError("Training-data bind paths cannot contain colons, commas, or newlines")
            if host.is_dir():
                for path in host.rglob("*"):
                    if path.is_symlink() and not path.resolve(strict=True).is_relative_to(host):
                        raise ValueError(f"Training-data symlink escapes selected directory: {path}")
        result.append((host, expected))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("--binds", action="store_true", help="Print validated train-only bind specifications")
    args = parser.parse_args()
    try:
        config = json.loads(args.config.read_text(encoding="utf-8"))
        mode = experiment_mode(config)
        if args.binds:
            if mode != "train_only":
                raise ValueError("--binds requires experiment_mode=train_only")
            for host, agent in training_entries(config):
                print(f"{host}:{agent}:ro")
        else:
            if mode == "train_only":
                training_entries(config)
            print(mode)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()
