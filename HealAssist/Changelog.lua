-- HealAssist: patch notes shown in game ("What's new") and on CurseForge.
-- Newest first. Put changes for the coming release in the "next" entry: the release workflow
-- (tools/changelog.py) turns "next" into the real version number and writes CHANGELOG.md from this file.
-- Write for players: what was added, what changed, what was fixed - no code talk.
-- One line per change: another try at the same fix rewords its line, it doesn't add one. A CurseForge
-- update goes out once "next" holds 3 lines (release.yml, MIN_CHANGES).
local _, S = ...
if S.yield then return end
S.Changelog = {
  { v = "next",
    added = {
      "Classes without heals: a class with a cure (Mage) gets decurse frames - left-click someone to remove a curse, the bar shows the debuff's colour and the cure button lights up. Classes with no heals or cures (Warrior, Rogue, Hunter, Warlock) have HealAssist switched off.",
    },
  },
  { v = "1.0.0",
    added = {
      "HealAssist on its own: the healing frames from Command Center now come as a separate addon too. Type /healassist or click the minimap button.",
      "Click casting on group frames: every mouse button with Shift, Ctrl or Alt can cast a heal, a fixed rank, the best rank, a group heal, target or open the menu.",
      "Rank gauging: drag the pins on the rank bar to choose which rank to cast for how much health someone is missing.",
      "Rank zones: click along a health bar to cast the rank that fits that much health - also in combat.",
      "Cure buttons next to every frame, and debuffs you can remove colour the bar and light up the right button, also in combat.",
      "Test mode (right-click the minimap button) shows a made-up group so you can try every setting.",
      "A \"What's new\" window after each update, and a message when someone in your guild or group has a newer HealAssist.",
    },
  },
}
