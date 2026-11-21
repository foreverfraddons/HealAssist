#!/usr/bin/env python3
"""Compare HealAssist/HealAssist.lua with Command Center's copy.

    python3 tools/check_cc.py <path to CommandCenter/HealAssist.lua>

The two must be the same file (line endings aside): Command Center runs it as a
built-in tool, this repo ships it as the standalone addon. Exit 1 when they differ.
"""
import sys, pathlib, re
ours = (pathlib.Path(__file__).resolve().parent.parent / "HealAssist" / "HealAssist.lua").read_text(encoding="utf-8").replace("\r\n", "\n")
theirs = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").replace("\r\n", "\n")
rev = lambda s: (re.search(r"local REV = (\d+)", s) or [None, "?"])[1]
if ours == theirs:
    print(f"same file (REV {rev(ours)})")
    sys.exit(0)
print(f"DIFFERENT: repo REV {rev(ours)}, Command Center REV {rev(theirs)} - copy the newer one over the other")
sys.exit(1)
