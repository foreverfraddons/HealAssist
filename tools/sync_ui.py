#!/usr/bin/env python3
"""Regenerate HealAssist/UI.lua from Command Center's UI.lua.

    python3 tools/sync_ui.py <path to CommandCenter/UI.lua>

HealAssist's UI kit is a copy of Command Center's with HealAssist's media path and
frame / font names, so the standalone addon looks exactly like the built-in tool.
"""
import re, sys, pathlib

src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").replace("\r\n", "\n")
out = pathlib.Path(__file__).resolve().parent.parent / "HealAssist" / "UI.lua"

def rep(s, a, b, count=None):
    n = s.count(a)
    if n == 0 or (count is not None and n != count):
        sys.exit(f"sync_ui: expected {count or 'some'} of {a!r}, found {n}")
    return s.replace(a, b)

s = rep(src, 'local _, S = ...\nlocal UI = {}\nS.UI = UI',
        "-- (HealAssist standalone: a copy of Command Center's UI kit, so HealAssist looks the same\n"
        "-- on its own. Media paths and frame / font names changed to HealAssist's. Regenerate\n"
        "-- with tools/sync_ui.py instead of editing by hand.)\n"
        'local _, S = ...\nif S.yield then return end\nlocal UI = {}\nS.UI = UI', 1)
s = rep(s, '"Interface\\\\AddOns\\\\CommandCenter\\\\Media\\\\"', '"Interface\\\\AddOns\\\\HealAssist\\\\Media\\\\"', 1)
s = rep(s, 'makeFont("CC_', 'makeFont("HealAssist_')
s = rep(s, '"CC_Scroll"', '"HealAssist_Scroll"')
s = rep(s, 'UI:Window("CC_Confirm", "Command Center"', 'UI:Window("HealAssist_Confirm", "HealAssist"')
s = rep(s, 'UI:Window("CC_Prompt", "Command Center"', 'UI:Window("HealAssist_Prompt", "HealAssist"')
s = rep(s, 'UI:Window("CC_Copy"', 'UI:Window("HealAssist_Copy"')
s = rep(s, '"CC_CopyScroll"', '"HealAssist_CopyScroll"')
left = sorted(set(re.findall(r'"CC_[A-Za-z]*', s)))
if left:
    sys.exit(f"sync_ui: Command Center frame names left: {left}")
out.write_text(s, encoding="utf-8", newline="\n")
print(f"wrote {out} ({len(s.encode())} bytes)")
