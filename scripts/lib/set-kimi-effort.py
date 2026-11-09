#!/usr/bin/env python3
"""Override thinking effort in an isolated Kimi job config (Python 3.11+)."""

import argparse
import copy
import os
from pathlib import Path
import re
import tempfile
import tomllib


EFFORTS = ("low", "medium", "high", "xhigh", "max")


def set_effort(path: Path, model_alias: str, effort: str) -> None:
    if effort not in EFFORTS:
        raise ValueError("Invalid effort; expected low, medium, high, xhigh, or max.")
    source = path.read_text(encoding="utf-8")
    try:
        config = tomllib.loads(source)
    except tomllib.TOMLDecodeError:
        raise ValueError("Invalid Kimi TOML configuration.") from None
    model = config.get("models", {}).get(model_alias)
    if not isinstance(model, dict):
        raise ValueError("Selected model alias is absent from the Kimi configuration.")
    supported = model.get("overrides", {}).get("support_efforts", model.get("support_efforts"))
    if not isinstance(supported, list) or not supported:
        raise ValueError("Declare support_efforts for the selected model before overriding effort.")
    if effort not in supported:
        raise ValueError("Requested effort is not in the selected model's support_efforts.")

    expected = copy.deepcopy(config)
    thinking = expected.setdefault("thinking", {})
    if not isinstance(thinking, dict):
        raise ValueError("Kimi thinking configuration must be a table.")
    thinking.update(enabled=True, effort=effort)

    # Preserve credentials, hooks, comments, and model settings in the original
    # text. Reparse and compare the entire result before writing: a header/key
    # inside a multiline string must never cause an unrelated value to change.
    headers = list(re.finditer(r"(?m)^[ \t]*\[thinking\][ \t]*(?:#[^\n]*)?(?:\n|$)", source))
    if not headers and "thinking" not in config:
        updated = source.rstrip("\n") + f'\n\n[thinking]\nenabled = true\neffort = "{effort}"\n'
    elif len(headers) == 1:
        start = headers[0].end()
        next_header = re.search(r"(?m)^[ \t]*\[", source[start:])
        end = start + next_header.start() if next_header else len(source)
        prefix = source[:start]
        if not prefix.endswith("\n"):
            prefix += "\n"
        body = source[start:end]
        for key, value in (("enabled", "true"), ("effort", f'"{effort}"')):
            body, count = re.subn(rf"(?m)^[ \t]*{key}[ \t]*=[^\n]*(?:\n|$)", f"{key} = {value}\n", body)
            if count > 1:
                raise ValueError("Cannot safely locate thinking fields; use a plain [thinking] table.")
            if count == 0:
                body = f"{key} = {value}\n" + body
        updated = prefix + body + source[end:]
    else:
        raise ValueError("Cannot safely locate thinking fields; use a plain [thinking] table.")
    try:
        matches = tomllib.loads(updated) == expected
    except tomllib.TOMLDecodeError:
        matches = False
    if not matches:
        raise ValueError("Cannot safely edit this TOML layout; use a plain [thinking] table with bare enabled/effort keys.")

    descriptor, temporary = tempfile.mkstemp(prefix=".effort-", suffix=".toml", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(updated)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("model_alias")
    parser.add_argument("effort", choices=EFFORTS)
    args = parser.parse_args()
    try:
        set_effort(args.config, args.model_alias, args.effort)
    except (OSError, ValueError) as error:
        parser.exit(2, f"Kimi effort override failed: {error}\n")
    print(f"Kimi: using {args.effort} effort for {args.model_alias} in this job.")


if __name__ == "__main__":
    main()
