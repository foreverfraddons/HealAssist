# HealAssist

HealBot-style healing frames for **World of Warcraft: Forever**, with click casting and **rank gauging**: the rank you cast follows how much health the person is missing.

HealAssist is also built into [Command Center](https://github.com/foreverfraddons/CommandCenter) as a tool. This repo is the standalone addon. Both run the **same `HealAssist.lua`**.

## Features
- One frame per group member (party and raid), plus an optional frame for yourself. Health text stays live in combat.
- **Click casting:** every mouse button with Shift, Ctrl or Alt can be bound. A click can cast a smart heal, a fixed rank, the max rank, an auto group heal, target the person or open their menu.
- **Rank gauging:** each spell has steps, set by dragging pins on a bar. For example, missing 5% casts Rank 1, 10% Rank 2 and 15% Rank 3.
- **Rank zones:** the health bar is split into click areas, and each area casts the rank for the health shown there. This works in combat. WoW Forever hides exact health from addons, so a single click can't pick the rank on its own.
- **Rank ladder:** Shift, Ctrl and Alt are set to three ranks. Badges on the frames show which click fits the health you see.
- **Group heals:** Chain Heal and Prayer of Healing are used when the people around the target are hurt too.
- **Cure buttons:** there is one button per cure your class knows, stacked beside each bar.
- **Debuff colours:** the bar takes the debuff's colour, the type is written on it, and the cure button that fits lights up. The game draws these through its aura containers, so they work in combat.
- **Custom spells:** you can add spells, so any class can use HealAssist.
- **Test mode:** a made-up group with changing health shows every setting live.

## Use
- `/healassist` (or `/hassist`) opens the settings, as does left-clicking the minimap button.
- `/healassist preview` turns on test mode; right-clicking the minimap button does the same.
- Other commands:
  - `/healassist test` toggles a frame for yourself, marked TEST.
  - `/healassist ladder` sets up the rank ladder.
  - `/healassist spells` adds your own spells.
  - `/healassist check` lists the ranks you know.
  - `/healassist minimap` shows or hides the minimap button.
  - `/healassist theme horde|classic|fel` sets the window colours.
  - `/healassist news` shows What's new; `/healassist newsoff` stops it opening by itself after updates.
- Settings are saved in `HealAssistDB` and kept per class.

## With Command Center
Command Center loads first (`OptionalDeps`). If it already contains HealAssist, this addon steps aside: `Host.lua` sets `S.yield` and the other files return at once, so the frames never show twice.

While both are installed, `/healassist` runs Command Center's `/ccenter heal`, and the HealAssist settings stored in Command Center are the ones used. A Command Center version without HealAssist doesn't stop the standalone from running.

## What's new and the new-version notice
The first login after an update opens **What's new**, which lists every version you haven't seen yet. The notes come from `HealAssist/Changelog.lua`.

Addons can't reach the internet, so HealAssist users in the same guild or group tell each other which version they run (addon messages with the prefix `HealAssist`). When someone has a newer version, you get a chat line saying so.

## Releases (automatic, like Questicus)
- **Patch notes:** every change players would notice goes into the top `{ v = "next" ... }` entry of `HealAssist/Changelog.lua`, under `added`, `changed` or `fixed`. Write them for players, with no code talk. Use one line per change: another try at the same fix rewords its line rather than adding one.
- **When a release happens:** `.github/workflows/release.yml` runs every day at 11:19 UTC, or by hand with Actions → Release → Run workflow (tick *force* to release now). It releases when both of these hold:
  - `HealAssist/` changed since the last tag;
  - the "next" entry holds at least **3** changes (repo variable `MIN_CHANGES`).
- **What a release does:**
  1. Raises the patch number in `HealAssist.toc`.
  2. Stamps "next" with that version.
  3. Tags `vX.Y.Z-beta`. The **beta** type comes from repo variable `RELEASE_TYPE` and can be set to `release` or `alpha`.
  4. Packages with BigWigsMods/packager and uploads to CurseForge, with the patch notes as the file changelog, and to a GitHub release.
- **Needed once, in Settings → Secrets and variables → Actions:**
  - the variable `CF_PROJECT_ID` (the CurseForge project number);
  - the secret `CF_API_KEY` (a CurseForge API token).

  Nothing is released until `CF_PROJECT_ID` is set.
- **Releases replace the game folder:** a CurseForge update reinstalls `AddOns\HealAssist`. Before a release, take any newer files from the game folder into the repo.

## Layout
```
HealAssist/            the addon folder
  HealAssist.toc
  Host.lua             what Command Center normally provides: events, messages, saved
                       settings, chat, slash command, minimap button
  UI.lua               copy of Command Center's UI kit (generated - tools/sync_ui.py)
  Changelog.lua        patch notes (newest first, "next" on top) - shown in game and on CurseForge
  News.lua             What's new window + new-version notice (standalone only)
  HealAssist.lua       the module itself - the same file as CommandCenter/HealAssist.lua
  Media/UI/*.tga       the art the UI kit and HealAssist use
  icon.tga
tests/
  ha_test.lua          the module as inside Command Center (texlua / lua5.3)
  standalone_test.lua  Host + UI + module alone, and stepping aside for Command Center
tools/
  sync_ui.py           regenerate UI.lua from Command Center's UI.lua
  check_cc.py          check that HealAssist.lua matches Command Center's copy
  changelog.py         stamp / md / count / check the patch notes (used by the workflows)
```

## Keeping both homes in step
1. Change `HealAssist/HealAssist.lua` and raise `REV`. Then copy the file to `CommandCenter/HealAssist.lua`, with CRLF line endings in the game folder.
2. Run `python3 tools/check_cc.py <CommandCenter/HealAssist.lua>` to confirm they match.
3. If Command Center's UI kit changes, run `python3 tools/sync_ui.py <CommandCenter/UI.lua>`.

## Tests
```
lua5.3 tests/ha_test.lua HealAssist/HealAssist.lua
HA_REFUSE=1 lua5.3 tests/ha_test.lua HealAssist/HealAssist.lua
lua5.3 tests/standalone_test.lua HealAssist
```
GitHub Actions runs these on every push (`.github/workflows/checks.yml`), together with a Lua 5.1 syntax check and the patch notes check.

Author: Fatedfr.
