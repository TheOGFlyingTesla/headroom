#!/usr/bin/env python3
"""Pair with a real UI drag to verify movement, not just event delivery."""
import argparse
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("mode", choices=["record", "verify"])
parser.add_argument("snapshot", type=Path)
args = parser.parse_args()
frame = subprocess.check_output(
    ["defaults", "read", "org.headroom.app", "NSWindow Frame HeadroomFloatingPanel"],
    text=True,
)
origin = [float(value) for value in frame.split()[:2]]
if args.mode == "record":
    args.snapshot.write_text(json.dumps(origin))
    print(f"Recorded origin: {origin}")
else:
    previous = json.loads(args.snapshot.read_text())
    if origin == previous:
        raise SystemExit(f"FAIL: panel did not move from {previous}")
    print(f"PASS: panel moved from {previous} to {origin}")
