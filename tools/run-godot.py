#!/usr/bin/env python3
"""Run Godot headlessly, failing even when a parser error incorrectly exits 0."""
import argparse
from pathlib import Path
import re
import subprocess
import sys

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ERROR = re.compile(r"(?m)^\s*(?:SCRIPT ERROR|ERROR):")


def failed_output(text):
    return bool(ERROR.search(ANSI.sub("", text)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--expect", type=Path)
    parser.add_argument("godot_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    arguments = args.godot_args
    if arguments[:1] == ["--"]:
        arguments = arguments[1:]
    result = subprocess.run([args.executable, "--headless", *arguments], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    text = ANSI.sub("", result.stdout)
    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.log.write_text(text, encoding="utf-8")
    sys.stdout.write(text)
    if result.returncode or failed_output(text):
        print(f"Godot failed: exit={result.returncode}; parser/engine error={failed_output(text)}", file=sys.stderr)
        return 1
    if args.expect and (not args.expect.is_file() or args.expect.stat().st_size == 0):
        print(f"Expected non-empty export missing: {args.expect}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
