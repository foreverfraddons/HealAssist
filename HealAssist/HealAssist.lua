-- HealAssist: HealBot-style healing frames with click casting and rank gauging.
--   * one frame per group member (party and raid), click a frame to heal that person
--   * every mouse button + Shift / Ctrl / Alt can be bound: a smart heal, a fixed
--     rank, the max rank, target, or the unit menu
--   * rank gauging: a smart click picks the spell rank from how much health the
--     person is missing (e.g. 5% -> Rank 1, 10% -> Rank 2, 15% -> Rank 3 ...), with
--     your own steps per spell
--   * group heals (Chain Heal, Prayer of Healing): when the people around the target
--     are all hurt, the "auto" click switches to the group heal and gauges its rank
--     from the whole cluster (e.g. all missing 10% -> Rank 2, 20% -> Rank 3)
-- What the game allows: an addon may only change what a click casts OUT of combat,
-- and in combat WoW Forever hides exact health from addons. So the smart rank is kept
-- up to date out of combat; when a fight starts smart clicks switch to your "in combat"
-- choice (max rank by default), and the frames show the gauged rank as marks on the
-- health bar (and a rank badge where the game supports it) so you can press the
-- matching rank binding.
-- The same file runs in two homes: inside Command Center (CommandCenter\HealAssist.lua)
-- and as the standalone HealAssist addon (HealAssist\HealAssist.lua, with Host.lua and UI.lua
-- giving it what Command Center normally provides). When both are installed the
-- standalone copy steps aside (S.yield) so the frames never show twice.
local _, S = ...
if S.yield then return end
local REV = 25
if S.ModuleRev then S:ModuleRev("HealAssist", REV) end
S.HEALASSIST_REV = REV
local CMD = S.HA_CMD or "/ccenter heal"     -- slash command shown in texts
local UI = S.UI

local WHITE = "Interface\\Buttons\\WHITE8x8"
local BACKDROP_T = BackdropTemplateMixin and "BackdropTemplate" or nil
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local isSecret = issecretvalue or function() return false end
local function sec(a, b, c, d) return isSecret(a) or isSecret(b) or isSecret(c) or isSecret(d) end
local function try(fn, ...)
  if not fn then return end
  local ok, a, b, c, d, e = pcall(fn, ...)
  if ok then return a, b, c, d, e end
end
local function bool(v) if isSecret(v) then return false end return v and true or false end
local function combat() return InCombatLockdown and InCombatLockdown() end
local function G() return S.db.global end
local function myClass() local _, c = UnitClass("player"); return c or "UNKNOWN" end
local function C(t) return t[1], t[2], t[3], t[4] or 1 end

---------------------------------------------------------------------------
-- Healing spells (classic rank spell IDs; Forever extras are found in the spellbook)
---------------------------------------------------------------------------
local SPELLS = {
  HW    = { class = "SHAMAN",  name = "Healing Wave",        ids = { 331, 332, 547, 913, 939, 959, 8005, 10395, 10396, 25357 } },
  LHW   = { class = "SHAMAN",  name = "Lesser Healing Wave", ids = { 8004, 8008, 8010, 10466, 10467, 10468 } },
  CH    = { class = "SHAMAN",  name = "Chain Heal",          ids = { 1064, 10622, 10623 }, group = "chain", jumps = 3 },
  LH    = { class = "PRIEST",  name = "Lesser Heal",         ids = { 2050, 2052, 2053 } },
  HEAL  = { class = "PRIEST",  name = "Heal",                ids = { 2054, 2055, 6063, 6064 } },
  GH    = { class = "PRIEST",  name = "Greater Heal",        ids = { 2060, 10963, 10964, 10965, 25314 } },
  FH    = { class = "PRIEST",  name = "Flash Heal",          ids = { 2061, 9472, 9473, 9474, 10915, 10916, 10917 } },
  RENEW = { class = "PRIEST",  name = "Renew",               ids = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 } },
  POH   = { class = "PRIEST",  name = "Prayer of Healing",   ids = { 596, 996, 10960, 10961, 25316 }, group = "party", jumps = 5 },
  HT    = { class = "DRUID",   name = "Healing Touch",       ids = { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 } },
  RG    = { class = "DRUID",   name = "Regrowth",            ids = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 } },
  REJ   = { class = "DRUID",   name = "Rejuvenation",        ids = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 } },
  HL    = { class = "PALADIN", name = "Holy Light",          ids = { 635, 639, 647, 1026, 1042, 3472, 10328, 10329, 25292 } },
  FOL   = { class = "PALADIN", name = "Flash of Light",      ids = { 19750, 19939, 19940, 19941, 19942, 19943 } },
}
local ORDER = { "HW", "LHW", "CH", "GH", "HEAL", "LH", "FH", "RENEW", "POH", "HT", "RG", "REJ", "HL", "FOL" }
S.HEALASSIST_SPELLS = SPELLS

-- custom spells (any class) live in SPELLS too, keyed "X<spellID>", custom = true
local syncCustom, customKeys, customSynced = nil, {}, false
local function classKeys()
  if syncCustom and not customSynced then syncCustom() end
  local out, cls = {}, myClass()
  for _, k in ipairs(ORDER) do if SPELLS[k].class == cls then out[#out + 1] = k end end
  for _, k in ipairs(customKeys) do if SPELLS[k] then out[#out + 1] = k end end
  return out
end

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then local n = try(C_Spell.GetSpellName, id); if type(n) == "string" then return n end end
  if C_Spell and C_Spell.GetSpellInfo then local t = try(C_Spell.GetSpellInfo, id); if type(t) == "table" and t.name then return t.name end end
  if GetSpellInfo then local n = try(GetSpellInfo, id); if type(n) == "string" then return n end end
end
local function spellIcon(id)
  if C_Spell and C_Spell.GetSpellTexture then local t = try(C_Spell.GetSpellTexture, id); if t then return t end end
  if GetSpellTexture then local t = try(GetSpellTexture, id); if t then return t end end
  return 134400
end
local function knownID(id)
  if IsPlayerSpell and bool(try(IsPlayerSpell, id)) then return true end
  if IsSpellKnown and bool(try(IsSpellKnown, id)) then return true end
  return false
end

-- spellbook: { [lower name] = { [rank] = spellID } } for spells with "Rank N"
local function rankOf(sub, id)
  local r = type(sub) == "string" and tonumber(sub:match("(%d+)")) or nil
  if not r and id then
    local s = (C_Spell and C_Spell.GetSpellSubtext and try(C_Spell.GetSpellSubtext, id)) or (GetSpellSubtext and try(GetSpellSubtext, id))
    if type(s) == "string" then r = tonumber(s:match("(%d+)")) end
  end
  return r
end
local function scanBook()
  local out = {}
  local function add(name, sub, id)
    if type(name) ~= "string" or type(id) ~= "number" or isSecret(name) then return end
    local r = rankOf(sub, id)
    if r then local t = out[name:lower()] or {}; out[name:lower()] = t; t[r] = id end
  end
  if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local n = try(C_SpellBook.GetNumSpellBookSkillLines) or 0
    for i = 1, n do
      local info = try(C_SpellBook.GetSpellBookSkillLineInfo, i)
      if type(info) == "table" and info.itemIndexOffset and info.numSpellBookItems then
        for j = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
          local it = try(C_SpellBook.GetSpellBookItemInfo, j, bank)
          local nm, sub = try(C_SpellBook.GetSpellBookItemName, j, bank)
          if type(it) == "table" then add(nm or it.name, sub or it.subName, it.spellID or it.actionID) end
        end
      end
    end
  elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
    local book = BOOKTYPE_SPELL or "spell"
    for i = 1, (try(GetNumSpellTabs) or 0) do
      local _, _, off, num = try(GetSpellTabInfo, i)
      for j = (off or 0) + 1, (off or 0) + (num or 0) do
        local nm, sub = try(GetSpellBookItemName, j, book)
        local _, id = try(GetSpellBookItemInfo, j, book)
        add(nm, sub, id)
      end
    end
  end
  return out
end

-- ranks you know: rankCache[key] = { name, byRank = { [r] = id }, list = { r... sorted }, max }
local rankCache
local function buildRanks()
  rankCache = {}
  local book = scanBook()
  for _, key in ipairs(classKeys()) do
    local sp = SPELLS[key]
    local name = spellName(sp.ids[1] or sp.baseID) or sp.name
    local by = {}
    for r, id in ipairs(sp.ids) do if knownID(id) then by[r] = id end end
    local b = book[name:lower()] or book[sp.name:lower()]
    if b then for r, id in pairs(b) do by[r] = id end end
    local unranked = false
    if sp.custom and next(by) == nil and sp.baseID then
      -- a spell without ranks (Cleanse, Power Word: Shield...) or one the spellbook lists without "Rank N"
      by[1] = sp.baseID; unranked = true
    end
    local list = {}
    for r in pairs(by) do list[#list + 1] = r end
    table.sort(list)
    rankCache[key] = { name = name, byRank = by, list = list, max = list[#list], unranked = unranked,
      icon = spellIcon(by[list[#list] or 0] or sp.ids[1] or sp.baseID) }
  end
end
local function ranks(key)
  if not rankCache then buildRanks() end
  return rankCache[key]
end
local function knownKey(key) local R = ranks(key); return R and R.max ~= nil end
local function sname(key) local R = ranks(key); return (R and R.name) or (SPELLS[key] and SPELLS[key].name) or tostring(key) end
local function topRank(key) local R = ranks(key); local n = SPELLS[key] and #SPELLS[key].ids or 0; return max(n, (R and R.max) or 0) end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local MODS = { "", "shift", "ctrl", "alt" }
local MODLABEL = { [""] = "", shift = "Shift-", ctrl = "Ctrl-", alt = "Alt-" }
local BTNLABEL = { "Left", "Right", "Middle", "Button 4", "Button 5" }
local BTNSHORT = { "L", "R", "M", "B4", "B5" }
local function bindKey(mod, btn) return mod .. "|" .. btn end
local function bindLabel(mod, btn) return MODLABEL[mod] .. BTNLABEL[btn] end
local function bindShort(mod, btn) return MODLABEL[mod] .. BTNSHORT[btn] end

local LOOK = {
  on = true, solo = true, w = 92, h = 40, perCol = 5, spacing = 4, scale = 1, orient = "cols",
  locked = true, marks = true, markNums = false, badge = true, combatBadge = true,
  rangeFade = true, rangeAlpha = 0.4, classColor = true, castBy = "id", at = nil, healthText = "percent", selfTest = false, zones = true,
  dispel = "right", dispelSize = 16, dispelColor = true, dispelText = true, dispelMine = true, dispelIdle = 0.3, dispelEngine = true, dispelWash = 0.6, rankRange = 50,
}

local function defaultBinds(cls)
  local function first(list) for _, k in ipairs(list) do if knownKey(k) then return k end end return list[1] end
  local b = {}
  if cls == "SHAMAN" then
    b["|1"] = { kind = "auto", key = "HW" }; b["|2"] = { kind = "smart", key = "LHW" }
    b["shift|1"] = { kind = "max", key = "HW" }; b["shift|2"] = { kind = "smart", key = "CH" }
  elseif cls == "PRIEST" then
    b["|1"] = { kind = "auto", key = first({ "GH", "HEAL", "LH" }) }; b["|2"] = { kind = "smart", key = first({ "FH", "LH" }) }
    b["shift|1"] = { kind = "smart", key = "RENEW" }; b["shift|2"] = { kind = "smart", key = "POH" }
  elseif cls == "DRUID" then
    b["|1"] = { kind = "smart", key = "HT" }; b["|2"] = { kind = "smart", key = "RG" }; b["shift|1"] = { kind = "smart", key = "REJ" }
  elseif cls == "PALADIN" then
    b["|1"] = { kind = "smart", key = "HL" }; b["|2"] = { kind = "smart", key = "FOL" }; b["shift|1"] = { kind = "max", key = "HL" }
  else
    b["|1"] = { kind = "target" }; b["|2"] = { kind = "menu" }
  end
  b["ctrl|1"] = { kind = "target" }; b["ctrl|2"] = { kind = "menu" }
  return b
end

local function store()
  local g = G()
  g.healAssist = type(g.healAssist) == "table" and g.healAssist or {}
  local h = g.healAssist
  h.look = type(h.look) == "table" and h.look or {}
  for k, v in pairs(LOOK) do if h.look[k] == nil then h.look[k] = v end end
  if not h.look.cleanV1 then h.look.cleanV1 = true; h.look.markNums = false end   -- r7: rank numbers off (too busy)
  h.classes = type(h.classes) == "table" and h.classes or {}
  return h
end
local function L() return store().look end
local function CL()
  local h, cls = store(), myClass()
  local c = h.classes[cls]
  if type(c) ~= "table" then c = {}; h.classes[cls] = c end
  if type(c.binds) ~= "table" then c.binds = defaultBinds(cls) end
  c.spells = type(c.spells) == "table" and c.spells or {}
  c.group = type(c.group) == "table" and c.group or {}
  local gr = c.group
  if gr.on == nil then gr.on = true end
  gr.minOthers = tonumber(gr.minOthers) or 2
  gr.minMiss = tonumber(gr.minMiss) or 10
  gr.rule = gr.rule or "all"
  gr.range = tonumber(gr.range) or 12.5
  c.combat = c.combat or "max"
  c.custom = type(c.custom) == "table" and c.custom or {}
  if c.live == nil then c.live = true end
  return c
end
-- per spell: th[rank] = "heal with this rank when missing at least th %", below = "low" / "skip"
local function defaultTh(key, r)
  if SPELLS[key] and SPELLS[key].group then local d = { 5, 10, 20, 30, 40 }; return d[r] or (r * 10) end
  return r * 5
end
local function spellCfg(key)
  local c = CL()
  local s = c.spells[key]
  if type(s) ~= "table" then s = {}; c.spells[key] = s end
  s.th = type(s.th) == "table" and s.th or {}
  s.below = s.below or "low"
  return s
end
local function th(key, r) local v = tonumber(spellCfg(key).th[r]); if v then return v end return defaultTh(key, r) end

---------------------------------------------------------------------------
-- Gauging
---------------------------------------------------------------------------
local function exists(u) return u and bool(try(UnitExists, u)) end
local function missingPct(u)
  if not exists(u) then return nil end
  if bool(try(UnitIsDeadOrGhost, u)) or (UnitIsConnected and not bool(try(UnitIsConnected, u))) then return nil end
  local cur, mx = try(UnitHealth, u), try(UnitHealthMax, u)
  if not sec(cur, mx) and type(cur) == "number" and type(mx) == "number" and mx > 0 then return max(0, (mx - cur) / mx * 100) end
  -- the game hid the numbers: try the percent API (may still be readable)
  if UnitHealthPercent then
    local p = try(UnitHealthPercent, u)
    if type(p) == "number" and not isSecret(p) then
      if p <= 1.0001 then p = p * 100 end
      return max(0, 100 - p)
    end
  end
  -- last: measure the frame's own health bar (filled by the game)
  if S.HealAssistMeasure then return S.HealAssistMeasure(u) end
  return nil
end
S.HealAssistMissing = missingPct

-- the rank for a missing amount (highest known rank whose step is reached)
local function pickRank(key, miss)
  local R = ranks(key)
  if not R or not R.max then return nil end
  local best, floorTh = nil, 0
  for _, r in ipairs(R.list) do
    floorTh = max(floorTh, th(key, r))     -- steps never go down (a higher rank needs at least as much)
    if (miss or 0) >= floorTh then best = r end
  end
  if not best then
    if spellCfg(key).below == "skip" then return nil end
    best = R.list[1]
  end
  return best
end
S.HealAssistPickRank = pickRank

local function roster()
  local out = {}
  if IsInRaid and IsInRaid() then
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do out[#out + 1] = "raid" .. i end
  else
    out[1] = "player"
    for i = 1, 4 do if exists("party" .. i) then out[#out + 1] = "party" .. i end end
  end
  return out
end
local function same(a, b) return a == b or bool(try(UnitIsUnit, a, b)) end
local function pos(u)
  if not UnitPosition then return nil end
  local y, x, _, inst = try(UnitPosition, u)
  if sec(y, x, inst) or type(x) ~= "number" or type(y) ~= "number" then return nil end
  return x, y, inst
end
local function inMyRange(u)
  if same(u, "player") then return true end
  local inR, checked = try(UnitInRange, u)
  if sec(inR, checked) then return false end
  if checked == false then return true end   -- the game couldn't check: count it
  return inR and true or false
end
-- is b close enough to a for a jump? second value: true when real positions were used
local function near(a, b, range)
  local ax, ay, ai = pos(a)
  local bx, by, bi = pos(b)
  if ax and bx then return ai == bi and ((ax - bx) ^ 2 + (ay - by) ^ 2) <= range * range, true end
  return inMyRange(b), false
end
local function subgroupOf(u)
  if not (IsInRaid and IsInRaid()) or not GetRaidRosterInfo then return 1 end
  for i = 1, (GetNumGroupMembers() or 0) do
    if same("raid" .. i, u) then local _, _, grp = try(GetRaidRosterInfo, i); return grp or 1 end
  end
  return 1
end
-- cluster around unit u for a group heal: ok (enough hurt), value (missing % used for the rank), count, usedPositions
local function cluster(u, gkey)
  local sp, gr = SPELLS[gkey], CL().group
  local m0 = missingPct(u)
  if not m0 then return false, 0, 0 end
  local others, usedPos = {}, false
  local myGrp = sp.group == "party" and subgroupOf("player") or nil
  for _, ru in ipairs(roster()) do
    if not same(ru, u) then
      local close, p
      if sp.group == "party" then close = (not myGrp or subgroupOf(ru) == myGrp) and inMyRange(ru)
      else close, p = near(u, ru, gr.range); usedPos = usedPos or p end
      if close then local m = missingPct(ru); if m then others[#others + 1] = m end end
    end
  end
  table.sort(others, function(a, b) return a > b end)
  local hurt = 0
  for _, m in ipairs(others) do if m >= gr.minMiss then hurt = hurt + 1 end end
  local ok = hurt >= gr.minOthers and m0 >= gr.minMiss
  -- the people the heal lands on: target + the most hurt others
  local take = { m0 }
  for i = 1, min(#others, (sp.jumps or 3) - 1) do take[#take + 1] = others[i] end
  local v
  if gr.rule == "avg" then
    local sum = 0
    for _, m in ipairs(take) do sum = sum + m end
    v = sum / #take
  else
    v = m0
    for _, m in ipairs(take) do v = min(v, m) end
  end
  return ok, v, #take, usedPos
end
S.HealAssistCluster = cluster

local function groupKey()
  for _, k in ipairs(classKeys()) do if SPELLS[k].group and knownKey(k) then return k end end
end

-- what a binding casts on unit u right now.
-- returns type, spell, label, badge ("R3" / "CH2"), key, rank
local function castValue(key, r)
  local R = ranks(key)
  if not R or not r then return nil end
  if R.unranked then return (L().castBy == "name") and R.name or R.byRank[1] end
  if L().castBy == "name" then return R.name .. "(Rank " .. r .. ")" end
  return R.byRank[r] or (R.name .. "(Rank " .. r .. ")")
end
local function rankLabel(key, r) return sname(key) .. " |cffaaaaaa(Rank " .. tostring(r) .. ")|r" end
local function resolve(b, u, forCombat)
  if type(b) ~= "table" or not b.kind or b.kind == "none" then return "none", nil, "|cff777777nothing|r" end
  if b.kind == "target" then return "target", nil, "Target" end
  if b.kind == "menu" then return "togglemenu", nil, "Menu" end
  local key = b.key
  local R = ranks(key)
  if not R or not R.max then return "none", nil, sname(key) .. " |cffff5555(not learned)|r" end
  local r, badge
  if b.kind == "max" then r = R.max
  elseif b.kind == "rank" then
    local want = tonumber(b.rank) or 1
    for _, x in ipairs(R.list) do if x <= want then r = x end end
    r = r or R.list[1]
  else  -- smart / auto
    if forCombat then
      local cm = CL().combat
      if cm == "keep" then return nil end
      if cm == "mid" then r = R.list[ceil(#R.list / 2)] elseif cm == "low" then r = R.list[1] else r = R.max end
    else
      if b.kind == "auto" and CL().group.on then
        local g = groupKey()
        if g and g ~= key then
          local ok, v = cluster(u, g)
          if ok then
            local gr = pickRank(g, v)
            if gr then key, R, r = g, ranks(g), gr end
          end
        end
      end
      if not r then
        if SPELLS[key].group then
          local _, v = cluster(u, key)
          r = pickRank(key, v or 0)
        else
          local m = missingPct(u)
          if m == nil then r = R.max else r = pickRank(key, m) end
        end
      end
      if not r then return "none", nil, sname(key) .. " |cff777777(not hurt enough)|r", nil, key end
    end
  end
  local short = SPELLS[key].group and (key == "CH" and "CH" or "G") or "R"
  badge = short .. r
  return "spell", castValue(key, r), rankLabel(key, r), badge, key, r
end
S.HealAssistResolve = resolve

-- the binding whose spell the frame marks show (left click, else the first spell binding)
local function primaryKey()
  local binds = CL().binds
  local b = binds["|1"]
  if type(b) == "table" and b.key and (b.kind == "smart" or b.kind == "auto") and knownKey(b.key) then return b.key end
  for _, mod in ipairs(MODS) do for btn = 1, 5 do
    local x = binds[bindKey(mod, btn)]
    if type(x) == "table" and x.key and (x.kind == "smart" or x.kind == "auto") and knownKey(x.key) then return x.key end
  end end
end
-- the click that casts exactly this rank of this spell (for the combat badge)
-- in combat: the click that casts the best rank for r (the highest bound rank not above r,
-- else the lowest bound one). Smart / auto clicks count with their combat fallback rank.
-- returns combo text ("Shift-L"), the rank that click casts
local function comboFor(key, r)
  local R = ranks(key)
  if not R or not R.max then return nil end
  local binds = CL().binds
  local cm = CL().combat
  local best, bestRank, low, lowRank
  for _, mod in ipairs(MODS) do for btn = 1, 5 do
    local x = binds[bindKey(mod, btn)]
    if type(x) == "table" and x.key == key then
      local c
      if x.kind == "rank" then
        for _, k in ipairs(R.list) do if k <= (tonumber(x.rank) or 1) then c = k end end
        c = c or R.list[1]
      elseif x.kind == "max" then c = R.max
      elseif (x.kind == "smart" or x.kind == "auto") and cm ~= "keep" then
        c = (cm == "mid" and R.list[ceil(#R.list / 2)]) or (cm == "low" and R.list[1]) or R.max
      end
      if c then
        local combo = bindShort(mod, btn)
        if c <= r and (not bestRank or c > bestRank) then best, bestRank = combo, c end
        if not lowRank or c < lowRank then low, lowRank = combo, c end
      end
    end
  end end
  if best then return best, bestRank end
  return low, lowRank
end

---------------------------------------------------------------------------
-- In-combat rank badge: the game hides health from addon code in combat, but it can
-- evaluate a curve on the health percent for us and hand the result straight to a
-- widget. One step curve per rank -> only the right "R3" label is visible.
---------------------------------------------------------------------------
local curveState = { ok = nil, scale = 1, sig = nil, list = {} }
local function newCurve(points)
  if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
  local c = try(C_CurveUtil.CreateCurve)
  if not c then return nil end
  if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then pcall(c.SetType, c, Enum.LuaCurveType.Step) end
  for _, p in ipairs(points) do pcall(c.AddPoint, c, p[1], p[2]) end
  return c
end
-- health-fraction window [lo, hi] -> points that are 1 inside, 0 outside
local function windowPoints(lo, hi, scale)
  local e = 0.0005
  local pts = {}
  if lo <= 0 then pts[#pts + 1] = { 0, 1 } else pts[#pts + 1] = { 0, 0 }; pts[#pts + 1] = { lo - e, 0 }; pts[#pts + 1] = { lo, 1 } end
  if hi < 1 then pts[#pts + 1] = { hi, 1 }; pts[#pts + 1] = { hi + e, 0 }; pts[#pts + 1] = { 1, 0 } else pts[#pts + 1] = { 1, 1 } end
  for _, p in ipairs(pts) do p[1] = p[1] * scale end
  return pts
end
-- rank windows of a spell: { { r, lo, hi } } in health fraction
local function rankWindows(key)
  local R = ranks(key)
  local out = {}
  if not R or not R.max then return out end
  local eff, f = {}, 0
  for i, r in ipairs(R.list) do f = max(f, th(key, r)); eff[i] = f end
  for i, r in ipairs(R.list) do
    local nextTh = eff[i + 1]
    local lo = nextTh and (1 - nextTh / 100) or 0
    local hi = 1 - eff[i] / 100
    if i == 1 and spellCfg(key).below ~= "skip" then hi = 1 end
    if hi > lo then out[#out + 1] = { r = r, lo = max(0, lo), hi = min(1, hi) } end
  end
  return out
end
-- does the game give 0-1 or 0-100 to a curve? (checked out of combat)
local function detectScale()
  if curveState.scaleChecked or combat() or not UnitHealthPercent then return end
  local p = try(UnitHealthPercent, "player")
  if type(p) == "number" and not isSecret(p) and p > 0 then
    curveState.scale = p > 1.5 and 100 or 1
    curveState.scaleChecked = true
  end
end
local function buildCurves(key)
  local sig = key and (key .. ":" .. table.concat((function() local t = {} for _, w in ipairs(rankWindows(key)) do t[#t + 1] = w.r .. "/" .. w.lo .. "/" .. w.hi end return t end)(), ",")) or ""
  if curveState.sig == sig then return curveState.list end
  curveState.sig, curveState.list = sig, {}
  if not key or curveState.ok == false then return curveState.list end
  if not UnitHealthPercent then curveState.ok = false; return curveState.list end
  for _, w in ipairs(rankWindows(key)) do
    local c = newCurve(windowPoints(w.lo, w.hi, curveState.scale))
    if not c then curveState.ok = false; curveState.list = {}; return curveState.list end
    curveState.list[#curveState.list + 1] = { r = w.r, curve = c, lo = w.lo, hi = w.hi }
  end
  -- check it once out of combat against our own numbers
  if curveState.ok == nil and not combat() and #curveState.list > 0 then
    local m = missingPct("player")
    local good = true
    if m then
      local f = 1 - m / 100
      for _, cv in ipairs(curveState.list) do
        local got = try(UnitHealthPercent, "player", false, cv.curve)
        if type(got) ~= "number" or isSecret(got) then good = false break end
        local want = (f >= cv.lo and f <= cv.hi) and 1 or 0
        if math.abs(got - want) > 0.5 then good = false break end
      end
      curveState.ok = good
    end
  end
  return curveState.list
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local anchor, header, kids = nil, nil, {}
local test = { on = false, size = 5, frames = {}, data = {} }   -- test mode (see below)
local placeTest
local pending = false
local function classRGB(u)
  local _, cls = try(UnitClass, u)
  if type(cls) == "string" and not isSecret(cls) then
    local c = (C_ClassColor and C_ClassColor.GetClassColor and try(C_ClassColor.GetClassColor, cls)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls])
    if c then return c.r, c.g, c.b end
  end
  return 0.3, 0.85, 0.4
end

local function styleKid(b)
  if b.haStyled then return end
  b.haStyled = true
  b:RegisterForClicks("AnyUp")
  local th0 = UI:Theme()
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0, 0, 0, 0.75)
  b.hp = CreateFrame("StatusBar", nil, b)
  b.hp:SetPoint("TOPLEFT", 1, -1); b.hp:SetPoint("BOTTOMRIGHT", -1, 1)
  b.hp:SetStatusBarTexture(WHITE); b.hp:SetMinMaxValues(0, 1); b.hp:SetValue(1)
  b.hp.bg = b.hp:CreateTexture(nil, "BACKGROUND"); b.hp.bg:SetAllPoints(); b.hp.bg:SetColorTexture(0.12, 0.05, 0.05, 0.9)
  b.over = CreateFrame("Frame", nil, b); b.over:SetAllPoints(); b.over:SetFrameLevel(b.hp:GetFrameLevel() + 3)
  b.name = UI:Text(b.over, "", "small", "CENTER"); b.name:SetPoint("TOP", 0, -6); b.name:SetPoint("LEFT", 5, 0); b.name:SetPoint("RIGHT", -5, 0); b.name:SetWordWrap(false)
  b.status = UI:Text(b.over, "", "small", "CENTER"); b.status:SetPoint("BOTTOM", 0, 5); b.status:SetTextColor(0.8, 0.8, 0.8)
  b.dispelText = UI:Text(b.over, "", "small", "CENTER"); b.dispelText:SetPoint("CENTER", 0, -1)
  b.hpText = UI:Text(b.over, "", "small", "LEFT"); b.hpText:SetPoint("BOTTOMLEFT", 5, 5); b.hpText:SetTextColor(1, 1, 1)
  b.badge = UI:Text(b.over, "", "small", "RIGHT"); b.badge:SetPoint("BOTTOMRIGHT", -6, 5)
  -- a small dark pill behind the rank badge so it reads on any class colour
  b.badgeBg = b.over:CreateTexture(nil, "ARTWORK")
  b.badgeBg:SetColorTexture(0, 0, 0, 0.55)
  b.badgeBg:SetPoint("TOPLEFT", b.badge, "TOPLEFT", -3, 2); b.badgeBg:SetPoint("BOTTOMRIGHT", b.badge, "BOTTOMRIGHT", 3, -2)
  b.badgeBg:Hide()
  -- outlined text: readable on bright bars (priest white, rogue yellow)
  for _, fs in ipairs({ b.name, b.status, b.hpText, b.badge }) do
    local font, size = fs:GetFont()
    if font then fs:SetFont(font, size, "OUTLINE") end
    fs:SetShadowOffset(0, 0)
  end
  b.cbadges = {}
  b.marks, b.markNums = {}, {}
  b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.12)
  b.tgt = CreateFrame("Frame", nil, b, BACKDROP_T); b.tgt:SetPoint("TOPLEFT", -1, 1); b.tgt:SetPoint("BOTTOMRIGHT", 1, -1)
  if b.tgt.SetBackdrop then b.tgt:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 }); b.tgt:SetBackdropBorderColor(C(th0.gold)) end
  b.tgt:SetFrameLevel(b.over:GetFrameLevel() + 1); b.tgt:Hide()
  b.haA, b.haLabel = {}, {}
  b:HookScript("OnEnter", function(self) S.HealAssistTooltip(self) end)
  b:HookScript("OnLeave", function() GameTooltip:Hide() end)
  b:HookScript("PostClick", function(self, button) if S.HealAssistNoteClick then S.HealAssistNoteClick(self, button) end end)
end

-- rank marks on the health bar: a thin line where each rank's step starts
local function layoutMarks(b, key)
  local l = L()
  local sig = (key or "") .. ":" .. tostring(l.marks) .. ":" .. tostring(l.markNums) .. ":" .. floor(b:GetWidth() + 0.5) .. ":" .. (curveState.sig or "")
  if key then local t = {} for _, w in ipairs(rankWindows(key)) do t[#t + 1] = w.r .. "/" .. w.hi end sig = sig .. table.concat(t, ",") end
  if b.haMarkSig == sig then return end
  b.haMarkSig = sig
  for _, m in ipairs(b.marks) do m:Hide() end
  for _, m in ipairs(b.markNums) do m:Hide() end
  if not key or not l.marks then return end
  local w = b.hp:GetWidth()
  if not w or w <= 0 then w = (l.w or 90) - 2 end
  local i, lastX = 0, nil
  for idx, win in ipairs(rankWindows(key)) do
    local x = floor(w * win.hi + 0.5)
    -- one short tick per rank step at the top edge; steps closer than 6 px share one tick
    if (idx > 1 or win.hi < 1) and x > 2 and x < w - 1 and (not lastX or math.abs(lastX - x) >= 6) then
      lastX = x
      i = i + 1
      local m = b.marks[i]
      if not m then m = b.over:CreateTexture(nil, "OVERLAY"); m:SetColorTexture(0, 0, 0, 0.6); m:SetSize(2, 4); b.marks[i] = m end
      m:ClearAllPoints(); m:SetPoint("TOP", b.hp, "TOPLEFT", x, 0); m:Show()
      if l.markNums then
        local n = b.markNums[i]
        if not n then n = b.over:CreateFontString(nil, "OVERLAY"); n:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE"); n:SetTextColor(1, 1, 1, 0.8); b.markNums[i] = n end
        n:ClearAllPoints(); n:SetPoint("TOP", m, "BOTTOM", 0, -1); n:SetText(win.r); n:Show()
      end
    end
  end
end


---------------------------------------------------------------------------
-- Health hidden from addons (WoW Forever hides UnitHealth even out of combat - seen in
-- the user's click log 2026-11-20: hp/percent "secret", only max health readable).
-- The game still evaluates a curve on the health percent for us. A STEP curve whose
-- steps are the rank windows and whose values are the spell IDs gives "the right
-- spell ID for this health" as a hidden number: it goes straight into the click's
-- spell attribute (out of combat) and, as "R%d", into the badge (in and out of combat).
-- Our code never sees the health or the rank. If the game won't cast from that value,
-- two clicks without a cast switch it off (hc.attrOK = false) and the old rules return.
---------------------------------------------------------------------------
local hc = { attrOK = nil, misses = 0, cache = {}, pending = nil }
S.HealAssistHC = hc
local function stepCurve(points)
  if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step) then return nil end
  local c = try(C_CurveUtil.CreateCurve)
  if not c or not c.SetType or not pcall(c.SetType, c, Enum.LuaCurveType.Step) then return nil end
  for _, p in ipairs(points) do if not pcall(c.AddPoint, c, p[1], p[2]) then return nil end end
  return c
end
-- health fraction -> spell ID ("id") or rank number ("rank") of the rank to cast
local function rankCurve(key, what)
  local R = ranks(key)
  if not R or not R.max then return nil end
  local wins = rankWindows(key)
  local parts = { key, what, curveState.scale }
  for _, w in ipairs(wins) do parts[#parts + 1] = w.r .. "/" .. w.lo end
  local sig = table.concat(parts, ":")
  local c = hc.cache[sig]
  if c ~= nil then return c or nil end
  table.sort(wins, function(a, b2) return a.lo < b2.lo end)
  local pts = {}
  for _, w in ipairs(wins) do
    local y = (what == "rank") and w.r or R.byRank[w.r]
    if not y then hc.cache[sig] = false return nil end
    -- a window starts just above its low edge (exactly 15% missing still counts for the 15% rank)
    pts[#pts + 1] = { (w.lo > 0 and (w.lo + 0.00001) or 0) * curveState.scale, y }
  end
  if #pts == 0 then hc.cache[sig] = false return nil end
  if pts[1][1] > 0 then table.insert(pts, 1, { 0, pts[1][2] }) end
  c = stepCurve(pts)
  hc.cache[sig] = c or false
  return c
end
-- the hidden "spell ID for this health" of a spell on a unit (nil if not possible)
local function hcValue(u, key, what)
  local c = rankCurve(key, what)
  if not c or not UnitHealthPercent then return nil end
  return try(UnitHealthPercent, u, false, c)
end
local function healthHidden(u)
  local cur = try(UnitHealth, u)
  return isSecret(cur) or (u and exists(u) and type(cur) ~= "number")
end

local function setAttr(b, k, v)
  -- compare with the real attribute: the secure click snippet changes some in combat
  local cur = b:GetAttribute(k)
  if not isSecret(cur) and not isSecret(v) and cur == v then return end
  b:SetAttribute(k, v)
end
-- point the clicks of one frame at the right spells (out of combat only)
local function updateClicks(b, forCombat)
  if combat() then return end
  local u = b:GetAttribute("unit")
  -- can't read their health out of combat? let the secure click measure the bar instead
  local blind = u and exists(u) and (function()
    local cur, mx = try(UnitHealth, u), try(UnitHealthMax, u)
    return sec(cur, mx) or type(cur) ~= "number"
  end)() or nil
  if b:GetAttribute("ha-blind") ~= blind then b:SetAttribute("ha-blind", blind) end
  local binds = CL().binds
  b.haBadgeText = nil
  for _, mod in ipairs(MODS) do
    local pre = mod ~= "" and (mod .. "-") or ""
    for btn = 1, 5 do
      local bk = bindKey(mod, btn)
      local bind = binds[bk]
      local typ, spell, label, badge = "none", nil, nil, nil
      if u then typ, spell, label, badge = resolve(bind, u, forCombat) end
      -- health hidden: let the game pick the spell ID from the health (single-target spells)
      if blind and not forCombat and hc.attrOK ~= false and typ == "spell" and type(bind) == "table"
        and (bind.kind == "smart" or bind.kind == "auto") and bind.key and not SPELLS[bind.key].group then
        local v = hcValue(u, bind.key, "id")
        if v ~= nil then
          setAttr(b, pre .. "type" .. btn, "spell")
          if pcall(b.SetAttribute, b, pre .. "spell" .. btn, v) and isSecret(b:GetAttribute(pre .. "spell" .. btn)) then
            typ = nil
            b.haLabel[bk] = sname(bind.key) .. " |cffaaaaaa(rank picked by the game from health)|r"
          else
            hc.attrOK = false   -- the game won't keep a hidden value in a click (seen in game 2026-11-20)
          end
        end
      end
      if typ ~= nil then   -- nil = keep what's there (in combat: "keep the last rank")
        setAttr(b, pre .. "type" .. btn, typ)
        setAttr(b, pre .. "spell" .. btn, spell)
        b.haLabel[bk] = label
      end
      if bk == "|1" then b.haBadgeText = badge end
      S.HealAssistLiveAttrs(b, mod, btn, bind)
    end
  end
  if S.HealAssistZones then S.HealAssistZones(b) end
  if S.HealAssistDispelButtons then S.HealAssistDispelButtons(b) end
  if S.HealAssistAuraWatch then pcall(S.HealAssistAuraWatch, b) end
end

---------------------------------------------------------------------------
-- Rank zones: invisible click areas along the health bar, one per rank of your main
-- smart heal. The bar fills left to right with health, so the spot where the bar ends
-- lies in the zone of the rank that health needs: click there and that rank is cast.
-- Each zone's spells are fixed (set out of combat), so this works in combat too - no
-- health reading needed. Every other click (right click, Shift / Ctrl / Alt, target,
-- menu) is copied from the frame, so the zones behave like the frame everywhere else.
---------------------------------------------------------------------------
local function zoneTooltip(z)
  local b = z.haParent
  S.HealAssistTooltip(b)
  if z.haRankText then
    GameTooltip:AddLine("Zone: " .. z.haRankText .. " |cffaaaaaa(click where the bar ends)|r", 1, 0.82, 0)
    GameTooltip:Show()
  end
end
local function makeZone(b, i)
  -- same template and click registration as the frame itself (that one casts fine);
  -- the plain action-button template ignored mouse-up clicks on this client
  local z = CreateFrame("Button", nil, b, "SecureUnitButtonTemplate")
  z.haParent = b
  z:SetAttribute("useparent-unit", true)
  z:SetAttribute("unit", b:GetAttribute("unit"))
  z:RegisterForClicks("AnyUp")
  z:SetFrameLevel(b:GetFrameLevel() + 8)
  local hl = z:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10)
  local edge = z:CreateTexture(nil, "HIGHLIGHT"); edge:SetColorTexture(1, 0.82, 0, 0.6)
  edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT"); edge:SetWidth(1)
  z:HookScript("OnEnter", zoneTooltip)
  z:HookScript("OnLeave", function() GameTooltip:Hide() end)
  z:HookScript("PostClick", function(self, button) if S.HealAssistNoteClick then S.HealAssistNoteClick(self, button) end end)
  b.haZones[i] = z
  return z
end
function S.HealAssistZones(b)
  if combat() or not b or b.fakeIndex then return end
  b.haZones = b.haZones or {}
  local l = L()
  local key = primaryKey()
  local wins = key and rankWindows(key) or {}
  if not l.zones or #wins == 0 then
    for _, z in ipairs(b.haZones) do z:Hide() end
    b.haZoneSig = nil
    return
  end
  -- health above the first rank's step with "don't cast": a zone that casts nothing
  table.sort(wins, function(a, c) return a.lo < c.lo end)
  local top = wins[#wins].hi
  local zonesDef = {}
  for _, w in ipairs(wins) do zonesDef[#zonesDef + 1] = { lo = w.lo, hi = w.hi, r = w.r } end
  if top < 1 then zonesDef[#zonesDef + 1] = { lo = top, hi = 1, r = nil } end
  -- layout (only when something changed)
  local W = max(1, (b:GetWidth() or l.w) - 2)
  local parts = { key, floor(W + 0.5), floor((b:GetHeight() or l.h) + 0.5) }
  for _, zd in ipairs(zonesDef) do parts[#parts + 1] = tostring(zd.r) .. "/" .. zd.lo .. "/" .. zd.hi end
  local sig = table.concat(parts, ":")
  if b.haZoneSig ~= sig then
    b.haZoneSig = sig
    for i, zd in ipairs(zonesDef) do
      local z = b.haZones[i] or makeZone(b, i)
      z:ClearAllPoints()
      local x1, x2 = floor(1 + zd.lo * W + 0.5), floor(1 + zd.hi * W + 0.5)
      if i == 1 then x1 = 0 end
      if i == #zonesDef then x2 = W + 2 end
      z:SetPoint("TOPLEFT", b, "TOPLEFT", x1, 0)
      z:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", x1, 0)
      z:SetWidth(max(1, x2 - x1))
      z:Show()
    end
    for i = #zonesDef + 1, #b.haZones do b.haZones[i]:Hide() end
  end
  -- clicks: copy the frame's, the main smart heal (and other smart heals) cast the zone's rank
  local binds = CL().binds
  local unit = b:GetAttribute("unit")
  for i, zd in ipairs(zonesDef) do
    local z = b.haZones[i]
    setAttr(z, "unit", unit)
    local miss = (1 - (zd.lo + zd.hi) / 2) * 100
    z.haRankText = zd.r and (sname(key) .. " Rank " .. zd.r) or "nothing (not hurt enough)"
    for _, mod in ipairs(MODS) do
      local pre = mod ~= "" and (mod .. "-") or ""
      for btn = 1, 5 do
        local bind = binds[bindKey(mod, btn)]
        local typ, spell = b:GetAttribute(pre .. "type" .. btn), b:GetAttribute(pre .. "spell" .. btn)
        if isSecret(spell) then spell = nil end
        if type(bind) == "table" and (bind.kind == "smart" or bind.kind == "auto") and bind.key and knownKey(bind.key) then
          local r
          if bind.key == key then r = zd.r
          elseif zd.r then r = pickRank(bind.key, miss) end
          if r then typ, spell = "spell", castValue(bind.key, r) else typ, spell = "none", nil end
        end
        setAttr(z, pre .. "type" .. btn, typ)
        setAttr(z, pre .. "spell" .. btn, spell)
      end
    end
  end
end

---------------------------------------------------------------------------
-- Live rank in combat (the workaround).
-- In combat our Lua may not read health or change what a click casts. But two things
-- still work there:
--   1) a StatusBar fed the (secret) health draws its fill at the right width - the
--      client does that, our code never sees the number;
--   2) a secure snippet wrapped around the frame's OnClick runs as secure code: it may
--      read the size of protected frames and set the click's spell attributes, in combat.
-- So each frame gets an invisible "probe" StatusBar fed the health, and a protected frame
-- anchored to the fill's right edge. On every click the secure snippet measures
-- probe width / full width = health fraction, picks the rank from the steps (written
-- into attributes out of combat) and sets the spell for this very click. Auto clicks
-- measure every frame the same way for the group heal (no positions in combat: anyone
-- in the group counts as "near"). If the game refuses any of it, the click just casts
-- the "in combat" fallback rank that was set before the fight.
---------------------------------------------------------------------------
local secure
local LIVE_SNIPPET = [=[
  if not owner:GetAttribute("ha-live") then return end
  if not PlayerInCombat() and not self:GetAttribute("ha-blind") then return end
  local btn = (button == "LeftButton" and 1) or (button == "RightButton" and 2) or (button == "MiddleButton" and 3) or (button == "Button4" and 4) or (button == "Button5" and 5)
  if not btn then return end
  local sh, ct, al = IsShiftKeyDown(), IsControlKeyDown(), IsAltKeyDown()
  local mod = ""
  if sh and not ct and not al then mod = "shift-" elseif ct and not sh and not al then mod = "ctrl-" elseif al and not sh and not ct then mod = "alt-" elseif sh or ct or al then return end
  local sfx = mod .. btn
  local kind = self:GetAttribute("ha-k-" .. sfx)
  if not kind then return end
  local idx = self:GetAttribute("ha-i")
  local pr, fu = owner:GetFrameRef("p" .. idx), owner:GetFrameRef("f" .. idx)
  if not pr or not fu then return end
  local fw = fu:GetWidth()
  if not fw or fw <= 0 then return end
  local m = 1 - (pr:GetWidth() or fw) / fw
  if m < 0 then m = 0 elseif m > 1 then m = 1 end
  local use = ""
  if kind == "a" or kind == "g" then
    local gn = self:GetAttribute("ha-gn-" .. sfx) or 0
    if gn > 0 then
      local need = owner:GetAttribute("ha-gothers") or 2
      local mm = owner:GetAttribute("ha-gmin") or 0.1
      local jumps = self:GetAttribute("ha-gj-" .. sfx) or 2
      local me = self:GetAttribute("unit")
      local hurt, t1, t2, t3, t4 = 0, -1, -1, -1, -1
      for i = 1, 40 do
        local k = owner:GetFrameRef("k" .. i)
        if k and k:IsVisible() and k:GetAttribute("unit") and k:GetAttribute("unit") ~= me then
          local p2, f2 = owner:GetFrameRef("p" .. i), owner:GetFrameRef("f" .. i)
          local w2 = f2 and f2:GetWidth()
          if p2 and w2 and w2 > 0 then
            local x = 1 - (p2:GetWidth() or w2) / w2
            if x >= mm then hurt = hurt + 1 end
            if x > t1 then t4 = t3; t3 = t2; t2 = t1; t1 = x
            elseif x > t2 then t4 = t3; t3 = t2; t2 = x
            elseif x > t3 then t4 = t3; t3 = x
            elseif x > t4 then t4 = x end
          end
        end
      end
      if kind == "g" or (hurt >= need and m >= mm) then
        local v, sum, cnt = m, m, 1
        if jumps >= 1 and t1 >= 0 then if t1 < v then v = t1 end sum = sum + t1; cnt = cnt + 1 end
        if jumps >= 2 and t2 >= 0 then if t2 < v then v = t2 end sum = sum + t2; cnt = cnt + 1 end
        if jumps >= 3 and t3 >= 0 then if t3 < v then v = t3 end sum = sum + t3; cnt = cnt + 1 end
        if jumps >= 4 and t4 >= 0 then if t4 < v then v = t4 end sum = sum + t4; cnt = cnt + 1 end
        if owner:GetAttribute("ha-grule") == "avg" then v = sum / cnt end
        m = v; use = "g"
      end
    end
  end
  local n = self:GetAttribute("ha-" .. use .. "n-" .. sfx) or 0
  if n == 0 then return end
  local pick
  for i = 1, n do
    if m + 0.005 >= (self:GetAttribute("ha-" .. use .. "t-" .. sfx .. "-" .. i) or 2) then pick = i end
  end
  if not pick then
    if self:GetAttribute("ha-" .. use .. "skip-" .. sfx) then
      self:SetAttribute(mod .. "type" .. btn, "none")
      self:SetAttribute("ha-last", "skip")
      return
    end
    pick = 1
  end
  self:SetAttribute(mod .. "type" .. btn, "spell")
  self:SetAttribute(mod .. "spell" .. btn, self:GetAttribute("ha-" .. use .. "v-" .. sfx .. "-" .. pick))
  self:SetAttribute("ha-lastm", m)
  self:SetAttribute("ha-last", (self:GetAttribute("ha-" .. use .. "l-" .. sfx .. "-" .. pick) or "?"))
]=]

-- a spell's known ranks as the snippet needs them: { { th = fraction, v = cast value, l = label } } ascending
local function liveList(key)
  local R = ranks(key)
  local out = {}
  if not R or not R.max then return out end
  local f = 0
  for _, r in ipairs(R.list) do
    f = max(f, th(key, r))
    out[#out + 1] = { th = f / 100, v = castValue(key, r), l = (SPELLS[key].group and (key == "CH" and "CH" or "G") or "R") .. r }
  end
  return out
end
local function writeList(b, prefix, sfx, list, skip)
  local old = b.haA["n:" .. prefix .. sfx] or 0
  setAttr(b, "ha-" .. prefix .. "n-" .. sfx, #list > 0 and #list or nil)
  for i = 1, max(old, #list) do
    local e = list[i]
    setAttr(b, "ha-" .. prefix .. "t-" .. sfx .. "-" .. i, e and e.th or nil)
    setAttr(b, "ha-" .. prefix .. "v-" .. sfx .. "-" .. i, e and e.v or nil)
    setAttr(b, "ha-" .. prefix .. "l-" .. sfx .. "-" .. i, e and e.l or nil)
  end
  b.haA["n:" .. prefix .. sfx] = #list
  setAttr(b, "ha-" .. prefix .. "skip-" .. sfx, skip and true or nil)
end
function S.HealAssistLiveAttrs(b, mod, btn, bind)
  if combat() or not secure or not b.probe then return end
  local sfx = (mod ~= "" and (mod .. "-") or "") .. btn
  local kind
  if type(bind) == "table" and bind.key and knownKey(bind.key) then
    if bind.kind == "smart" then kind = SPELLS[bind.key].group and "g" or "s"
    elseif bind.kind == "auto" then kind = SPELLS[bind.key].group and "g" or "a" end
  end
  setAttr(b, "ha-k-" .. sfx, kind)
  if not kind then return end
  local single = (kind ~= "g") and liveList(bind.key) or {}
  writeList(b, "", sfx, single, spellCfg(bind.key).below == "skip")
  local g = (kind == "g") and bind.key or ((kind == "a" and CL().group.on) and groupKey() or nil)
  local glist = g and liveList(g) or {}
  writeList(b, "g", sfx, glist, false)
  setAttr(b, "ha-gj-" .. sfx, g and ((SPELLS[g].jumps or 3) - 1) or nil)
end
local function liveHandlerAttrs()
  if not secure or combat() then return end
  local c = CL()
  secure:SetAttribute("ha-live", (c.live and not S.HealAssistLiveBroken) and true or false)
  secure:SetAttribute("ha-gothers", c.group.minOthers)
  secure:SetAttribute("ha-gmin", c.group.minMiss / 100)
  secure:SetAttribute("ha-grule", c.group.rule)
end
S.HealAssistLiveHandler = liveHandlerAttrs
-- missing % of a unit from its frame's probe (when the game hides the numbers)
function S.HealAssistMeasure(u)
  for _, b in ipairs(kids) do
    if b.probe and b:IsShown() and b:GetAttribute("unit") == u then
      local fw, w = b.full:GetWidth(), b.probe:GetWidth()
      if fw and w and not isSecret(fw) and not isSecret(w) and fw > 0 then return max(0, min(100, (1 - w / fw) * 100)) end
    end
  end
end
-- out of combat: does the probe measure what the game says?
function S.HealAssistProbe(b)
  if not b or not b.probe then return nil end
  local fw = b.full:GetWidth()
  if not fw or fw <= 0 then return nil end
  local w = b.probe:GetWidth()
  if isSecret(w) or isSecret(fw) then return nil end
  return (1 - w / fw) * 100
end
-- the live-rank parts of one frame. The game refuses to anchor a protected frame to a
-- texture ("Cannot anchor protected frames to regions" - seen in game), so a plain frame
-- follows the bar's fill and the protected probe is anchored to that frame instead.
-- Any refusal only switches live rank off (S.HealAssistLiveBroken); the frame still works.
S.HealAssistLiveBroken = nil
local function buildProbe(b, i)
  b.pbar = b.pbar or CreateFrame("StatusBar", nil, b)
  b.pbar:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1); b.pbar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  b.pbar:SetStatusBarTexture(WHITE); b.pbar:SetMinMaxValues(0, 1); b.pbar:SetValue(1)
  b.pbar:SetAlpha(0)
  b.pbar:EnableMouse(false)
  b.follow = b.follow or CreateFrame("Frame", nil, b.pbar)
  b.follow:SetPoint("TOPLEFT", b.pbar, "TOPLEFT", 0, 0)
  b.follow:SetPoint("BOTTOMRIGHT", b.pbar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
  local probe = CreateFrame("Frame", nil, b, "SecureFrameTemplate")
  probe:SetAllPoints(b.follow)
  local full = CreateFrame("Frame", nil, b, "SecureFrameTemplate")
  full:SetAllPoints(b.pbar)
  b.probe, b.full = probe, full
  b:SetAttribute("ha-i", i)
  secure:SetFrameRef("k" .. i, b)
  secure:SetFrameRef("p" .. i, probe)
  secure:SetFrameRef("f" .. i, full)
  secure:WrapScript(b, "OnClick", LIVE_SNIPPET)
end
local function makeProbe(b, i)
  if b.probe or not secure or S.HealAssistLiveBroken then return end
  local ok, err = pcall(buildProbe, b, i)
  if not ok then
    S.HealAssistLiveBroken = tostring(err)
    b.probe, b.full = nil, nil
    S:Print("HealAssist: the game refused the live rank parts, so live rank in combat is off (" .. tostring(err):gsub("^.-:%d+: ", "") .. "). Everything else works.")
  end
end

---------------------------------------------------------------------------
-- Health text, live in combat. In combat the game hands addons "secret" numbers:
-- our code can't read or do maths on them, but the client can format them and the
-- game's own widgets can show them. So the secret value goes straight from the API
-- (UnitHealthPercent with the 0-100 curve constant, UnitHealthMissing, UnitHealth)
-- through string.format / AbbreviateNumbers into the FontString - the same client-side
-- path Blizzard's status-bar text uses - and never into a comparison or sum of ours.
-- Last resort: Blizzard's TextStatusBar_UpdateTextStringWithValues on the bar.
---------------------------------------------------------------------------
local textState = { blizz = nil }
local function fmt(pattern, ...)
  local ok, out = pcall(string.format, pattern, ...)
  if ok then return out end
end
local function abbrev(v)
  if v == nil then return nil end
  if AbbreviateNumbers then local ok, out = pcall(AbbreviateNumbers, v); if ok and out ~= nil then return out end end
  if not isSecret(v) and type(v) == "number" then
    if v >= 1000000 then return string.format("%.1fm", v / 1000000) elseif v >= 10000 then return string.format("%.1fk", v / 1000) end
    return tostring(floor(v + 0.5))
  end
  return fmt("%d", v) or fmt("%s", v)
end
local fullCurve   -- 1 when hurt, 0 at full health (hides "-0" in combat)
local function setFS(fs, text) if text == nil or not pcall(fs.SetText, fs, text) then fs:SetText("") return false end return true end
local function blizzText(b, u, cur, mx, mode)
  if textState.blizz == false or not TextStatusBar_UpdateTextStringWithValues then return false end
  local bar = b.hp
  bar.TextString = b.hpText
  bar.showPercentage = mode == "percent"; bar.showNumeric = mode ~= "percent"
  bar.lockShow = 1; bar.forceShow = true; bar.capNumericDisplay = true
  local ok = pcall(TextStatusBar_UpdateTextStringWithValues, bar, b.hpText, cur, 0, mx)
  if not ok then textState.blizz = false end
  return ok
end
local function healthText(b, u, cur, mx, dead)
  local mode = L().healthText or "percent"
  local fs = b.hpText
  fs:SetAlpha(1)
  if mode == "none" or dead then fs:SetText("") return end
  if not sec(cur, mx) and type(cur) == "number" and type(mx) == "number" then
    if mode == "percent" then fs:SetText(mx > 0 and (floor(cur / mx * 100 + 0.5) .. "%") or "")
    elseif mode == "deficit" then local d = mx - cur; fs:SetText(d > 0 and ("-" .. abbrev(d)) or "")
    else fs:SetText(abbrev(cur) or "") end
    return
  end
  -- hidden numbers (in combat)
  local done
  if mode == "percent" then
    local p = UnitHealthPercent and try(UnitHealthPercent, u, false, CurveConstants and CurveConstants.ScaleTo100)
    if p ~= nil then done = setFS(fs, fmt("%.0f%%", p) or fmt("%d%%", p)) end
  elseif mode == "deficit" then
    local miss = UnitHealthMissing and try(UnitHealthMissing, u)
    if miss ~= nil then
      local a = abbrev(miss)
      done = setFS(fs, a ~= nil and (fmt("-%s", a)) or nil)
      if done and UnitHealthPercent then
        if fullCurve == nil then fullCurve = newCurve(windowPoints(0, 0.999, curveState.scale)) or false end
        if fullCurve then local v = try(UnitHealthPercent, u, false, fullCurve); if v ~= nil then pcall(fs.SetAlpha, fs, v) end end
      end
    end
  else
    done = setFS(fs, abbrev(cur))
  end
  if not done then done = blizzText(b, u, cur, mx, mode) end
  if not done then fs:SetText("") end
end

-- the live part of a frame: bar, health text, combat rank badge
local function paintHealth(b, u)
  local cur, mx = try(UnitHealth, u), try(UnitHealthMax, u)
  pcall(b.hp.SetMinMaxValues, b.hp, 0, mx or 1)
  pcall(b.hp.SetValue, b.hp, cur or 0)
  if b.pbar then
    pcall(b.pbar.SetMinMaxValues, b.pbar, 0, mx or 1)
    pcall(b.pbar.SetValue, b.pbar, cur or 0)
  end
  local dead = bool(try(UnitIsDeadOrGhost, u)) or (UnitIsConnected and not bool(try(UnitIsConnected, u)))
  healthText(b, u, cur, mx, dead)
  return cur, mx
end


---------------------------------------------------------------------------
-- Dispels: a small button per cure your class has (Cure Poison, Remove Curse, Cleanse...)
-- at the end or the start of each bar. The game decides nothing here: each button always
-- casts its own spell on that person (also in combat). Out of combat the debuffs are read
-- and the button you need lights up, the bar takes the debuff colour and shows its name.
-- In combat WoW Forever refuses debuff data to addons; HealAssist still tries every read,
-- and when refused keeps what it saw last.
---------------------------------------------------------------------------
local DTYPES = { "Magic", "Curse", "Poison", "Disease" }
local DCOLOR = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.64, 0.19, 0.79 }, Poison = { 0.1, 0.65, 0.1 }, Disease = { 0.6, 0.4, 0 } }
local DISPELS = {     -- per class, best first for each type
  PRIEST  = { { name = "Dispel Magic", ids = { 527, 988 }, types = { Magic = true } },
              { name = "Abolish Disease", ids = { 552 }, types = { Disease = true } },
              { name = "Cure Disease", ids = { 528 }, types = { Disease = true } } },
  PALADIN = { { name = "Cleanse", ids = { 4987 }, types = { Poison = true, Disease = true, Magic = true } },
              { name = "Purify", ids = { 1152 }, types = { Poison = true, Disease = true } } },
  SHAMAN  = { { name = "Cure Poison", ids = { 526 }, types = { Poison = true } },
              { name = "Cure Disease", ids = { 2870 }, types = { Disease = true } } },
  DRUID   = { { name = "Remove Curse", ids = { 2782 }, types = { Curse = true } },
              { name = "Abolish Poison", ids = { 2893 }, types = { Poison = true } },
              { name = "Cure Poison", ids = { 8946 }, types = { Poison = true } } },
  MAGE    = { { name = "Remove Lesser Curse", ids = { 475 }, types = { Curse = true } } },
}
S.HEALASSIST_DISPELS = DISPELS
local dispelCache
local function knownByName(name)
  if not name then return nil end
  local id
  if C_Spell and C_Spell.GetSpellInfo then local t = try(C_Spell.GetSpellInfo, name); if type(t) == "table" and not isSecret(t.spellID) then id = t.spellID end end
  if not id and GetSpellInfo then local _, _, _, _, _, _, x = try(GetSpellInfo, name); id = x end
  if id and knownID(id) then return id end
end
-- the cure buttons your class has right now: { { name, id, icon, types, typeList } }
local function dispelButtons()
  if dispelCache then return dispelCache end
  local out, bySpell = {}, {}
  for _, t in ipairs(DTYPES) do
    for _, e in ipairs(DISPELS[myClass()] or {}) do
      if e.types[t] then
        local id
        for k = #e.ids, 1, -1 do if knownID(e.ids[k]) then id = e.ids[k] break end end
        local nm = spellName(e.ids[1]) or e.name
        id = id or knownByName(nm)
        if id then
          local btn = bySpell[e.name]
          if not btn then btn = { name = spellName(id) or nm, id = id, icon = spellIcon(id), types = {} }; bySpell[e.name] = btn; out[#out + 1] = btn end
          btn.types[t] = true
          break
        end
      end
    end
  end
  for _, btn in ipairs(out) do
    local t = {}
    for _, x in ipairs(DTYPES) do if btn.types[x] then t[#t + 1] = x end end
    btn.typeList = table.concat(t, ", ")
  end
  dispelCache = out
  return out
end
S.HealAssistDispelButtonsList = dispelButtons
local function canCure(t) for _, btn in ipairs(dispelButtons()) do if btn.types[t] then return true end end return false end
-- debuff types on a unit; nil when the game won't tell (in combat on Forever)
local function readDebuffs(u)
  local out = {}
  for i = 1, 40 do
    local t
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, "HARMFUL")
      if not ok then return nil end
      if a == nil then break end
      local ok2, v = pcall(function() return a.dispelName end)
      if not ok2 or isSecret(v) then return nil end
      t = v
    elseif UnitDebuff then
      local ok, name, _, _, dtype = pcall(UnitDebuff, u, i)
      if not ok then return nil end
      if not name then break end
      if isSecret(dtype) then return nil end
      t = dtype
    else return nil end
    if type(t) == "string" and DCOLOR[t] then out[t] = true end
  end
  return out
end
S.HealAssistReadDebuffs = readDebuffs

local function dispelTooltip(d)
  local info = d.haInfo
  if not info then return end
  GameTooltip:SetOwner(d, "ANCHOR_RIGHT")
  GameTooltip:AddLine(info.name, 1, 0.82, 0)
  GameTooltip:AddLine("Removes: " .. info.typeList, 1, 1, 1)
  GameTooltip:AddLine("Lights up when they have one (out of combat - the game hides debuffs in a fight).", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end
local function makeDispelButton(b, i)
  local fake = b.fakeIndex ~= nil
  local d = CreateFrame("Button", nil, b, (not fake) and "SecureUnitButtonTemplate" or nil)
  d:RegisterForClicks("AnyUp")
  d:SetFrameLevel(b:GetFrameLevel() + 14)
  d.edge = d:CreateTexture(nil, "BACKGROUND"); d.edge:SetAllPoints(); d.edge:SetColorTexture(0, 0, 0, 0.9)
  d.icon = d:CreateTexture(nil, "ARTWORK"); d.icon:SetPoint("TOPLEFT", 1, -1); d.icon:SetPoint("BOTTOMRIGHT", -1, 1); d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local hl = d:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(d.icon); hl:SetColorTexture(1, 1, 1, 0.25)
  d:HookScript("OnEnter", dispelTooltip)
  d:HookScript("OnLeave", function() GameTooltip:Hide() end)
  if fake then
    d:SetScript("OnClick", function(self)
      local data = S.HealAssistFakeData and S.HealAssistFakeData(b.fakeIndex)
      if data and data.debuff and self.haTypes and self.haTypes[data.debuff] then data.debuff = nil end
    end)
  end
  b.haDispel[i] = d
  return d
end
-- buttons: layout and spells (out of combat; test frames any time)
-- size of the cure buttons and the room they take beside a frame (0 when off)
-- buttons sit OUTSIDE the frame, stacked top to bottom, together as tall as the frame at most
local function dispelRoom()
  local l = L()
  local n = (l.dispel ~= "off") and #dispelButtons() or 0
  if n == 0 then return 0, 0, 0 end
  local h = l.h or 40
  local size = max(8, min(l.dispelSize or 16, floor((h - 2 * (n - 1)) / n)))
  return size, size + 3, n
end
S.HealAssistDispelRoom = dispelRoom
function S.HealAssistDispelButtons(b)
  if not b or (combat() and not b.fakeIndex) then return end
  b.haDispel = b.haDispel or {}
  local l = L()
  local list = (l.dispel ~= "off") and dispelButtons() or {}
  local size, _, n = dispelRoom()
  local total = n * size + (n - 1) * 2
  for i, info in ipairs(list) do
    local d = b.haDispel[i] or makeDispelButton(b, i)
    d:SetSize(size, size)
    d:ClearAllPoints()
    local y = total / 2 - (i - 1) * (size + 2)          -- stacked, centred on the frame's height
    if l.dispel == "left" then d:SetPoint("TOPRIGHT", b, "LEFT", -2, y)
    else d:SetPoint("TOPLEFT", b, "RIGHT", 2, y) end
    d.icon:SetTexture(info.icon)
    d.haInfo, d.haTypes = info, info.types
    if not b.fakeIndex then
      setAttr(d, "unit", b:GetAttribute("unit"))
      setAttr(d, "type1", "spell"); setAttr(d, "spell1", info.name)
      setAttr(d, "type2", "spell"); setAttr(d, "spell2", info.name)
    end
    d:Show()
  end
  for i = #list + 1, #b.haDispel do b.haDispel[i]:Hide() end
end

---------------------------------------------------------------------------
-- Debuffs drawn by the game (works in combat). WoW Forever ships Blizzard's AuraContainer
-- system (CustomAuraContainerTemplate): an addon creates a container and points it at a
-- unit; the game reads the auras in its own code and fills the container's buttons - the
-- addon only decides how they look and never sees the aura. Same route as Decursive's
-- Forever build and other Forever frame addons.
--   * per frame: one slot with the filter HARMFUL|RAID_PLAYER_DISPELLABLE (only debuffs
--     you can remove); its button covers the frame and carries a wash over the bar,
--     tinted by the game in the debuff type's colour, plus the type name (SetDispelTypeText)
--   * per cure button: the same slot on a tiny container; its glow uses a colour map where
--     the types that button can't cure are black on an ADD blend = invisible, so only the
--     right button lights up
-- If the client lacks the template, the old (out-of-combat only) reading is used.
---------------------------------------------------------------------------
local engine = { ok = nil }
local function colorObj(c) if CreateColor then return CreateColor(c[1], c[2], c[3], 1) end return { r = c[1], g = c[2], b = c[3] } end
local function dispelColorMap(onlyTypes)
  local m = {}
  for _, t in ipairs(DTYPES) do
    if not onlyTypes or onlyTypes[t] then m[t] = colorObj(DCOLOR[t]) else m[t] = colorObj({ 0, 0, 0 }) end
  end
  m.None = colorObj(onlyTypes and { 0, 0, 0 } or { 0.8, 0, 0 })
  return m
end
local function newContainer(parent)
  if engine.ok == false then return nil end
  local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
  if not ok or not c then engine.ok = false; engine.why = tostring(c); return nil end
  engine.ok = true
  if c.EnableMouse then pcall(c.EnableMouse, c, false) end
  return c
end
-- the slot's one button: size it, keep clicks going to the frame underneath, then dress it
local function slotOptions(dress)
  return {
    initializeFrame = function(a, b2)
      local btn = (type(b2) == "table" and b2.SetSize) and b2 or a
      if type(btn) ~= "table" then return end
      pcall(btn.EnableMouse, btn, false)
      if btn.SetMouseClickEnabled then pcall(btn.SetMouseClickEnabled, btn, false) end
      if btn.SetMouseMotionEnabled then pcall(btn.SetMouseMotionEnabled, btn, false) end
      pcall(dress, btn)
    end,
  }
end
local function sizeSlotButton(c, w, h)
  if not c or not c.GetChildren then return end
  for _, ch in ipairs({ c:GetChildren() }) do pcall(ch.SetSize, ch, w, h) end
end
-- frame-wide wash + type name
local function makeFrameWatch(b)
  local c = newContainer(b)
  if not c then return nil end
  c:SetAllPoints(b)
  c:SetFrameLevel(b.hp:GetFrameLevel() + 1)
  local opts = slotOptions(function(btn)
    btn:SetSize(b:GetWidth() or 92, b:GetHeight() or 40)
    local wash = btn:CreateTexture(nil, "ARTWORK")
    wash:SetPoint("TOPLEFT", 1, -1); wash:SetPoint("BOTTOMRIGHT", -1, 1)
    wash:SetTexture(WHITE); wash:SetAlpha(L().dispelWash or 0.6)
    btn:AddDispelTypeTexture(wash, { style = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset or 3,
      showWhenHarmful = true, customDispelColorMap = dispelColorMap(nil) })
    btn.haWash = wash
    if btn.SetDispelTypeText then
      local fs = btn:CreateFontString(nil, "OVERLAY")
      fs:SetFontObject(UI.fSmall or GameFontNormalSmall)
      local font, size = fs:GetFont(); if font then fs:SetFont(font, size, "OUTLINE") end
      fs:SetPoint("CENTER", 0, -1)
      pcall(btn.SetDispelTypeText, btn, fs, {})
      btn.haText = fs
    end
    b.haWatchBtn = btn
  end)
  local ok, err = pcall(c.AddAuraSlot, c, "hadispel", "HARMFUL|RAID_PLAYER_DISPELLABLE", opts)
  if not ok then engine.ok = false; engine.why = tostring(err); c:Hide(); return nil end
  return c
end
-- glow on a cure button, only for the types it cures
local function makeCureWatch(d, types)
  local c = newContainer(d)
  if not c then return nil end
  c:SetAllPoints(d)
  c:SetFrameLevel(d:GetFrameLevel() + 2)
  local opts = slotOptions(function(btn)
    btn:SetSize(d:GetWidth() or 16, d:GetHeight() or 16)
    local glow = btn:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("TOPLEFT", -2, 2); glow:SetPoint("BOTTOMRIGHT", 2, -2)
    glow:SetTexture(WHITE); glow:SetBlendMode("ADD"); glow:SetAlpha(0.55)
    btn:AddDispelTypeTexture(glow, { style = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset or 3,
      showWhenHarmful = true, customDispelColorMap = dispelColorMap(types) })
  end)
  local ok = pcall(c.AddAuraSlot, c, "hacure", "HARMFUL|RAID_PLAYER_DISPELLABLE", opts)
  if not ok then c:Hide(); return nil end
  return c
end
-- create / point / size the watchers of a frame (out of combat)
function S.HealAssistAuraWatch(b)
  if not b or b.fakeIndex or combat() then return end
  local l = L()
  local u = b:GetAttribute("unit")
  local want = l.dispelEngine and l.dispel ~= "off" or (l.dispelEngine and (l.dispelColor or l.dispelText))
  if not want or engine.ok == false then
    if b.haWatch then b.haWatch:Hide() end
    for _, d in ipairs(b.haDispel or {}) do if d.haWatch then d.haWatch:Hide() end end
    return
  end
  if not b.haWatch then b.haWatch = makeFrameWatch(b) end
  local c = b.haWatch
  if c then
    c:SetShown(l.dispelColor or l.dispelText)
    if b.haWatchUnit ~= u then b.haWatchUnit = u; pcall(c.SetUnit, c, u) end
    sizeSlotButton(c, b:GetWidth(), b:GetHeight())
    if b.haWatchBtn then
      if b.haWatchBtn.haWash then b.haWatchBtn.haWash:SetShown(l.dispelColor and true or false); b.haWatchBtn.haWash:SetAlpha(l.dispelWash or 0.6) end
      if b.haWatchBtn.haText then b.haWatchBtn.haText:SetShown(l.dispelText and true or false) end
    end
  end
  for _, d in ipairs(b.haDispel or {}) do
    if d:IsShown() and d.haTypes then
      local sig = d.haInfo and d.haInfo.typeList or ""
      if d.haWatch and d.haWatchSig ~= sig then d.haWatch:Hide(); d.haWatch = nil end
      if not d.haWatch then d.haWatch = makeCureWatch(d, d.haTypes); d.haWatchSig = sig end
      if d.haWatch then
        d.haWatch:Show()
        if d.haWatchUnit ~= u then d.haWatchUnit = u; pcall(d.haWatch.SetUnit, d.haWatch, u) end
        sizeSlotButton(d.haWatch, d:GetWidth(), d:GetHeight())
      end
    elseif d.haWatch then d.haWatch:Hide() end
  end
end
local function engineOn(b) return L().dispelEngine and engine.ok and b and b.haWatch ~= nil end
S.HealAssistEngine = engine

-- colour / text / which button is needed (in and out of combat, display only)
local function paintDispel(b, u, fake)
  local l = L()
  local deb
  if not fake and engineOn(b) then
    if b.dispelText then b.dispelText:SetText("") end
    for _, d in ipairs(b.haDispel or {}) do
      if d:IsShown() then pcall(d.SetAlpha, d, 1); d.edge:SetColorTexture(0, 0, 0, 0.9) end
    end
    return
  end
  if fake then deb = fake.debuff and { [fake.debuff] = true } or {}
  else
    local nowT = GetTime()
    if b.haDebDirty or not b.haDebAt or nowT - b.haDebAt > 1 then
      b.haDebDirty, b.haDebAt = nil, nowT
      local d = readDebuffs(u)
      if d then b.haDeb = d end      -- refused (combat): keep what we saw last
    end
    deb = b.haDeb or {}
  end
  local show, names = nil, {}
  for _, t in ipairs(DTYPES) do
    if deb[t] and (not l.dispelMine or canCure(t)) then
      show = show or t
      local c = DCOLOR[t]
      names[#names + 1] = string.format("|cff%02x%02x%02x%s|r", floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255), t)
    end
  end
  if show and l.dispelColor then
    local c = DCOLOR[show]
    b.hp:SetStatusBarColor(c[1], c[2], c[3])
    b.hp.bg:SetColorTexture(c[1] * 0.18, c[2] * 0.18, c[3] * 0.18, 0.95)
  end
  if b.dispelText then
    b.dispelText:SetText((show and l.dispelText) and table.concat(names, " ") or "")
  end
  for _, d in ipairs(b.haDispel or {}) do
    if d:IsShown() then
      local need
      for _, t in ipairs(DTYPES) do if d.haTypes and d.haTypes[t] and deb[t] then need = need or t end end
      pcall(d.SetAlpha, d, need and 1 or l.dispelIdle)
      if need then local c = DCOLOR[need]; d.edge:SetColorTexture(c[1], c[2], c[3], 1) else d.edge:SetColorTexture(0, 0, 0, 0.9) end
    end
  end
end

local paintBadges
local function paint(b)
  local u = b:GetAttribute("unit")
  if not u or not exists(u) then return end
  local l = L()
  paintHealth(b, u)
  local r, g, bl = 0.3, 0.85, 0.4
  if l.classColor then r, g, bl = classRGB(u) end
  b.hp:SetStatusBarColor(r, g, bl)
  b.hp.bg:SetVertexColor(1, 1, 1, 1); b.hp.bg:SetColorTexture(r * 0.18, g * 0.18, bl * 0.18, 0.95)
  local nm = try(UnitName, u)
  if not pcall(b.name.SetText, b.name, nm or "") then b.name:SetText("") end
  local dead, ghost, off = bool(try(UnitIsDead, u)), bool(try(UnitIsGhost, u)), UnitIsConnected and not bool(try(UnitIsConnected, u))
  local st = off and "Offline" or ghost and "Ghost" or dead and "Dead" or nil
  b.status:SetText(st or "")
  b.tgt:SetShown(same(u, "target"))
  pcall(paintDispel, b, u)
  -- range
  if l.rangeFade and not same(u, "player") then
    local inR, checked = try(UnitInRange, u)
    if sec(inR, checked) then
      if b.SetAlphaFromBoolean then pcall(b.SetAlphaFromBoolean, b, inR, 1, l.rangeAlpha) end
    elseif checked then b:SetAlpha(inR and 1 or l.rangeAlpha) else b:SetAlpha(1) end
  else b:SetAlpha(1) end
  -- rank marks + badges
  local key = primaryKey()
  layoutMarks(b, key)
  local fight = combat()
  -- health hidden: the game turns health into the rank number for the badge (live, also in combat)
  if l.badge and key and not st and healthHidden(u) and not (fight and l.combatBadge and curveState.ok ~= false) then
    local v = hcValue(u, key, "rank")
    local txt = v ~= nil and (fmt("R%d", v) or fmt("R%.0f", v)) or nil
    if txt ~= nil and pcall(b.badge.SetText, b.badge, txt) then
      b.badge:SetTextColor(1, 0.82, 0); b.badge:Show(); b.badgeBg:Show()
      for _, fs in ipairs(b.cbadges) do fs:Hide() end
      b.haBadgeHC = true
      return
    end
  end
  b.haBadgeHC = nil
  b.badge:SetShown(l.badge and not fight and not st and b.haBadgeText ~= nil)
  b.badgeBg:SetShown(b.badge:IsShown())
  if l.badge and not fight then
    local t = b.haBadgeText or ""
    if t:sub(1, 1) ~= "R" then t = "|cff66ddff" .. t .. "|r" else t = "|cffffd100" .. t .. "|r" end
    b.badge:SetText(t)
  end
  paintBadges(b, u, key, fight and not st)
end
paintBadges = function(b, u, key, show)
  local l = L()
  if not combat() then
    detectScale()
    if key and l.combatBadge and curveState.ok == nil then buildCurves(key) end   -- builds + checks the curves before the fight
  end
  local list = (l.combatBadge and key and show) and buildCurves(key) or nil
  for i = 1, max(#b.cbadges, list and #list or 0) do
    local cv = list and list[i]
    local fs = b.cbadges[i]
    if cv and curveState.ok ~= false then
      if not fs then
        fs = UI:Text(b.over, "", "small", "RIGHT"); fs:SetPoint("BOTTOMRIGHT", -6, 5)
        local font, size = fs:GetFont(); if font then fs:SetFont(font, size, "OUTLINE") end
        b.cbadges[i] = fs
      end
      local combo, castR = comboFor(key, cv.r)
      if combo then
        -- what to press for this health: the click and the rank it casts
        fs:SetText("|cffffffff" .. combo .. "|r |cffffd100R" .. castR .. "|r")
      else
        fs:SetText("|cffffd100R" .. cv.r .. "|r")
      end
      local v = try(UnitHealthPercent, u, false, cv.curve)
      if v == nil or not pcall(fs.SetAlpha, fs, v) then curveState.ok = false; fs:Hide() else fs:Show() end
    elseif fs then fs:Hide() end
  end
end

local function eachKid(fn) for _, b in ipairs(kids) do if b:IsShown() then fn(b) end end end
-- unit token -> frame, for instant health updates between ticks
local byUnit = {}
local function mapUnits()
  for k in pairs(byUnit) do byUnit[k] = nil end
  for _, b in ipairs(kids) do
    if b:IsShown() then local u = b:GetAttribute("unit"); if u then byUnit[u] = b end end
  end
end
local function collectKids()
  if not header then return end
  for i = 1, 40 do
    local b = header:GetAttribute("child" .. i) or _G[header:GetName() .. "UnitButton" .. i]
    if b and not b.haIndex then
      b.haIndex = i
      local ok, err = pcall(styleKid, b)
      if not ok and S.report then S.report(err) end
      makeProbe(b, i)
      kids[#kids + 1] = b
    end
  end
end

local function applyLayout()
  if not header then return end
  if combat() then pending = true return end
  pending = false
  local l = L()
  anchor:SetScale(l.scale or 1)
  for _, b in ipairs(kids) do b:SetSize(l.w, l.h); b.haMarkSig = nil end
  header:SetAttribute("haW", l.w); header:SetAttribute("haH", l.h)
  if l.orient == "rows" then
    header:SetAttribute("point", "LEFT"); header:SetAttribute("xOffset", l.spacing + select(2, dispelRoom())); header:SetAttribute("yOffset", 0)
    header:SetAttribute("columnAnchorPoint", "TOP")
  else
    header:SetAttribute("point", "TOP"); header:SetAttribute("xOffset", 0); header:SetAttribute("yOffset", -l.spacing)
    header:SetAttribute("columnAnchorPoint", "LEFT")
  end
  header:SetAttribute("columnSpacing", l.spacing + (l.orient == "rows" and 0 or select(2, dispelRoom())))
  if S.HealAssistSelfBtn then
    local room = select(2, dispelRoom())
    S.HealAssistSelfBtn:ClearAllPoints()
    S.HealAssistSelfBtn:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -10 - room - ((l.dispel == "left") and room or 0), 0)
  end
  header:SetAttribute("unitsPerColumn", l.perCol)
  header:SetAttribute("maxColumns", ceil(40 / max(1, l.perCol)))
  header:SetAttribute("showSolo", (l.solo or not l.locked) and true or false)
  if S.HealAssistSelfBtn then S.HealAssistSelfBtn:SetShown(l.on and l.selfTest and true or false) end
  if l.on and not test.on then header:Show() else header:Hide() end
  if test.on then placeTest() end
  anchor.handle:SetShown(not l.locked)
  liveHandlerAttrs()
  for _, b in ipairs(kids) do updateClicks(b) end
end
S.HealAssistLayout = applyLayout

local function savePos()
  local p, _, rp, x, y = anchor:GetPoint()
  L().at = { p, rp, x, y }
end
local ticker
local tickN = 0
local testTickRef
local function tick()
  if testTickRef then testTickRef() end
  if not header or not header:IsShown() then return end
  local fight = combat()
  tickN = tickN + 1
  mapUnits()
  local clicks = not fight and (tickN % 2 == 1)    -- clicks every 0.3 s, the look every 0.15 s
  eachKid(function(b)
    if clicks then updateClicks(b) end
    paint(b)
  end)
end

S.HealAssistTick = function() local ok, err = pcall(tick); if not ok and S.report then S.report(err) end return ok, err end
local buildFrames

---------------------------------------------------------------------------
-- Test mode: a made-up group with health that changes on its own, drawn with the
-- same look, rank marks, badges and health text - every setting you change shows at
-- once. Left-click a test frame = heal it with the rank the badge shows, right-click =
-- hit it. Plain (not secure) frames, so it's out-of-combat only; the real group frames
-- step aside while it runs.
---------------------------------------------------------------------------
local FAKE = {
  { "Grumbash", "WARRIOR" }, { nil, nil }, { "Shadowkiss", "ROGUE" }, { "Frostella", "MAGE" }, { "Lightwell", "PRIEST" },
  { "Ironhide", "PALADIN" }, { "Thornpaw", "DRUID" }, { "Bolttusk", "SHAMAN" }, { "Darkpact", "WARLOCK" }, { "Hawkeye", "HUNTER" },
}
local function fakeRGB(cls)
  local c = cls and ((C_ClassColor and C_ClassColor.GetClassColor and try(C_ClassColor.GetClassColor, cls)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]))
  if c then return c.r, c.g, c.b end
  return 0.3, 0.85, 0.4
end
local function fakeData(i)
  local d = test.data[i]
  if d then return d end
  local f = FAKE[((i - 1) % #FAKE) + 1]
  local name, cls = f[1], f[2]
  if not name then
    if i == 2 then name = (try(UnitName, "player") or "You"); cls = myClass() else name, cls = "Brightmend", "PRIEST" end
  end
  if i > #FAKE then name = name .. " " .. ceil(i / #FAKE) end
  d = { name = name, cls = cls, max = 4000 + ((i * 937) % 3000), tank = (i == 1) }
  d.hp = d.max * (0.6 + ((i * 53) % 40) / 100)
  test.data[i] = d
  return d
end
local function fakeMiss(d) return (d.max - d.hp) / d.max * 100 end
S.HealAssistFakeData = function(i) return fakeData(i) end
-- what a left click would cast on fake i (same rules as the real frames)
local function fakeResolve(i)
  local b = CL().binds["|1"]
  if type(b) ~= "table" or not b.key or not (b.kind == "smart" or b.kind == "auto" or b.kind == "max" or b.kind == "rank") then return nil end
  local key = b.key
  local R = ranks(key)
  if not R or not R.max then return nil end
  if b.kind == "max" then return key, R.max end
  if b.kind == "rank" then local r; for _, x in ipairs(R.list) do if x <= (tonumber(b.rank) or 1) then r = x end end return key, r or R.list[1] end
  local d = fakeData(i)
  local m0 = fakeMiss(d)
  local function clusterValue(g)
    local gr, sp = CL().group, SPELLS[g]
    local others = {}
    for j = 1, test.size do if j ~= i then others[#others + 1] = fakeMiss(fakeData(j)) end end
    table.sort(others, function(a, c) return a > c end)
    local hurt = 0
    for _, m in ipairs(others) do if m >= gr.minMiss then hurt = hurt + 1 end end
    local take = { m0 }
    for k = 1, min(#others, (sp.jumps or 3) - 1) do take[#take + 1] = others[k] end
    local v, sum = m0, 0
    for _, m in ipairs(take) do v = min(v, m); sum = sum + m end
    if gr.rule == "avg" then v = sum / #take end
    return hurt >= gr.minOthers and m0 >= gr.minMiss, v
  end
  if b.kind == "auto" and CL().group.on then
    local g = groupKey()
    if g and g ~= key then
      local ok, v = clusterValue(g)
      if ok then local r = pickRank(g, v); if r then return g, r end end
    end
  end
  if SPELLS[key].group then local _, v = clusterValue(key); return key, pickRank(key, v) end
  return key, pickRank(key, m0)
end
local function badgeFor(key, r)
  if not key or not r then return nil end
  return (SPELLS[key].group and (key == "CH" and "CH" or "G") or "R") .. r
end

placeTest = function()
  local l = L()
  for i, b in ipairs(test.frames) do
    b:SetSize(l.w, l.h); b.haMarkSig = nil
    b:ClearAllPoints()
    if i <= test.size then
      local k = i - 1
      local col, row = floor(k / max(1, l.perCol)), k % max(1, l.perCol)
      local x, y
      local room = select(2, dispelRoom())
      if l.orient == "rows" then x, y = row * (l.w + l.spacing + room), -col * (l.h + l.spacing)
      else x, y = col * (l.w + l.spacing + room), -row * (l.h + l.spacing) end
      b:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
      b:Show()
      if S.HealAssistDispelButtons then S.HealAssistDispelButtons(b) end
    else b:Hide() end
  end
end
local function paintTest(b, i)
  local l, d = L(), fakeData(i)
  b.hp:SetMinMaxValues(0, d.max); b.hp:SetValue(d.hp)
  local r, g, bl = 0.3, 0.85, 0.4
  if l.classColor then r, g, bl = fakeRGB(d.cls) end
  b.hp:SetStatusBarColor(r, g, bl)
  b.hp.bg:SetColorTexture(r * 0.18, g * 0.18, bl * 0.18, 0.95)
  b.name:SetText(d.name)
  b.status:SetText("")
  b.tgt:SetShown(i == 1)
  pcall(paintDispel, b, nil, d)
  b:SetAlpha((l.rangeFade and i == test.size and test.size > 3) and l.rangeAlpha or 1)   -- the last one shows the out-of-range fade
  healthText(b, nil, d.hp, d.max, false)
  layoutMarks(b, primaryKey())
  local key, rk = fakeResolve(i)
  local t = badgeFor(key, rk)
  b.badge:SetShown(l.badge and t ~= nil)
  b.badgeBg:SetShown(b.badge:IsShown())
  if t then b.badge:SetText((t:sub(1, 1) == "R" and "|cffffd100" or "|cff66ddff") .. t .. "|r") end
  b.fakeKey, b.fakeRank = key, rk
  for _, fs in ipairs(b.cbadges) do fs:Hide() end
end
-- health drifts: hits on the tank, random hits, now and then a hit on everyone
local function driftTest()
  for i = 1, test.size do
    local d = fakeData(i)
    local roll = math.random()
    if roll < (d.tank and 0.10 or 0.025) then d.hp = d.hp - d.max * (0.04 + math.random() * (d.tank and 0.18 or 0.25)) end
    d.hp = d.hp + d.max * 0.004
  end
  if math.random() < 0.012 then
    for i = 1, test.size do local d = fakeData(i); d.hp = d.hp - d.max * (0.08 + math.random() * 0.17) end
  end
  -- now and then a debuff (any type, so "only ones I can remove" shows too); fades after a while
  for i = 1, test.size do
    local d = fakeData(i)
    if not d.debuff and math.random() < 0.006 then d.debuff = ({ "Magic", "Curse", "Poison", "Disease" })[math.random(1, 4)]; d.debuffT = 0 end
    if d.debuff then d.debuffT = (d.debuffT or 0) + 1; if d.debuffT > 140 then d.debuff = nil end end
  end
  for i = 1, test.size do local d = fakeData(i); d.hp = max(d.max * 0.05, min(d.max, d.hp)) end
end
local function testTick()
  if not test.on then return end
  driftTest()
  for i = 1, test.size do local b = test.frames[i]; if b then paintTest(b, i) end end
end
local function testFrame(i)
  local b = test.frames[i]
  if b then return b end
  b = CreateFrame("Button", nil, anchor)
  b.fakeIndex = i
  styleKid(b)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, btn)
    local d = fakeData(self.fakeIndex)
    if btn == "RightButton" then d.hp = max(d.max * 0.05, d.hp - d.max * 0.15)
    else
      -- heal with what the badge says: a bigger rank heals more (rank x 6% of max health here)
      local r = self.fakeRank or 1
      local amt = d.max * 0.06 * r
      if self.fakeKey and SPELLS[self.fakeKey].group then
        local hit = { self.fakeIndex }
        local list = {}
        for j = 1, test.size do if j ~= self.fakeIndex then list[#list + 1] = j end end
        table.sort(list, function(a, c) return fakeMiss(fakeData(a)) > fakeMiss(fakeData(c)) end)
        for k = 1, min(#list, (SPELLS[self.fakeKey].jumps or 3) - 1) do hit[#hit + 1] = list[k] end
        for _, j in ipairs(hit) do local x = fakeData(j); x.hp = min(x.max, x.hp + amt) end
      else d.hp = min(d.max, d.hp + amt) end
    end
    paintTest(self, self.fakeIndex)
  end)
  test.frames[i] = b
  return b
end
function S.HealAssistTestOn() return test.on end
function S.HealAssistTest(on, size)
  if on and combat() then S:Print("HealAssist: test mode works out of combat only.") return end
  if size then test.size = size end
  if on == nil then on = not test.on end
  if on and not anchor then buildFrames() end
  if not anchor then return end
  test.on = on and true or false
  if test.on then
    for i = 1, test.size do testFrame(i) end
    placeTest()
    if header then header:Hide() end
    testTick()
  else
    for _, b in ipairs(test.frames) do b:Hide() end
    applyLayout()     -- brings the real group frames back
  end
  if S.RefreshHealAssist then S:RefreshHealAssist() end
end
S.HealAssistTestTick = testTick
testTickRef = testTick

buildFrames = function()
  if anchor then return end
  anchor = CreateFrame("Frame", "CC_HealAssistAnchor", UIParent)
  anchor:SetSize(20, 20); anchor:SetClampedToScreen(true); anchor:SetMovable(true)
  local at = L().at
  if type(at) == "table" and at[1] then anchor:SetPoint(at[1], UIParent, at[2] or at[1], at[3] or 0, at[4] or 0)
  else anchor:SetPoint("LEFT", UIParent, "LEFT", 260, 80) end
  local h = CreateFrame("Frame", nil, anchor, BACKDROP_T)
  h:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2); h:SetSize(170, 18)
  if h.SetBackdrop then h:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }); h:SetBackdropColor(0, 0, 0, 0.8); h:SetBackdropBorderColor(C(UI:Theme().gold)) end
  h.t = UI:Text(h, "HealAssist - drag to move", "small", "CENTER"); h.t:SetPoint("CENTER")
  h:EnableMouse(true); h:RegisterForDrag("LeftButton")
  h:SetScript("OnDragStart", function() if not combat() then anchor:StartMoving() end end)
  h:SetScript("OnDragStop", function() anchor:StopMovingOrSizing(); savePos() end)
  anchor.handle = h
  anchor:SetSize(20, 20)

  secure = CreateFrame("Frame", "CC_HealAssistSecure", UIParent, "SecureHandlerBaseTemplate")
  header = CreateFrame("Frame", "CC_HealAssistGroup", anchor, "SecureGroupHeaderTemplate")
  header:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
  header:SetAttribute("template", "SecureUnitButtonTemplate")
  header:SetAttribute("initialConfigFunction", [[
    local h = self:GetParent()
    self:SetWidth(h:GetAttribute("haW") or 92)
    self:SetHeight(h:GetAttribute("haH") or 40)
  ]])
  header:SetAttribute("showRaid", true)
  header:SetAttribute("showParty", true)
  header:SetAttribute("showPlayer", true)
  header:SetAttribute("groupBy", "GROUP")
  header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
  local l = L()
  header:SetAttribute("haW", l.w); header:SetAttribute("haH", l.h)
  -- make all 40 buttons now so nothing has to be built in combat
  header:SetAttribute("startingIndex", -39)
  header:Show()
  header:SetAttribute("startingIndex", 1)
  collectKids()
  -- the updates start first, so nothing below can leave the frames blank
  if not ticker then ticker = C_Timer.NewTicker(0.15, S.PerfWrap and S.PerfWrap("HealAssist  0.15 s tick", S.HealAssistTick) or S.HealAssistTick) end
  -- test frame: always you, even in a group (index 41 = outside the group heal count)
  local okMe, errMe = pcall(function()
    local me = CreateFrame("Button", "CC_HealAssistSelf", anchor, "SecureUnitButtonTemplate")
    me:SetSize(l.w, l.h)
    me:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -10, 0)
    me:SetAttribute("unit", "player")
    me.haIndex = 41
    styleKid(me); makeProbe(me, 41)
    me.testTag = UI:Text(me.over, "|cffff9933TEST|r", "small", "LEFT"); me.testTag:SetPoint("BOTTOMLEFT", me, "TOPLEFT", 0, 2)
    me:Hide()
    kids[#kids + 1] = me
    S.HealAssistSelfBtn = me
  end)
  if not okMe and S.report then S.report(errMe) end
  applyLayout()
end

function S.HealAssistTooltip(b)
  if b.fakeIndex then
    local d = fakeData(b.fakeIndex)
    GameTooltip_SetDefaultAnchor(GameTooltip, b)
    GameTooltip:AddLine(d.name .. "  |cffff9933(test)|r")
    GameTooltip:AddLine(string.format("Missing %d%%", floor(fakeMiss(d) + 0.5)), 1, 1, 1)
    GameTooltip:AddDoubleLine("Left click", b.fakeKey and rankLabel(b.fakeKey, b.fakeRank) or "|cff777777nothing|r", 0.9, 0.8, 0.5, 1, 1, 1)
    GameTooltip:AddLine("Right click: hit them for 15%", 0.6, 0.6, 0.6)
    GameTooltip:Show()
    return
  end
  local u = b:GetAttribute("unit")
  if not u then return end
  GameTooltip_SetDefaultAnchor(GameTooltip, b)
  pcall(GameTooltip.SetUnit, GameTooltip, u)
  local m = missingPct(u)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("HealAssist" .. (m and string.format("  |cffaaaaaamissing %d%%|r", floor(m + 0.5)) or ""), 0.31, 0.82, 0.77)
  local binds = CL().binds
  for _, mod in ipairs(MODS) do for btn = 1, 5 do
    local bk = bindKey(mod, btn)
    local bd = binds[bk]
    if type(bd) == "table" and bd.kind and bd.kind ~= "none" then
      local label = b.haLabel[bk] or "?"
      local extra = ""
      if combat() and (bd.kind == "smart" or bd.kind == "auto") then
        local cm = CL().combat
        if CL().live then extra = " |cff55ff55(rank picked on click)|r"
        else extra = " |cffff9933(" .. (cm == "keep" and "last rank" or cm == "mid" and "middle rank" or cm == "low" and "rank 1" or "max rank") .. " in combat)|r" end
      end
      GameTooltip:AddDoubleLine(bindLabel(mod, btn), label .. extra, 0.9, 0.8, 0.5, 1, 1, 1)
    end
  end end
  local last = b:GetAttribute("ha-last")
  if last ~= nil then
    local m = b:GetAttribute("ha-lastm")
    local txt = (type(m) == "number" and not isSecret(m)) and string.format("%s at %d%% missing", tostring(last), floor(m * 100 + 0.5)) or tostring(last)
    pcall(GameTooltip.AddLine, GameTooltip, "Last combat click: " .. txt, 0.6, 0.9, 0.6)
  end
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Cast check: after a click, compare the rank we asked for with the rank the game
-- actually cast. If casting by spell ID gives a different rank (newer clients may
-- "upgrade" a low rank ID to your best rank), switch to casting by name (Rank N).
---------------------------------------------------------------------------
local lastClick, lastCast, lastLog
local BTNNUM = { LeftButton = 1, RightButton = 2, MiddleButton = 3, Button4 = 4, Button5 = 5 }
-- spell ID -> key, rank (for every rank we know of)
local function idInfo(id)
  if type(id) ~= "number" or isSecret(id) then return nil end
  for _, key in ipairs(classKeys()) do
    for r, x in ipairs(SPELLS[key].ids) do if x == id then return key, r end end
    local R = ranks(key)
    if R then for r, x in pairs(R.byRank) do if x == id then return key, r end end end
  end
end
local function valueInfo(v)
  if isSecret(v) then return nil end
  if type(v) == "number" then return idInfo(v) end
  if type(v) == "string" then
    local name, r = v:match("^(.-)%(Rank (%d+)%)$")
    if name then
      for _, key in ipairs(classKeys()) do if sname(key) == name or SPELLS[key].name == name then return key, tonumber(r) end end
    end
  end
end
-- click log (saved, last 25): what we saw and set on each click, for bug reports
local function raw(v) if v == nil then return "nil" end if isSecret(v) then return "secret" end return tostring(v) end
local function logClick(b, button, mod, n)
  local h = store()
  h.diag = type(h.diag) == "table" and h.diag or {}
  local u = b:GetAttribute("unit")
  local e = {
    t = date and date("%H:%M:%S") or "", frame = b:GetName() or ("#" .. tostring(b.haIndex)), unit = tostring(u), btn = mod .. n,
    combat = combat() and true or false, type = raw(b:GetAttribute(mod .. "type" .. n)), spell = raw(b:GetAttribute(mod .. "spell" .. n)),
    kind = raw(b:GetAttribute("ha-k-" .. mod .. n)), blind = raw(b:GetAttribute("ha-blind")), last = raw(b:GetAttribute("ha-last")),
    lastm = raw(b:GetAttribute("ha-lastm")), castBy = L().castBy, live = CL().live and true or false, broken = S.HealAssistLiveBroken,
    hcOK = raw(hc.attrOK), hcBadge = b.haBadgeHC and true or false, badge = raw(b.badge and b.badge:GetText()), curveScale = curveState.scale,
  }
  if u then
    e.hp = raw(try(UnitHealth, u)); e.hpmax = raw(try(UnitHealthMax, u))
    e.pct = raw(UnitHealthPercent and try(UnitHealthPercent, u))
    e.missing = raw(missingPct(u))
    if b.probe then e.probeW = raw(b.probe:GetWidth()); e.fullW = raw(b.full:GetWidth()); e.followW = raw(b.follow and b.follow:GetWidth()) end
    if b.pbar then local okv, v = pcall(b.pbar.GetValue, b.pbar); e.pbarV = okv and raw(v) or "err" end
  end
  table.insert(h.diag, 1, e)
  while #h.diag > 25 do table.remove(h.diag) end
  return e
end
function S.HealAssistNoteClick(b, button)
  local n = BTNNUM[button]
  if not n then return end
  do
    local m0 = (IsShiftKeyDown() and "shift-") or (IsControlKeyDown() and "ctrl-") or (IsAltKeyDown() and "alt-") or ""
    local ok, e = pcall(logClick, b, button, m0, n)
    if ok then lastLog = e end
  end
  local mod = (IsShiftKeyDown() and "shift-") or (IsControlKeyDown() and "ctrl-") or (IsAltKeyDown() and "alt-") or ""
  if (IsShiftKeyDown() and 1 or 0) + (IsControlKeyDown() and 1 or 0) + (IsAltKeyDown() and 1 or 0) > 1 then return end
  if b:GetAttribute(mod .. "type" .. n) ~= "spell" then return end
  local v = b:GetAttribute(mod .. "spell" .. n)
  if isSecret(v) then
    -- a spell ID picked by the game from health: make sure the game really casts from it
    local myClick = GetTime()
    hc.pending = myClick
    if C_Timer then C_Timer.After(1.2, function()
      if hc.pending ~= myClick then return end
      hc.pending = nil
      hc.misses = hc.misses + 1
      if hc.misses >= 2 and hc.attrOK ~= true then
        hc.attrOK = false
        if not combat() then for _, x in ipairs(kids) do updateClicks(x) end end
        S:Print("HealAssist: the game won't cast from a rank it picked itself - back to the old rules (smart clicks cast your top rank while health is hidden).")
      end
    end) end
    return
  end
  local key, r = valueInfo(v)
  if key then lastClick = { key = key, rank = r, t = GetTime(), value = v } end
end
local function onCast(_, unit, a2, a3, a4)
  if unit == "player" and hc.pending then hc.pending = nil; hc.misses = 0; hc.attrOK = true end
  if unit ~= "player" or not lastClick or GetTime() - lastClick.t > 1.5 then return end
  -- UNIT_SPELLCAST_SENT: unit, target, castGUID, spellID   /   SUCCEEDED: unit, castGUID, spellID
  local id = (type(a4) == "number" and a4) or (type(a3) == "number" and a3) or nil
  if isSecret(id) then return end
  if lastLog and not lastLog.castID then lastLog.castID = id end
  local key, r = idInfo(id)
  if not key or key ~= lastClick.key then return end
  local want = lastClick
  lastClick = nil
  lastCast = { want = want.rank, got = r, key = key, by = L().castBy, t = time() }
  if r == want.rank then return end
  if L().castBy ~= "name" then
    L().castBy = "name"
    if S.HealAssistLiveHandler then S.HealAssistLiveHandler() end
    if not combat() then for _, b in ipairs(kids) do updateClicks(b) end end
    S:Print(string.format("HealAssist: you asked for %s Rank %d but the game cast Rank %d - switched to casting by name (\"%s(Rank N)\"). Try again%s.",
      sname(key), want.rank, r, sname(key), combat() and " after this fight" or ""))
    if S.RefreshHealAssist then S:RefreshHealAssist() end
  else
    S:Print(string.format("HealAssist: asked for %s Rank %d, the game cast Rank %d even by name. Please send me " .. CMD .. " check.", sname(key), want.rank, r))
  end
end
S:On("UNIT_SPELLCAST_SENT", onCast)
-- out of range / out of mana etc. still means the click tried to cast
S:On("UI_ERROR_MESSAGE", function() if hc.pending then hc.pending = nil end end)
S:On("UNIT_SPELLCAST_SUCCEEDED", onCast)
function S.HealAssistLastCast() return lastCast end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function refreshRanks()
  rankCache = nil
  dispelCache = nil
  if header and not combat() then applyLayout() end
  curveState.sig = nil
  if header and not combat() then for _, b in ipairs(kids) do b.haMarkSig = nil; updateClicks(b) end end
  if S.RefreshHealAssist then S:RefreshHealAssist() end
end
S:On("PLAYER_REGEN_DISABLED", function()
  -- the last moment we may still change clicks: smart clicks switch to the combat rank
  if not header then return end
  if test.on then S.HealAssistTest(false); S:Print("HealAssist: test mode ended (combat).") end
  for _, b in ipairs(kids) do pcall(updateClicks, b, true) end
end)
S:On("PLAYER_REGEN_ENABLED", function()
  if not header then return end
  if pending then applyLayout() end
  for _, b in ipairs(kids) do updateClicks(b) end
end)
for _, ev in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP" }) do
  S:On(ev, function() if C_Timer then C_Timer.After(0.5, refreshRanks) else refreshRanks() end end)
end
-- health changes repaint that frame at once (bar + text + combat badge), in and out of combat
local function onHealth(_, u)
  if u == "player" and S.HealAssistSelfBtn and S.HealAssistSelfBtn:IsShown() then
    local me = S.HealAssistSelfBtn
    paintHealth(me, "player")
    if combat() then paintBadges(me, "player", primaryKey(), not bool(try(UnitIsDeadOrGhost, "player"))) end
  end
  local b = u and byUnit[u]
  if not b or not b:IsShown() or b:GetAttribute("unit") ~= u then return end
  paintHealth(b, u)
  if combat() then
    local st = bool(try(UnitIsDeadOrGhost, u))
    paintBadges(b, u, primaryKey(), not st)
  end
end
for _, ev in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH", "UNIT_CONNECTION" }) do S:On(ev, onHealth) end
S:On("UNIT_AURA", function(_, u) local b = u and byUnit[u]; if b then b.haDebDirty = true end end)
S:On("GROUP_ROSTER_UPDATE", function() if header and not combat() then for _, b in ipairs(kids) do updateClicks(b) end end end)
S:Listen("LOGIN", function()
  CL()
  if not L().on then return end
  if combat() then
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(self) self:UnregisterAllEvents(); buildFrames() end)
  else buildFrames() end
end)

-- In-combat rank ladder: Shift / Ctrl / Alt + left click get three ranks spread over what
-- you know; left click stays smart (exact rank out of combat, your fallback rank in combat).
-- The badge then shows which click to press for the health you see.
function S.HealAssistLadder(key)
  key = key or primaryKey()
  local R = key and ranks(key)
  if not R or not R.max then S:Print("HealAssist: no known ranks for a rank ladder yet.") return end
  local L0, n = R.list, #R.list
  local function at(f) return L0[max(1, min(n, ceil(n * f)))] end
  local b = CL().binds
  b["|1"] = { kind = "smart", key = key }
  b["shift|1"] = { kind = "rank", key = key, rank = at(0.25) }
  b["ctrl|1"] = { kind = "rank", key = key, rank = at(0.5) }
  b["alt|1"] = { kind = "rank", key = key, rank = at(0.75) }
  if CL().combat == "keep" then CL().combat = "max" end
  if not combat() then for _, x in ipairs(kids) do x.haMarkSig = nil; updateClicks(x) end end
  local c = CL().combat
  local fb = (c == "mid" and R.list[ceil(n / 2)]) or (c == "low" and R.list[1]) or R.max
  S:Print(string.format("HealAssist rank ladder for %s: Shift-Left = Rank %d, Ctrl-Left = Rank %d, Alt-Left = Rank %d, Left = exact rank out of combat / Rank %d in combat. The badge shows which click to press.",
    sname(key), at(0.25), at(0.5), at(0.75), fb))
  if S.RefreshHealAssist then S:RefreshHealAssist() end
end

---------------------------------------------------------------------------
-- Custom spells: any spell you add (by name, spell ID or dragged from the spellbook)
-- can be bound to clicks and gets rank steps like the built-in heals. Ranks come from
-- your spellbook ("Rank N"); spells without ranks act as one rank. Saved per class.
---------------------------------------------------------------------------
syncCustom = function()
  if not S.db then return end
  customSynced = true
  local cls = myClass()
  for i = #customKeys, 1, -1 do SPELLS[customKeys[i]] = nil; customKeys[i] = nil end
  for _, e in ipairs(CL().custom) do
    local id = tonumber(e.id)
    if id then
      local key = "X" .. id
      if not SPELLS[key] then
        SPELLS[key] = { class = cls, name = e.name or spellName(id) or ("Spell " .. id), ids = {}, custom = true, baseID = id }
        customKeys[#customKeys + 1] = key
      end
    end
  end
end
local function findSpell(text)
  text = S.Trim(text or "")
  if text == "" then return nil end
  local n = tonumber(text)
  if n then return spellName(n) and n or nil end
  if C_Spell and C_Spell.GetSpellInfo then
    local t = try(C_Spell.GetSpellInfo, text)
    if type(t) == "table" and t.spellID then return t.spellID end
  end
  if GetSpellInfo then local _, _, _, _, _, _, id = try(GetSpellInfo, text); if id then return id end end
end
local function customChanged()
  customSynced = false
  rankCache = nil
  curveState.sig = nil
  if S.HealAssistRefreshAll then S.HealAssistRefreshAll() end
  if S.RefreshHealAssist then S:RefreshHealAssist() end
  if S.HealAssistRefreshCustom then S.HealAssistRefreshCustom() end
end
function S.HealAssistAddSpell(id)
  id = tonumber(id)
  if not id then return false end
  local name = spellName(id)
  if not name then return false end
  for _, e in ipairs(CL().custom) do
    local en = e.name or spellName(e.id)
    if tonumber(e.id) == id or (en and en:lower() == name:lower()) then return false, "already added" end
  end
  for _, k in ipairs(ORDER) do
    if SPELLS[k].class == myClass() and (SPELLS[k].name:lower() == name:lower() or (spellName(SPELLS[k].ids[1]) or ""):lower() == name:lower()) then
      return false, "already built in"
    end
  end
  table.insert(CL().custom, { id = id, name = name })
  customChanged()
  return true
end
function S.HealAssistRemoveSpell(id)
  id = tonumber(id)
  local key = "X" .. tostring(id)
  local list = CL().custom
  for i = #list, 1, -1 do if tonumber(list[i].id) == id then table.remove(list, i) end end
  for _, b in pairs(CL().binds) do if type(b) == "table" and b.key == key then b.kind = "none"; b.key = nil end end
  CL().spells[key] = nil
  customChanged()
end

local cwin
function S.HealAssistRefreshCustom()
  if not cwin or not cwin:IsShown() then return end
  local list = CL().custom
  for i, row in ipairs(cwin.rows) do
    local e = list[i]
    if e then
      local key = "X" .. tostring(e.id)
      local R = ranks(key)
      local info = (R and R.max) and (R.unranked and "no ranks" or (#R.list .. " rank" .. (#R.list > 1 and "s" or "") .. " known")) or "|cffff7777not known by you|r"
      row.icon:SetTexture((R and R.icon) or spellIcon(e.id)); row.icon:Show()
      row.text:SetText((e.name or spellName(e.id) or "?") .. "  |cffaaaaaa" .. info .. "|r")
      row.rm.id = e.id; row.rm:Show()
    else
      row.icon:Hide(); row.text:SetText(""); row.rm:Hide()
    end
  end
  cwin.empty:SetShown(#list == 0)
end
function S:ShowHealAssistSpells()
  if not cwin then
    cwin = UI:Window("CC_HealAssistSpells", "HealAssist - your spells", 420, 430)
    local hint = UI:Text(cwin, "|cffaaaaaaAdd any spell to use it in click bindings (any class: Holy Light, Flash Heal, Rejuvenation, Cleanse...). Type its name or spell ID, or drag it here from your spellbook. Its ranks come from your spellbook; smart clicks and rank zones use its steps on the Ranks tab.|r", "small")
    hint:SetPoint("TOPLEFT", 16, -40); hint:SetWidth(388); hint:SetJustifyH("LEFT")
    local function add(id)
      local ok, why = S.HealAssistAddSpell(id)
      if not ok then UI:Alert(why == "already added" and "That spell is already in your list." or why == "already built in" and "That spell is already built in - pick it straight from the click menus." or "Couldn't find that spell.") end
    end
    local box
    if S.RotKit and S.RotKit.spellBox then
      box = S.RotKit.spellBox(cwin, 280, "Spell name or ID, or drag one here", add)
    else
      box = UI:Edit(cwin, 280, 24, "Spell name or ID", function(_, text) local id = findSpell(text); if id then add(id) else UI:Alert("Couldn't find \"" .. tostring(text) .. "\".") end end)
    end
    box:SetPoint("TOPLEFT", 16, -96)
    local addB = UI:PrimaryButton(cwin, "Add", 80, 24, function()
      local h = box:GetScript("OnEnterPressed"); if h then h(box) end
    end)
    addB:SetPoint("LEFT", box, "RIGHT", 8, 0)
    cwin.rows = {}
    for i = 1, 10 do
      local y = -132 - (i - 1) * 28
      local row = {}
      row.icon = cwin:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(20, 20); row.icon:SetPoint("TOPLEFT", 18, y - 2)
      row.text = UI:Text(cwin, "", "normal"); row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0); row.text:SetWidth(260); row.text:SetWordWrap(false)
      row.rm = UI:Button(cwin, "|cffff7777Remove|r", 72, 20, function(self) if self.id then S.HealAssistRemoveSpell(self.id) end end)
      row.rm:SetPoint("TOPRIGHT", -16, y)
      cwin.rows[i] = row
    end
    cwin.empty = UI:Text(cwin, "|cff888888No spells added yet.|r", "small"); cwin.empty:SetPoint("TOPLEFT", 18, -136)
    cwin:HookScript("OnShow", function() rankCache = nil; S.HealAssistRefreshCustom() end)
  end
  cwin:Show(); cwin:Raise()
  S.HealAssistRefreshCustom()
end

---------------------------------------------------------------------------
-- Settings window
---------------------------------------------------------------------------
local win, panes = nil, {}
local W, H = 600, 680
local KINDS = {
  { value = "none", text = "Nothing" },
  { value = "auto", text = "Auto heal (group heal when needed)" },
  { value = "smart", text = "Smart heal (rank by health)" },
  { value = "max", text = "Max rank" },
  { value = "rank", text = "A set rank" },
  { value = "target", text = "Target" },
  { value = "menu", text = "Unit menu" },
}
local function refreshAll()
  if S.HealAssistLiveHandler then S.HealAssistLiveHandler() end
  curveState.sig = nil
  if header and not combat() then for _, b in ipairs(kids) do b.haMarkSig = nil; updateClicks(b) end end
  curveState.sig = nil
end
S.HealAssistRefreshAll = function() refreshAll() end
local function spellOptions()
  local out = {}
  for _, k in ipairs(classKeys()) do
    out[#out + 1] = { value = k, text = sname(k) .. (knownKey(k) and "" or " |cff777777(not learned)|r") }
  end
  return out
end
local function rankOptions(key)
  local out = {}
  local R = ranks(key)
  for r = 1, max(1, topRank(key)) do
    out[#out + 1] = { value = r, text = "Rank " .. r .. ((R and R.byRank[r]) and "" or " |cff777777-|r") }
  end
  return out
end

local function buildClicks(p)
  local hint = UI:Text(p, "|cffaaaaaaPick what each click does on a HealAssist frame. |cffffd100Smart|r|cffaaaaaa = the rank is chosen from how much health the person is missing (steps on the Ranks tab). |cffffd100Auto|r|cffaaaaaa = smart, but switches to your group heal when the people around them are hurt too (Group heal tab).|r", "small")
  hint:SetPoint("TOPLEFT", 14, -6); hint:SetWidth(W - 28); hint:SetJustifyH("LEFT")
  local sf, child = UI:Scroll(p, W - 16, 320)
  sf:SetPoint("TOPLEFT", 8, -50)
  child:SetHeight(20 * 28 + 8)
  p.rows = {}
  local y = -4
  for _, mod in ipairs(MODS) do for btn = 1, 5 do
    local bk = bindKey(mod, btn)
    local row = { key = bk }
    row.label = UI:Text(child, bindLabel(mod, btn), "small"); row.label:SetPoint("TOPLEFT", 6, y - 6); row.label:SetWidth(100)
    local function cur() local b = CL().binds[bk]; if type(b) ~= "table" then b = { kind = "none" }; CL().binds[bk] = b end return b end
    local function changed() refreshAll(); S:RefreshHealAssist() end
    row.kind = UI:Dropdown(child, 210, KINDS, "none", function(v)
      local b = cur(); b.kind = v
      if (v == "smart" or v == "auto" or v == "max" or v == "rank") and not b.key then b.key = classKeys()[1] end
      if v == "rank" and not b.rank then b.rank = 1 end
      changed()
    end)
    row.kind:SetPoint("TOPLEFT", 108, y)
    row.spell = UI:Dropdown(child, 150, spellOptions, nil, function(v) cur().key = v; changed() end)
    row.spell:SetPoint("LEFT", row.kind, "RIGHT", 6, 0)
    row.rank = UI:Dropdown(child, 80, function() return rankOptions(cur().key) end, 1, function(v) cur().rank = v; changed() end)
    row.rank:SetPoint("LEFT", row.spell, "RIGHT", 6, 0)
    function row:Refresh()
      local b = CL().binds[bk]
      local kind = type(b) == "table" and b.kind or "none"
      self.kind:SetValue(kind)
      local spelly = kind == "smart" or kind == "auto" or kind == "max" or kind == "rank"
      self.spell:SetShown(spelly); self.rank:SetShown(kind == "rank")
      if spelly then self.spell:SetValue(b.key); self.spell.text:SetText(sname(b.key) .. (knownKey(b.key) and "" or " |cff777777(not learned)|r")) end
      if kind == "rank" then self.rank:SetValue(tonumber(b.rank) or 1); self.rank.text:SetText("Rank " .. tostring(b.rank or 1)) end
    end
    p.rows[#p.rows + 1] = row
    y = y - 28
  end end
  local yb = -378
  local cl = UI:Text(p, "Fallback in combat:", "small"); cl:SetPoint("TOPLEFT", 14, yb - 5)
  p.combat = UI:Dropdown(p, 150, { { value = "max", text = "The max rank" }, { value = "mid", text = "The middle rank" },
    { value = "low", text = "Rank 1" }, { value = "keep", text = "The rank gauged before the fight" } }, CL().combat, function(v) CL().combat = v end)
  p.combat:SetPoint("TOPLEFT", 250, yb)
  p.live = UI:Check(p, "Live rank in combat", CL().live, function(v) CL().live = v; refreshAll() end,
    { "Experimental workaround: every click measures the person's health bar with a secure snippet and casts the matching rank - in combat too.", "If the game refuses it, the click casts the rank picked on the left instead." })
  p.live:SetPoint("LEFT", p.combat, "RIGHT", 12, 0)
  p.live:Hide()   -- blocked on WoW Forever (protected frames can't follow the health bar); zones replace it
  p.zones = UI:Check(p, "Rank zones on the health bar", L().zones, function(v) L().zones = v; refreshAll() end,
    { "Click where the green bar ends: each part of the bar casts the rank for that health - also in combat.", "Shift / Ctrl / Alt clicks and right clicks still do what you set here." })
  p.zones:SetPoint("LEFT", p.combat, "RIGHT", 12, 0)
  yb = yb - 30
  local cb = UI:Text(p, "Cast ranks by:", "small"); cb:SetPoint("TOPLEFT", 14, yb - 5)
  p.castBy = UI:Dropdown(p, 200, { { value = "id", text = "Spell ID (default)" }, { value = "name", text = "Name (Rank N)" } }, L().castBy,
    function(v) L().castBy = v; refreshAll() end)
  p.castBy:SetPoint("TOPLEFT", 250, yb)
  UI:Tip(p.castBy, "Cast ranks by", { "Switch to \"Name (Rank N)\" only if a smart click casts the wrong rank or nothing at all." })
  yb = yb - 32
  local note = UI:Text(p, "|cffff9933Picking the rank|r |cffaaaaaaWoW Forever hides health from addons and locks what a click casts. Two ways that work, also in combat: |cffffd100Rank zones|r|cffaaaaaa - click where the green bar ends and that part of the bar casts the rank for that health; |cffffd100Rank ladder|r|cffaaaaaa - Shift / Ctrl / Alt + left click cast set ranks and the badge shows which click fits.|r", "small")
  note:SetPoint("TOPLEFT", 14, yb); note:SetWidth(W - 28); note:SetJustifyH("LEFT")
  local lad = UI:Button(p, "Rank ladder", 120, 22, function()
    UI:Confirm("Set Shift / Ctrl / Alt + left click to three ranks of your main heal, for picking the rank in combat?\n(Your current Shift / Ctrl / Alt + left clicks are replaced.)", function() S.HealAssistLadder() end, "Set")
  end, "In combat the game won't let a click change rank by itself. This binds three ranks to Shift / Ctrl / Alt + left click; the badge on each frame shows which click fits the health right now.")
  lad:SetPoint("BOTTOMRIGHT", -140, 14)
  local cus = UI:Button(p, "Your spells...", 120, 22, function() S:ShowHealAssistSpells() end,
    "Add any spell (any class) to use in these click menus - by name, spell ID or dragged from your spellbook.")
  cus:SetPoint("BOTTOMLEFT", 14, 14)
  local def = UI:Button(p, "Default clicks", 120, 22, function()
    UI:Confirm("Put every click back to the defaults for your class?", function() CL().binds = defaultBinds(myClass()); refreshAll(); S:RefreshHealAssist() end, "Reset")
  end)
  def:SetPoint("BOTTOMRIGHT", -14, 14)
  function p:Refresh()
    for _, r in ipairs(self.rows) do r:Refresh() end
    self.combat:SetValue(CL().combat); self.castBy:SetValue(L().castBy); self.live:SetChecked(CL().live and true or false)
    self.live.label:SetText(S.HealAssistLiveBroken and "Live rank in combat |cffff7777(blocked by the game)|r" or "Live rank in combat")
    self.zones:SetChecked(L().zones and true or false)
  end
end


---------------------------------------------------------------------------
-- Ranks page, visual view: a health bar laid out like the frames (full health on the
-- right, empty on the left). Each rank's step is a tick on the bar with a pin above it;
-- drag a pin left/right to move the step. Coloured bands show which rank each part of
-- the bar casts. Hover the bar to read "missing X% -> Rank N". Right-click a pin = default.
---------------------------------------------------------------------------
local BAND = { { 0.25, 0.75, 0.35 }, { 0.2, 0.55, 0.9 }, { 0.85, 0.65, 0.15 }, { 0.75, 0.3, 0.8 }, { 0.9, 0.4, 0.3 }, { 0.3, 0.8, 0.8 } }
-- clamp a step between its neighbours (steps never go down with rank)
local function clampStep(key, r, v)
  v = max(0, min(100, floor(v + 0.5)))
  if r > 1 then v = max(v, th(key, r - 1)) end
  if r < topRank(key) then v = min(v, th(key, r + 1)) end
  return v
end
local function setStep(key, r, v)
  if not key or not r then return end
  spellCfg(key).th[r] = clampStep(key, r, v)
end
S.HealAssistSetStep = setStep
local function buildRankVisual(p, top, height)
  local v = CreateFrame("Frame", nil, p)
  v:SetPoint("TOPLEFT", 14, top); v:SetPoint("TOPRIGHT", -14, top); v:SetHeight(height)
  p.vis = v
  local BW = W - 28 - 40
  local hint = UI:Text(v, "|cffaaaaaaDrag a pin to move that rank's step. The bar looks like a heal frame: full health on the right, empty on the left. Right-click a pin to reset it.|r", "small")
  hint:SetPoint("TOPLEFT", 6, -2); hint:SetWidth(W - 40); hint:SetJustifyH("LEFT")
  -- zoom
  local zl = UI:Text(v, "Show up to:", "small"); zl:SetPoint("TOPLEFT", 6, -38)
  v.zoom = UI:Dropdown(v, 170, { { value = 25, text = "25% missing" }, { value = 50, text = "50% missing" }, { value = 100, text = "100% missing (whole bar)" } }, L().rankRange,
    function(val) L().rankRange = val; p:Refresh() end)
  v.zoom:SetPoint("TOPLEFT", 80, -32)
  -- the bar
  local bar = CreateFrame("Frame", nil, v)
  bar:SetSize(BW, 30); bar:SetPoint("TOPLEFT", 20, -170)
  local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
  local edge = bar:CreateTexture(nil, "BORDER"); edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1); edge:SetColorTexture(0, 0, 0, 1)
  bg:SetDrawLayer("BACKGROUND", 1)
  v.bar, v.BW = bar, BW
  v.bands, v.pins = {}, {}
  -- scale under the bar
  v.scale = {}
  for i = 1, 5 do
    local fs = UI:Text(v, "", "small"); fs:SetTextColor(0.6, 0.6, 0.6)
    v.scale[i] = fs
  end
  v.leftLab = UI:Text(v, "", "small"); v.leftLab:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -22)
  v.rightLab = UI:Text(v, "|cff55ff55full health|r", "small"); v.rightLab:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -22)
  -- hover readout
  v.cursor = bar:CreateTexture(nil, "OVERLAY"); v.cursor:SetWidth(1); v.cursor:SetColorTexture(1, 1, 1, 0.8)
  v.cursor:SetPoint("TOP", bar, "TOPLEFT", 0, 0); v.cursor:SetHeight(30); v.cursor:Hide()
  v.read = UI:Text(v, "", "small"); v.read:SetPoint("TOP", bar, "BOTTOM", 0, -40)
  local range = function() return L().rankRange or 50 end
  -- missing % <-> x on the bar (missing 0 = right edge, missing = range at the left edge)
  function v:XFor(miss) return BW * (1 - min(miss, range()) / range()) end
  function v:MissAt(x) return (1 - max(0, min(BW, x)) / BW) * range() end
  local function cursorX()
    local cx = GetCursorPosition and GetCursorPosition() or 0
    local sc = bar:GetEffectiveScale() or 1
    return cx / sc - (bar:GetLeft() or 0)
  end
  bar:EnableMouse(true)
  bar:SetScript("OnUpdate", function()
    if not bar:IsMouseOver() or v.dragging then if not v.dragging then v.cursor:Hide() end return end
    local x = cursorX()
    local m = floor(v:MissAt(x) + 0.5)
    v.cursor:ClearAllPoints(); v.cursor:SetPoint("TOP", bar, "TOPLEFT", x, 0); v.cursor:Show()
    local r = p.key and pickRank(p.key, m)
    v.read:SetText("Missing " .. m .. "% -> " .. (r and ("|cffffd100Rank " .. r .. "|r") or "|cff777777no cast|r"))
  end)
  bar:SetScript("OnLeave", function() v.cursor:Hide(); v.read:SetText("") end)
  local function pin(i)
    if v.pins[i] then return v.pins[i] end
    local pn = CreateFrame("Button", nil, v)
    pn:SetSize(30, 20)
    pn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pn.bg = pn:CreateTexture(nil, "BACKGROUND"); pn.bg:SetAllPoints(); pn.bg:SetColorTexture(0.15, 0.15, 0.15, 1)
    pn.bd = pn:CreateTexture(nil, "BORDER"); pn.bd:SetPoint("TOPLEFT", -1, 1); pn.bd:SetPoint("BOTTOMRIGHT", 1, -1); pn.bd:SetColorTexture(0, 0, 0, 1)
    pn.bg:SetDrawLayer("BACKGROUND", 1)
    pn.text = UI:Text(pn, "", "small"); pn.text:SetPoint("CENTER", 0, 0)
    pn.stem = v:CreateTexture(nil, "ARTWORK"); pn.stem:SetWidth(1)
    pn.tick = bar:CreateTexture(nil, "OVERLAY"); pn.tick:SetSize(2, 30)
    pn.val = UI:Text(v, "", "small")
    -- drag ends on release anywhere: the pin's own OnMouseUp / OnDragStop, or the game's
    -- GLOBAL_MOUSE_UP (the release often happens off the pin when it stopped at a
    -- neighbour / the edge). (r20 polled IsMouseButtonDown - that reads "not held" on
    -- Forever and dropped the pin at once.)
    -- tooltip: shown on hover and kept up to date while dragging
    local function pinTip(self)
      if not GameTooltip or not p.key then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      local val = th(p.key, self.rank)
      GameTooltip:AddLine("Rank " .. self.rank .. ": " .. val .. "% missing or more", 1, 0.82, 0)
      if v.dragging == self then
        GameTooltip:AddLine("Release to set it.", 0.6, 1, 0.6)
      else
        GameTooltip:AddLine("Drag left/right to move. Right-click: default.", 0.8, 0.8, 0.8)
      end
      self.tipVal = val
      GameTooltip:Show()
    end
    local function stopDrag(self)
      if v.dragging ~= self then return end
      self:SetScript("OnUpdate", nil)
      v.dragging = nil
      refreshAll(); p:Refresh()
      if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self then
        if self:IsMouseOver() then pinTip(self) else GameTooltip:Hide() end
      end
    end
    pn.StopDrag = stopDrag
    pn:SetScript("OnMouseDown", function(self, btn)
      if btn ~= "LeftButton" or not p.key then return end
      if v.dragging and v.dragging ~= self then v.dragging:StopDrag() end
      v.dragging = self
      pinTip(self)
      self:SetScript("OnUpdate", function()
        local m = v:MissAt(cursorX())
        setStep(p.key, self.rank, m)
        v:Layout(true)
        p:RefreshText()
        if th(p.key, self.rank) ~= self.tipVal then pinTip(self) end   -- live % while dragging
      end)
    end)
    pn:SetScript("OnMouseUp", function(self, btn)
      if btn == "RightButton" and p.key and not v.dragging then
        spellCfg(p.key).th[self.rank] = nil
        refreshAll(); p:Refresh()
        return
      end
      stopDrag(self)
    end)
    pn:SetScript("OnHide", function(self) stopDrag(self) end)
    pn:RegisterForDrag("LeftButton")
    pn:SetScript("OnDragStart", function() end)            -- keeps the mouse captured by the pin
    pn:SetScript("OnDragStop", function(self) stopDrag(self) end)
    pn:SetScript("OnEnter", function(self) if not v.dragging then pinTip(self) end end)
    pn:SetScript("OnLeave", function(self) if GameTooltip and v.dragging ~= self then GameTooltip:Hide() end end)
    v.pins[i] = pn
    return pn
  end
  local function band(i)
    if v.bands[i] then return v.bands[i] end
    local t = bar:CreateTexture(nil, "ARTWORK")
    t.label = UI:Text(v, "", "small")
    v.bands[i] = t
    return t
  end
  -- place everything; dragOnly = skip the scale (cheaper while dragging)
  function v:Layout(dragOnly)
    local key = p.key
    -- never Hide() a pin that stays on screen: hiding the pin being dragged makes the game
    -- drop it (and lose its mouse-up). Only pins past the last rank are hidden.
    local n = key and min(12, topRank(key)) or 0
    for i, pn in ipairs(self.pins) do if i > n then pn:Hide(); pn.stem:Hide(); pn.tick:Hide(); pn.val:Hide() end end
    for _, t in ipairs(self.bands) do t:Hide(); t.label:Hide() end
    if not key then return end
    local R = ranks(key)
    local rg = range()
    -- bands: what each part of the bar casts
    local wins = rankWindows(key)
    local bi = 0
    for _, w in ipairs(wins) do
      local mLo, mHi = (1 - w.hi) * 100, (1 - w.lo) * 100         -- missing range of this window
      if mLo < rg then
        local x1, x2 = self:XFor(min(mHi, rg)), self:XFor(mLo)
        if x2 - x1 >= 1 then
          bi = bi + 1
          local t = band(bi)
          local c = BAND[((w.r - 1) % #BAND) + 1]
          t:ClearAllPoints(); t:SetPoint("TOPLEFT", bar, "TOPLEFT", x1, 0); t:SetSize(x2 - x1, 30)
          t:SetColorTexture(c[1], c[2], c[3], 0.75); t:Show()
          if x2 - x1 >= 22 then t.label:ClearAllPoints(); t.label:SetPoint("CENTER", bar, "LEFT", (x1 + x2) / 2, 0); t.label:SetText("R" .. w.r); t.label:Show() end
        end
      end
    end
    local first = wins[1] and wins[1].hi or 0
    if first < 1 and spellCfg(key).below == "skip" then
      local mTop = (1 - first) * 100
      local x1 = self:XFor(min(mTop, rg))
      if BW - x1 >= 1 then
        bi = bi + 1
        local t = band(bi)
        t:ClearAllPoints(); t:SetPoint("TOPLEFT", bar, "TOPLEFT", x1, 0); t:SetSize(BW - x1, 30)
        t:SetColorTexture(0.25, 0.25, 0.25, 0.9); t:Show()
        if BW - x1 >= 40 then t.label:ClearAllPoints(); t.label:SetPoint("CENTER", bar, "LEFT", (x1 + BW) / 2, 0); t.label:SetText("|cff999999no cast|r"); t.label:Show() end
      end
    end
    -- pins: two staggered rows so close steps don't overlap
    local lastX = { -100, -100 }
    for r = 1, n do
      local pn = pin(r)
      pn.rank = r
      local val = th(key, r)
      local have = R and R.byRank[r]
      local x = self:XFor(val)
      local off = val > rg
      local row = (math.abs(x - lastX[1]) < 34) and 2 or 1
      if row == 2 and math.abs(x - lastX[2]) < 34 then row = 1 end
      lastX[row] = x
      local py = row == 1 and -80 or -112
      pn:ClearAllPoints(); pn:SetPoint("TOP", v, "TOPLEFT", 20 + x, py)
      local c = BAND[((r - 1) % #BAND) + 1]
      if have then pn.bg:SetColorTexture(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1) else pn.bg:SetColorTexture(0.2, 0.2, 0.2, 1) end
      pn.text:SetText((have and "|cffffffff" or "|cff888888") .. "R" .. r .. "|r" .. (off and "<" or ""))
      pn:SetAlpha(off and 0.5 or 1)
      pn:Show()
      -- stem from the pin to the bar, tick on the bar
      pn.stem:ClearAllPoints(); pn.stem:SetPoint("TOP", pn, "BOTTOM", 0, 0); pn.stem:SetPoint("BOTTOM", bar, "TOPLEFT", x, 0)
      pn.stem:SetColorTexture(have and 0.9 or 0.5, have and 0.9 or 0.5, have and 0.9 or 0.5, 0.8); pn.stem:Show()
      pn.tick:ClearAllPoints(); pn.tick:SetPoint("TOP", bar, "TOPLEFT", x, 0); pn.tick:SetColorTexture(1, 1, 1, have and 0.95 or 0.4); pn.tick:Show()
      pn.val:ClearAllPoints(); pn.val:SetPoint("BOTTOM", pn, "TOP", 0, 1); pn.val:SetText(val .. "%"); pn.val:Show()
    end
    if dragOnly then return end
    for i = 1, 5 do
      local m = rg * (i - 1) / 4
      local fs = self.scale[i]
      fs:ClearAllPoints(); fs:SetPoint("TOP", bar, "BOTTOMLEFT", self:XFor(m), -3)
      fs:SetText(floor(m + 0.5) .. "%")
    end
    self.leftLab:SetText(rg >= 100 and "|cffff5555empty|r" or ("|cffaaaaaa" .. rg .. "% missing|r"))
    self.zoom:SetValue(rg)
  end
  v:SetScript("OnHide", function() if v.dragging then v.dragging:StopDrag() end end)
  -- release anywhere on screen
  pcall(v.RegisterEvent, v, "GLOBAL_MOUSE_UP")
  v:SetScript("OnEvent", function(_, ev, btn)
    if ev == "GLOBAL_MOUSE_UP" and v.dragging and (btn == nil or btn == "LeftButton") then v.dragging:StopDrag() end
  end)
  v:Hide()
  return v
end

local function buildRanks(p)
  p.key = nil
  local hint = UI:Text(p, "|cffaaaaaaFor each rank: heal with it when the person is missing at least this much health. The highest rank whose step is reached is cast (only ranks you know). For a group heal the step is checked against the whole cluster.|r", "small")
  hint:SetPoint("TOPLEFT", 14, -6); hint:SetWidth(W - 28); hint:SetJustifyH("LEFT")
  local sl = UI:Text(p, "Spell:", "small"); sl:SetPoint("TOPLEFT", 14, -52)
  p.spell = UI:Dropdown(p, 220, spellOptions, nil, function(v) p.key = v; p:Refresh() end)
  p.spell:SetPoint("TOPLEFT", 60, -46)
  p.icon = p:CreateTexture(nil, "ARTWORK"); p.icon:SetSize(22, 22); p.icon:SetPoint("LEFT", p.spell, "RIGHT", 8, 0)
  -- the steps are set only by dragging the pins on the bar
  buildRankVisual(p, -80, 320)
  local yb = -410
  local bl = UI:Text(p, "Missing less than the first step:", "small"); bl:SetPoint("TOPLEFT", 14, yb - 5)
  p.below = UI:Dropdown(p, 200, { { value = "low", text = "Cast the lowest rank" }, { value = "skip", text = "Don't cast" } }, "low",
    function(v) if p.key then spellCfg(p.key).below = v; refreshAll(); p:Refresh() end end)
  p.below:SetPoint("TOPLEFT", 230, yb)
  yb = yb - 30
  p.example = UI:Text(p, "", "small"); p.example:SetPoint("TOPLEFT", 14, yb); p.example:SetWidth(W - 28); p.example:SetJustifyH("LEFT")
  function p:Refresh()
    local keys = classKeys()
    if not self.key or SPELLS[self.key].class ~= myClass() then self.key = primaryKey() or keys[1] end
    local key = self.key
    self.vis:Show()
    if not key then self.spell:SetValue(nil); self.spell.text:SetText("|cff777777No healing spells for your class|r"); self.example:SetText(""); self.vis:Layout(); return end
    self.spell:SetValue(key)
    self.spell.text:SetText(sname(key) .. (knownKey(key) and "" or " |cff777777(not learned)|r"))
    local R = ranks(key)
    self.icon:SetTexture((R and R.icon) or spellIcon(SPELLS[key].ids[1]))
    self.vis:Layout()
    self.below:SetValue(spellCfg(key).below)
    self:RefreshText()
  end
  function p:RefreshText()
    local key = self.key
    if not key then return end
    -- examples
    local ex = {}
    for _, m in ipairs({ 3, 8, 12, 18, 25, 40 }) do
      local r = pickRank(key, m)
      ex[#ex + 1] = m .. "% -> " .. (r and ("|cffffd100R" .. r .. "|r") or "|cff777777none|r")
    end
    self.example:SetText("|cffaaaaaaWith what you know now, missing:|r  " .. table.concat(ex, "   "))
  end
end

local function buildGroup(p)
  local hint = UI:Text(p, "", "small")
  hint:SetPoint("TOPLEFT", 14, -6); hint:SetWidth(W - 28); hint:SetJustifyH("LEFT")
  p.hint = hint
  local y = -64
  p.on = UI:Check(p, "Auto clicks switch to the group heal", true, function(v) CL().group.on = v; refreshAll() end,
    "Off: auto clicks behave like smart clicks.")
  p.on:SetPoint("TOPLEFT", 16, y); y = y - 34
  p.others = UI:Slider(p, W - 40, "Others hurt around them", 1, 4, 1, 2, function(v) CL().group.minOthers = v; refreshAll(); p:Refresh() end)
  p.others:SetPoint("TOPLEFT", 16, y); y = y - 30
  p.miss = UI:Slider(p, W - 40, "...each missing at least", 0, 60, 1, 10, function(v) CL().group.minMiss = v; refreshAll(); p:Refresh() end, function(v) return v .. "%" end)
  p.miss:SetPoint("TOPLEFT", 16, y); y = y - 30
  p.range = UI:Slider(p, W - 40, "Jump range (yards)", 5, 40, 0.5, 12.5, function(v) CL().group.range = v; refreshAll() end, function(v) return string.format("%.1f", v) end)
  p.range:SetPoint("TOPLEFT", 16, y); y = y - 34
  local rl = UI:Text(p, "Rank from the cluster's:", "small"); rl:SetPoint("TOPLEFT", 16, y - 5)
  p.rule = UI:Dropdown(p, 260, { { value = "all", text = "Least hurt of them (all are missing it)" }, { value = "avg", text = "Average missing" } }, "all",
    function(v) CL().group.rule = v; refreshAll(); p:Refresh() end)
  p.rule:SetPoint("TOPLEFT", 200, y); y = y - 40
  p.info = UI:Text(p, "", "small"); p.info:SetPoint("TOPLEFT", 16, y); p.info:SetWidth(W - 32); p.info:SetJustifyH("LEFT")
  local toRanks = UI:Button(p, "Group heal ranks...", 150, 22, function()
    local g = groupKey()
    for _, k in ipairs(classKeys()) do if SPELLS[k].group and not g then g = k end end
    if g then panes[2].key = g end
    win.tabs:Select(2)
  end)
  toRanks:SetPoint("BOTTOMLEFT", 14, 14)
  function p:Refresh()
    local g = groupKey()
    local any
    for _, k in ipairs(classKeys()) do if SPELLS[k].group then any = any or k end end
    g = g or any
    local gr = CL().group
    if not g then
      self.hint:SetText("|cffaaaaaaYour class has no group heal with ranks here. Smart clicks still gauge single-target ranks.|r")
      self.info:SetText("")
      return
    end
    local sp = SPELLS[g]
    self.hint:SetText("|cffaaaaaaGroup heal: |cffffd100" .. sname(g) .. "|r|cffaaaaaa" .. (knownKey(g) and "" or " (not learned yet)") ..
      ". An |cffffd100auto|r|cffaaaaaa click casts it instead of your single heal when the person you click AND enough people " ..
      (sp.group == "party" and "in your party (in range)" or "near them") .. " are hurt. Its rank comes from the steps on the Ranks tab, checked against the cluster.|r")
    self.on:SetChecked(gr.on ~= false)
    self.others:SetValue(gr.minOthers); self.miss:SetValue(gr.minMiss); self.range:SetValue(gr.range)
    self.range:SetShown(sp.group ~= "party")
    self.rule:SetValue(gr.rule)
    local ex = {}
    for _, m in ipairs({ 5, 10, 20, 30 }) do
      local r = knownKey(g) and pickRank(g, m)
      ex[#ex + 1] = "all missing " .. m .. "% -> " .. (r and ("|cff66ddff" .. sname(g) .. " R" .. r .. "|r") or "|cff777777-|r")
    end
    self.info:SetText("Example (" .. (gr.minOthers + 1) .. " people hurt): " .. table.concat(ex, ",  ") ..
      (sp.group == "chain" and "\n\n|cffaaaaaa\"Near them\" uses real positions where the game gives them (open world). In dungeons and raids it falls back to everyone in your healing range.|r" or ""))
  end
end

local function buildLook(p)
  local y = -10
  local function chk(label, key, tip, after)
    local c = UI:Check(p, label, L()[key], function(v) L()[key] = v; if after then after(v) end; applyLayout(); refreshAll() end, tip)
    c:SetPoint("TOPLEFT", 16, y); y = y - 26
    return c
  end
  p.checks = {}
  p.checks.on = chk("Show the HealAssist frames", "on", nil, function(v) if v and not anchor then if combat() then S:Print("HealAssist: the frames appear after combat.") else buildFrames() end end end)
  p.checks.locked = chk("Lock the frames", "locked", "Unlocked: a bar above the frames lets you drag them (and your own frame shows even when solo).")
  p.checks.solo = chk("Show my own frame when I'm not in a group", "solo")
  p.checks.selfTest = chk("Test frame for me (always shown, also in a group)", "selfTest",
    "An extra frame for yourself, left of the group, marked TEST - heal yourself to try your clicks and ranks. " .. CMD .. " test")
  p.checks.classColor = chk("Class colours", "classColor")
  p.checks.marks = chk("Rank marks on the health bar", "marks", "A small tick on the top edge where each rank's step starts: once the bar ends left of a tick, that rank is earned.")
  p.checks.markNums = chk("Rank numbers under the marks", "markNums")
  p.checks.badge = chk("Rank badge (what a left click casts) out of combat", "badge")
  p.checks.combatBadge = chk("Rank badge in combat (where the game supports it)", "combatBadge")
  p.checks.rangeFade = chk("Fade people out of range", "rangeFade")
  y = y - 6
  local function sld(label, key, lo, hi, step, fmt)
    local s = UI:Slider(p, W - 40, label, lo, hi, step, L()[key], function(v) L()[key] = v; applyLayout() end, fmt)
    s:SetPoint("TOPLEFT", 16, y); y = y - 28
    return s
  end
  p.sliders = {
    w = sld("Width", "w", 50, 200, 1), h = sld("Height", "h", 20, 80, 1), perCol = sld("People per column / row", "perCol", 1, 10, 1),
    spacing = sld("Spacing", "spacing", 0, 20, 1), scale = sld("Scale", "scale", 0.5, 2, 0.05, function(v) return string.format("%.2f", v) end),
    rangeAlpha = sld("Out of range opacity", "rangeAlpha", 0.1, 1, 0.05, function(v) return floor(v * 100 + 0.5) .. "%" end),
  }
  local ol = UI:Text(p, "Layout:", "small"); ol:SetPoint("TOPLEFT", 16, y - 5)
  p.orient = UI:Dropdown(p, 220, { { value = "cols", text = "Columns (party goes down)" }, { value = "rows", text = "Rows (party goes across)" } }, L().orient,
    function(v) L().orient = v; applyLayout() end)
  p.orient:SetPoint("TOPLEFT", 152, y); y = y - 32
  local hl = UI:Text(p, "Health text:", "small"); hl:SetPoint("TOPLEFT", 16, y - 5)
  p.htext = UI:Dropdown(p, 220, { { value = "percent", text = "Percent (87%)" }, { value = "deficit", text = "Missing (-1.2k)" },
    { value = "current", text = "Current health" }, { value = "none", text = "None" } }, L().healthText,
    function(v) L().healthText = v end)
  p.htext:SetPoint("TOPLEFT", 152, y); y = y - 34
  p.status = UI:Text(p, "", "small"); p.status:SetPoint("TOPLEFT", 16, y); p.status:SetWidth(W - 32); p.status:SetJustifyH("LEFT")
  p.test = UI:PrimaryButton(p, "Test mode", 130, 24, function() S.HealAssistTest() end,
    "A made-up group whose health changes on its own: watch the rank badges, marks and text follow your settings live. Left-click a test frame to heal it with the shown rank, right-click to hit it.")
  p.test:SetPoint("BOTTOMLEFT", 14, 14)
  local sz = UI:Text(p, "Group size:", "small"); sz:SetPoint("LEFT", p.test, "RIGHT", 14, 0)
  p.tsize = UI:Dropdown(p, 90, { { value = 5, text = "5" }, { value = 10, text = "10" }, { value = 25, text = "25" }, { value = 40, text = "40" } }, 5,
    function(v) S.HealAssistTest(test.on, v) end)
  p.tsize:SetPoint("LEFT", sz, "RIGHT", 8, 0)
  function p:Refresh()
    for k, c in pairs(self.checks) do c:SetChecked(L()[k] and true or false) end
    for k, s in pairs(self.sliders) do s:SetValue(L()[k]) end
    self.orient:SetValue(L().orient); self.htext:SetValue(L().healthText)
    self.test:SetText(test.on and "Stop test mode" or "Test mode"); self.tsize:SetValue(test.size)
    local cs = curveState.ok
    self.status:SetText("|cffaaaaaaIn-combat rank badge: " .. (cs == true and "|cff55ff55working|r" or cs == false and "|cffff7777not supported by the game - the rank marks still work|r" or "|cffffd100not checked yet (shows after your first look at a hurt frame)|r") .. "|r")
  end
end

local function buildDispels(p)
  local y = -10
  local hint = UI:Text(p, "|cffaaaaaaA button for each cure your class knows sits beside every bar - click it to cure that person (works in combat). Out of combat the button you need lights up and the bar shows the debuff's colour and name. With \"Let the game draw debuffs\" on, the game itself does the colouring, the type name and the button glow - also in combat (WoW Forever hides debuffs from addon code, but not from its own aura containers).|r", "small")
  hint:SetPoint("TOPLEFT", 14, y); hint:SetWidth(W - 28); hint:SetJustifyH("LEFT")
  y = y - 58
  local pl = UI:Text(p, "Cure buttons:", "small"); pl:SetPoint("TOPLEFT", 16, y - 5)
  p.pos = UI:Dropdown(p, 200, { { value = "right", text = "Outside, after the bar" }, { value = "left", text = "Outside, before the bar" }, { value = "off", text = "Off" } }, L().dispel,
    function(v) L().dispel = v; applyLayout(); refreshAll(); if test.on then placeTest() end end)
  p.pos:SetPoint("TOPLEFT", 150, y); y = y - 34
  p.size = UI:Slider(p, W - 40, "Button size (max)", 10, 30, 1, L().dispelSize, function(v) L().dispelSize = v; applyLayout(); refreshAll(); if test.on then placeTest() end end)
  p.size:SetPoint("TOPLEFT", 16, y); y = y - 28
  p.idle = UI:Slider(p, W - 40, "Button when not needed", 0, 1, 0.05, L().dispelIdle, function(v) L().dispelIdle = v end, function(v) return floor(v * 100 + 0.5) .. "%" end)
  p.idle:SetPoint("TOPLEFT", 16, y); y = y - 34
  local function chk(label, key, tip)
    local c = UI:Check(p, label, L()[key], function(v) L()[key] = v end, tip)
    c:SetPoint("TOPLEFT", 16, y); y = y - 26
    return c
  end
  p.c1 = chk("Colour the bar for a debuff", "dispelColor", "Poison green, curse purple, disease brown, magic blue.")
  p.c2 = chk("Write the debuff type on the bar", "dispelText")
  p.c3 = chk("Only debuffs my class can remove", "dispelMine")
  p.c4 = chk("Let the game draw debuffs (works in combat)", "dispelEngine",
    "Uses Blizzard's aura containers: the game itself tints the bar, writes the type and lights the right cure button, also in combat. Off: HealAssist reads debuffs itself (out of combat only).")
  p.wash = UI:Slider(p, W - 40, "Bar tint strength", 0.2, 1, 0.05, L().dispelWash, function(v) L().dispelWash = v; refreshAll() end, function(v) return floor(v * 100 + 0.5) .. "%" end)
  p.wash:SetPoint("TOPLEFT", 16, y); y = y - 30
  y = y - 8
  p.list = UI:Text(p, "", "normal"); p.list:SetPoint("TOPLEFT", 16, y); p.list:SetWidth(W - 32); p.list:SetJustifyH("LEFT")
  function p:Refresh()
    dispelCache = nil
    self.pos:SetValue(L().dispel); self.size:SetValue(L().dispelSize); self.idle:SetValue(L().dispelIdle)
    self.c1:SetChecked(L().dispelColor and true or false); self.c2:SetChecked(L().dispelText and true or false); self.c3:SetChecked(L().dispelMine and true or false)
    self.c4:SetChecked(L().dispelEngine and true or false); self.wash:SetValue(L().dispelWash or 0.6)
    local lines = { "|cffffd100Your cures:|r" }
    local have = dispelButtons()
    for _, info in ipairs(have) do lines[#lines + 1] = "|T" .. tostring(info.icon) .. ":16:16:0:0:64:64:5:59:5:59|t  " .. info.name .. "  |cffaaaaaa" .. info.typeList .. "|r" end
    if #have == 0 then lines[#lines + 1] = (DISPELS[myClass()] and "|cff888888None learned yet.|r" or "|cff888888Your class has no cures.|r") end
    local all = {}
    for _, e in ipairs(DISPELS[myClass()] or {}) do
      local got = false
      for _, info in ipairs(have) do if info.name == (spellName(e.ids[1]) or e.name) then got = true end end
      if not got then all[#all + 1] = e.name end
    end
    if #all > 0 then lines[#lines + 1] = "|cff888888Not used / not learned: " .. table.concat(all, ", ") .. "|r" end
    local eng = S.HealAssistEngine
    lines[#lines + 1] = "\n|cffaaaaaaGame-drawn debuffs: " .. ((not L().dispelEngine) and "off" or eng.ok == true and "|cff55ff55working (also in combat)|r" or eng.ok == false and ("|cffff7777not available on this client|r - " .. tostring(eng.why or "")) or "|cffffd100starting...|r") .. "|r"
    self.list:SetText(table.concat(lines, "\n"))
  end
end

function S:RefreshHealAssist()
  if not win or not win:IsShown() then return end
  for _, p in ipairs(panes) do if p.Refresh and p:IsShown() then p:Refresh() end end
end

local function build()
  win = UI:Window("CC_HealAssist", "HealAssist", W, H)
  local names = { "Clicks", "Ranks", "Group heal", "Frames", "Dispels" }
  local builders = { buildClicks, buildRanks, buildGroup, buildLook, buildDispels }
  for i = 1, #names do
    local p = CreateFrame("Frame", nil, win)
    p:SetPoint("TOPLEFT", 0, -70); p:SetPoint("BOTTOMRIGHT", 0, 0)
    p:Hide()
    builders[i](p)
    panes[i] = p
  end
  win.pages = panes
  win.tabs = UI:SubTabs(win, names, function(i)
    for j, p in ipairs(panes) do p:SetShown(i == j) end
    if panes[i].Refresh then panes[i]:Refresh() end
  end)
  win.tabs:SetPoint("TOPLEFT", 14, -38); win.tabs:SetPoint("TOPRIGHT", -14, -38)
  win.tabs:Select(1)
  win:HeaderButton("heal", "Test mode", "A made-up group with changing health, so you see every setting live. Click again to stop.", function() S.HealAssistTest() end)
  win:HookScript("OnShow", function() rankCache = nil; S:RefreshHealAssist() end)
end
function S:ShowHealAssist()
  if not win then build() end
  win:Show(); win:Raise()
  S:RefreshHealAssist()
end
function S:HideHealAssist() if win then win:Hide() end end

S:AddCommand("heal", "[check|test|preview|ladder|spells]", "HealAssist: healing frames with click casting and rank gauging", function(rest)
  rest = S.Trim(rest or ""):lower()
  if rest == "preview" then S.HealAssistTest() return end
  if rest == "spells" then S:ShowHealAssistSpells() return end
  if rest == "ladder" then if combat() then S:Print("HealAssist: after combat.") else S.HealAssistLadder() end return end
  if rest == "test" then
    local l = L()
    if combat() then S:Print("HealAssist: change the test frame after combat.") return end
    l.selfTest = not l.selfTest
    if l.selfTest then l.on = true end
    if not anchor then buildFrames() else applyLayout() end
    S:Print("HealAssist test frame " .. (l.selfTest and "|cff55ff55on|r - heal yourself on the TEST frame (drag the frames with Frames > unlock)." or "|cffff7777off|r."))
    S:RefreshHealAssist()
    return
  end
  if rest == "check" then
    rankCache = nil
    S:Print("HealAssist ranks you know:")
    for _, k in ipairs(classKeys()) do
      local R = ranks(k)
      local t = {}
      for _, r in ipairs(R.list) do t[#t + 1] = r .. "=" .. tostring(R.byRank[r]) end
      print("  " .. sname(k) .. ": " .. (#t > 0 and table.concat(t, ", ") or "|cff777777none|r"))
    end
    local u = exists("target") and "target" or "player"
    local m = missingPct(u)
    print("  " .. (try(UnitName, u) or u) .. " missing: " .. (m and string.format("%.1f%%", m) or "hidden"))
    for _, mod in ipairs(MODS) do for btn = 1, 5 do
      local b = CL().binds[bindKey(mod, btn)]
      if type(b) == "table" and b.kind and b.kind ~= "none" then
        local typ, spell, label = resolve(b, u)
        print("  " .. bindLabel(mod, btn) .. ": " .. tostring(label) .. " |cff888888[" .. tostring(typ) .. " " .. tostring(spell) .. "]|r")
      end
    end end
    print("  in-combat badge: " .. tostring(curveState.ok) .. ", live rank in combat: " .. tostring(CL().live) .. (S.HealAssistLiveBroken and (" |cffff7777blocked: " .. S.HealAssistLiveBroken .. "|r") or ""))
    print("  health hidden from addons: " .. tostring(healthHidden(u)) .. ", game-picked rank on click: " .. tostring(hc.attrOK == nil and "not tried yet" or hc.attrOK))
    local lc = S.HealAssistLastCast and S.HealAssistLastCast()
    if lc then print(string.format("  last cast check: asked Rank %s, game cast Rank %s (%s, by %s)", tostring(lc.want), tostring(lc.got), sname(lc.key), tostring(lc.by))) end
    for _, b in ipairs(kids) do
      local bu = b:GetAttribute("unit")
      if b:IsShown() and bu then
        local pm, rm = S.HealAssistProbe(b), missingPct(bu)
        print(string.format("  probe %s: measures %s missing (game: %s)%s", tostring(try(UnitName, bu) or bu),
          pm and string.format("%.1f%%", pm) or "?", rm and string.format("%.1f%%", rm) or "?",
          b:GetAttribute("ha-last") and ("  last combat click: " .. tostring(b:GetAttribute("ha-last"))) or ""))
      end
    end
    return
  end
  S:ShowHealAssist()
end)
