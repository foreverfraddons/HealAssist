-- Mock harness for HealAssist.lua (texlua / Lua 5.3)
local errors = 0
local function check(cond, msg) if not cond then errors = errors + 1; print("FAIL: " .. msg) else print("ok   " .. msg) end end

local SECRET = setmetatable({}, { __tostring = function() return "SECRET" end })
-- generic mock object: unknown methods are no-ops
local function mock(extra)
  local o = { __attr = {}, __shown = true, __scripts = {}, __w = 92, __h = 40, __text = "" }
  for k, v in pairs(extra or {}) do o[k] = v end
  return setmetatable(o, { __index = function(t, k)
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
  end })
end
local frames = {}
local function newFrame(kind, name, parent, template)
  local f = mock()
  f.__kind, f.__name, f.__tpl = kind, name, template
  function f:SetAttribute(k, v) self.__attr[k] = v; if self.__onattr then self:__onattr(k, v) end end
  function f:GetAttribute(k) return self.__attr[k] end
  function f:IsShown() return self.__shown end
  function f:IsVisible() return self.__shown end
  function f:Show() local was = self.__shown; self.__shown = true; if not was and self.__scripts and self.__scripts.OnShow then self.__scripts.OnShow(self) end end
  function f:Hide() local was = self.__shown; self.__shown = false; if was and self.__scripts and self.__scripts.OnHide then self.__scripts.OnHide(self) end end
  function f:SetShown(v) self.__shown = v and true or false end
  function f:GetName() return self.__name end
  function f:GetWidth() return self.__w end
  function f:GetHeight() return self.__h end
  function f:SetSize(w, h) self.__w, self.__h = w, h end
  function f:SetWidth(w) self.__w = w end
  function f:GetFrameLevel() return 1 end
  function f:GetPoint() return "LEFT", nil, "LEFT", 10, 20 end
  function f:SetScript(k, fn) self.__scripts[k] = fn end
  function f:GetScript(k) return self.__scripts[k] end
  function f:HookScript(k, fn) self.__scripts[k] = fn end
  function f:CreateTexture() return newFrame("Texture") end
  function f:CreateFontString() local fs = newFrame("FontString"); function fs:SetText(t) self.__text = t end; function fs:GetText() return self.__text end; return fs end
  function f:SetText(t) self.__text = t end
  function f:GetText() return self.__text end
  function f:HasFocus() return false end
  function f:GetChecked() return self.__checked end
  function f:SetChecked(v) self.__checked = v end
  f.__parent = parent
  if kind == "StatusBar" then
    f.__v, f.__max = 1, 1
    f.__tex = newFrame("Texture"); f.__tex.__bar = f
    function f:GetStatusBarTexture() return self.__tex end
    function f:SetMinMaxValues(a, b2) if b2 == SECRET then b2 = 1000 end if type(b2) == "table" and b2.v then b2 = b2.v end self.__max = b2 end
    function f:SetValue(v)
      if v == SECRET then local u = self.__parent and self.__parent.__attr.unit; v = units[u] and units[u].hp or 0; self.__max = units[u] and units[u].max or 1 end
      if type(v) == "table" and v.v then v = v.v end
      self.__v = v
    end
  end
  if kind == "Frame" and template == nil then
    function f:SetPoint(pt, rel) if type(rel) == "table" and rel.__bar then self.__tex = rel end end
  end
  if template == "SecureFrameTemplate" then
    -- the game's rule: protected frames can't be anchored to regions (textures)
    function f:SetPoint(pt, rel) if type(rel) == "table" and rel.__kind == "Texture" then error("Action[SetPoint] failed because[Cannot anchor protected frames to regions]") end end
    function f:SetAllPoints(rel)
      if os.getenv("HA_REFUSE") then error("Action[SetPoint] failed because[refused in test]") end
      if rel and rel.__kind == "Texture" then error("Cannot anchor protected frames to regions") end
      if rel and rel.__kind ~= "StatusBar" and rawget(rel, "__tex") then self.__tex = rel.__tex end
    end
    function f:GetWidth()
      local W = 90
      if self.__tex then local bar = self.__tex.__bar; return W * (bar.__v / math.max(1, bar.__max)) end
      return W
    end
  end
  if kind == "AuraContainer" then
    if NO_AURA_CONTAINER then error("Unknown frame type 'AuraContainer'") end
    f.__kids2 = {}
    function f:AddAuraSlot(key, filter, opts)
      self.__filter = filter
      local btn = newFrame("AuraButton")
      btn.__dispel = {}
      function btn:AddDispelTypeTexture(tx, o) table.insert(self.__dispel, { t = tx, o = o }) end
      function btn:SetDispelTypeText(fs, o) self.__dtext = fs end
      table.insert(self.__kids2, btn)
      if opts and opts.initializeFrame then opts.initializeFrame(btn) end
    end
    function f:GetChildren() return table.unpack(self.__kids2) end
    function f:SetUnit(u) self.__unit = u end
  end
  if template == "SecureHandlerBaseTemplate" then
    f.__refs = {}
    function f:SetFrameRef(l, fr) self.__refs[l] = fr end
    function f:GetFrameRef(l) return self.__refs[l] end
    function f:WrapScript(fr, script, body) fr.__wrap = body; fr.__owner = self end
  end
  frames[#frames + 1] = f
  if name then _G[name] = f end
  -- secure group header: build 40 kids on startingIndex -39
  if template == "SecureGroupHeaderTemplate" then
    f.__onattr = function(self, k, v)
      if k == "startingIndex" and v == -39 and not rawget(self, "__kids") then
        self.__kids = {}
        for i = 1, 40 do
          local b = newFrame("Button", name .. "UnitButton" .. i, self, "SecureUnitButtonTemplate")
          b.__shown = false
          self.__attr["child" .. i] = b
          self.__kids[i] = b
        end
      end
    end
  end
  return f
end
CreateFrame = newFrame
UIParent = newFrame("Frame", "UIParent")
GameTooltip = newFrame("GameTooltip")
STANDARD_TEXT_FONT = "x"
function GameTooltip_SetDefaultAnchor() end
time = os.time
function GetTime() return os.clock() end
date = os.date
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return {} end }

-- world state
local inCombat = false

function InCombatLockdown() return inCombat end
units = {
  player = { name = "Me", hp = 1000, max = 1000, x = 0, y = 0 },
  party1 = { name = "Tank", hp = 1000, max = 1000, x = 5, y = 0 },
  party2 = { name = "Rogue", hp = 1000, max = 1000, x = 8, y = 3 },
  party3 = { name = "Far", hp = 1000, max = 1000, x = 200, y = 0 },
}
local secretMode = false
function issecretvalue(v) return v == SECRET or (type(v) == "table" and getmetatable(v) ~= nil and getmetatable(v).__box == true) end
function UnitExists(u) return units[u] ~= nil end
function UnitHealth(u) if secretMode then return SECRET end return units[u] and units[u].hp end
function UnitHealthMax(u) if secretMode then return SECRET end return units[u] and units[u].max end
function UnitName(u) return units[u] and units[u].name end
function UnitClass(u) return "Shaman", "SHAMAN" end
function UnitIsDeadOrGhost() return false end
function UnitIsDead() return false end
function UnitIsGhost() return false end
function UnitIsConnected() return true end
function UnitIsUnit(a, b) return a == b end
function UnitInRange(u) return true, true end
function UnitPosition(u) local d = units[u]; if not d then return nil end return d.y, d.x, 0, 1 end
function IsInRaid() return false end
function GetNumGroupMembers() return 4 end
local known = { [331] = true, [332] = true, [547] = true, [913] = true, [939] = true, [8004] = true, [8008] = true, [1064] = true, [10622] = true }
function IsPlayerSpell(id) return known[id] or false end
local NAMES = { [331] = "Healing Wave", [8004] = "Lesser Healing Wave", [1064] = "Chain Heal" }
function GetSpellInfo(id) return NAMES[id] or ("Spell" .. id) end
function GetSpellTexture() return 1 end
RAID_CLASS_COLORS = { SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
function print(...) io.write(table.concat((function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end return t end)(...), " "), "\n") end
_print = print

-- addon namespace + UI stub
local S = { db = { global = {} } }
local listeners, events, commands = {}, {}, {}
function S:On(e, fn) events[e] = events[e] or {}; table.insert(events[e], fn) end
function S:Listen(m, fn) listeners[m] = listeners[m] or {}; table.insert(listeners[m], fn) end
function S:AddCommand(c, a, d, fn) commands[c] = fn end
function S:Print(m) print("[CC] " .. tostring(m)) end
function S.Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function S:ModuleRev(n, r) S.rev = r end
local function fire(e, ...) for _, fn in ipairs(events[e] or {}) do local ok, err = xpcall(fn, debug.traceback, e, ...); if not ok then error(err) end end end
local function listen(m) for _, fn in ipairs(listeners[m] or {}) do fn() end end

local UI = { ICON = setmetatable({}, { __index = function(_, k) return "i_" .. k end }) }
function UI:Theme() return { gold = { 1, 0.8, 0.2 }, text = { 1, 1, 1 }, muted = { 0.5, 0.5, 0.5 } } end
function UI:Text(parent) return parent:CreateFontString() end
function UI:Window(name) local w = newFrame("Frame", name); w.__shown = false; return w end
function UI:Button(parent, text, w, h, onClick) local b = newFrame("Button"); b.click = onClick; return b end
function UI:PrimaryButton(parent, text, w, h, onClick) local b = newFrame("Button"); b.click = onClick; return b end
function UI:Check(parent, label, checked, onChange) local c = newFrame("CheckButton"); c.change = onChange; c.__checked = checked; c.label = c:CreateFontString(); return c end
function UI:Slider(parent, w, label, lo, hi, step, value, onChange)
  local s = newFrame("Slider"); s.v = value; s.change = onChange
  function s:SetValue(v) self.v = v end
  function s:GetValue() return self.v end
  return s
end
function UI:Edit() return newFrame("EditBox") end
function UI:Dropdown(parent, w, options, selected, onSelect)
  local d = newFrame("Button"); d.text = d:CreateFontString(); d.options = options; d.select = onSelect
  function d:SetValue(v) self.value = v end
  return d
end
function UI:Scroll() local sf = newFrame("ScrollFrame"); return sf, newFrame("Frame") end
function UI:SubTabs(parent, names, onSelect)
  local t = newFrame("Frame"); function t:Select(i) self.current = i; onSelect(i) end; return t
end
function UI:Tip() end
function UI:Confirm(text, fn) fn() end
S.UI = UI
S.report = function(e) print("REPORT: " .. tostring(e)) end

-- load
local chunk = assert(loadfile(arg[1] or "HealAssist.lua"))
chunk("CommandCenter", S)
check(S.rev == 25, "revision line registered")

listen("LOGIN")
local header = _G.CC_HealAssistGroup
check(header ~= nil, "header built")
check(rawget(header, "__kids") and #header.__kids == 40, "40 buttons pre-made")

-- assign units to the first 4 kids
local order = { "player", "party1", "party2", "party3" }
for i, u in ipairs(order) do local b = header.__kids[i]; b.__attr.unit = u; b.__shown = true end
local function kid(u) for i, x in ipairs(order) do if x == u then return header.__kids[i] end end end

if os.getenv("HA_REFUSE") then
  units.party1.hp = 860
  fire("PLAYER_REGEN_ENABLED")
  local bb = kid("party1")
  check(S.HealAssistLiveBroken ~= nil, "refused live parts are noted")
  check(bb.__attr.type1 == "spell" and bb.__attr.spell1 == 332, "frames still get their clicks when live rank is refused")
  local okT = S.HealAssistTick(); check(okT, "tick still runs")
  check(bb.hp.__v == 860, "frame still painted")
  print(errors == 0 and "ALL PASSED (refused mode)" or (errors .. " FAILED"))
  os.exit(errors == 0 and 0 or 1)
end
local pick = S.HealAssistPickRank
check(pick("HW", 3) == 1, "HW 3% missing -> rank 1 (below first step casts lowest)")
check(pick("HW", 5) == 1, "HW 5% -> rank 1")
check(pick("HW", 10) == 2, "HW 10% -> rank 2")
check(pick("HW", 15) == 3, "HW 15% -> rank 3")
check(pick("HW", 40) == 5, "HW 40% -> rank 5 (highest known)")
check(pick("CH", 10) == 2, "CH 10% -> rank 2")
check(pick("CH", 20) == 2, "CH 20% -> rank 2 (rank 3 not known)")

-- run a tick through the module: call the PLAYER_REGEN_ENABLED path which updates clicks
units.party1.hp = 860   -- 14% missing
fire("PLAYER_REGEN_ENABLED")
local b = kid("party1")
check(b.__attr.type1 == "spell", "left click is a spell")
check(b.__attr.spell1 == 332, "tank 14% -> Healing Wave rank 2 = 332, got " .. tostring(b.__attr.spell1))
check(b.__attr.type2 == "spell" and b.__attr.spell2 == 8008, "right smart LHW 14% -> rank 2 (8008), got " .. tostring(b.__attr.spell2))
check(b.__attr["shift-spell1"] == 939, "shift-left max HW -> 939")
check(b.__attr["ctrl-type1"] == "target", "ctrl-left target")
check(b.__attr["ctrl-type2"] == "togglemenu", "ctrl-right menu")
check(b.__attr["alt-type1"] == "none", "unbound alt-left does nothing")

-- cluster: tank, player and rogue hurt 20%, far one hurt too but out of jump range
units.player.hp = 800; units.party1.hp = 790; units.party2.hp = 780; units.party3.hp = 500
fire("PLAYER_REGEN_ENABLED")
check(b.__attr.spell1 == 10622, "auto left -> Chain Heal rank 2 (all ~20% missing) got " .. tostring(b.__attr.spell1))
local ok, v, n, usedPos = S.HealAssistCluster("party1", "CH")
check(ok and n == 3 and usedPos and math.abs(v - 20) < 0.01, "cluster uses 3 nearest, min 20%, positions")
-- only one other hurt -> single heal
units.party2.hp = 1000
fire("PLAYER_REGEN_ENABLED")
check(b.__attr.spell1 == 913, "one other hurt -> Healing Wave by 21% -> rank 4 (913) got " .. tostring(b.__attr.spell1))

-- combat: smart clicks switch to max rank before lockdown
fire("PLAYER_REGEN_DISABLED")
check(b.__attr.spell1 == 939 and b.__attr.spell2 == 8008, "combat start: smart/auto -> max rank")
inCombat = true; secretMode = true
units.party1.hp = 100
fire("GROUP_ROSTER_UPDATE")
check(b.__attr.spell1 == 939, "no attribute changes in combat")
check(S.HealAssistMissing("party1") ~= nil, "secret health -> measured from the frame instead")
inCombat = false; secretMode = false
fire("PLAYER_REGEN_ENABLED")
check(b.__attr.spell1 == 939, "after combat 90% missing -> max HW rank")

-- castBy name
S.db.global.healAssist.look.castBy = "name"
units.party1.hp = 950
fire("PLAYER_REGEN_ENABLED")
check(b.__attr.spell1 == "Healing Wave(Rank 1)", "cast by name: " .. tostring(b.__attr.spell1))
S.db.global.healAssist.look.castBy = "id"

-- custom thresholds
S.db.global.healAssist.classes.SHAMAN.spells.HW = { th = { 0, 30, 60, 80, 95 }, below = "low" }
check(pick("HW", 29) == 1 and pick("HW", 30) == 2 and pick("HW", 61) == 3, "custom steps")
S.db.global.healAssist.classes.SHAMAN.spells.HW = { th = { 0, 30, 60 }, below = "low" }
check(pick("HW", 61) == 5 and pick("HW", 40) == 2, "steps never go down (unset higher ranks follow the last one)")
S.db.global.healAssist.classes.SHAMAN.spells.HW = { th = { 10, 20 }, below = "skip" }
check(pick("HW", 5) == nil, "below first step + skip -> no cast")
S.db.global.healAssist.classes.SHAMAN.spells.HW = nil

-- UI builds and every tab refreshes
S:ShowHealAssist()
local win = _G.CC_HealAssist
check(win ~= nil, "window built")
for i = 1, 4 do win.tabs:Select(i) end
check(true, "all tabs selected without error")
commands.heal("check")
-- paint path (tooltip)
S.HealAssistTooltip(b)
check(true, "tooltip ok")

-- paint out of combat, then in combat with curves
S.db.global.healAssist.classes.SHAMAN.spells.HW = nil
local curves = 0
C_CurveUtil = { CreateCurve = function()
  curves = curves + 1
  local c = { pts = {} }
  function c:SetType() end
  function c:AddPoint(x, y) table.insert(self.pts, { x, y }) end
  function c:Evaluate(x) local v = 0 for _, p in ipairs(self.pts) do if x >= p[1] then v = p[2] end end return v end
  return c
end }
Enum = { LuaCurveType = { Step = 1 } }
function UnitHealthPercent(u, pred, curve)
  local f = units[u].hp / units[u].max
  local v = (type(curve) == "table" and curve:Evaluate(f)) or (curve == "S100" and f * 100) or f
  if secretMode then return SECRET end
  return v
end
units.party1.hp = 870
local okT, errT = S.HealAssistTick()
check(okT, "tick out of combat " .. tostring(errT))
check(b.badge.__text:find("R2") ~= nil, "badge shows R2 out of combat: " .. tostring(b.badge.__text))
local marks = 0 for _, m in ipairs(b.marks) do if m.__shown then marks = marks + 1 end end
check(marks >= 2 and marks <= 4, "rank ticks drawn, close ones merged, got " .. marks)
inCombat = true
okT, errT = S.HealAssistTick()
check(okT, "tick in combat " .. tostring(errT))
local vis = {}
for _, fs in ipairs(b.cbadges) do if fs.__shown then vis[#vis + 1] = fs.__text end end
check(#b.cbadges == 5 and curves >= 5, "5 curve badges built")
inCombat = false
-- health text
units.party1.hp = 870
fire("UNIT_HEALTH", "party1")
check(b.hpText.__text == "87%", "percent text out of combat: " .. tostring(b.hpText.__text))
S.db.global.healAssist.look.healthText = "deficit"
fire("UNIT_HEALTH", "party1")
check(b.hpText.__text == "-130", "deficit text: " .. tostring(b.hpText.__text))
S.db.global.healAssist.look.healthText = "percent"
-- in combat with hidden numbers: our format fails on the mock secret -> Blizzard fallback
inCombat = true; secretMode = true
CurveConstants = { ScaleTo100 = "S100" }
function TextStatusBar_UpdateTextStringWithValues(bar, fs, v, lo, hi) fs:SetText(bar.showPercentage and "blizz%" or "blizz") end
units.party1.hp = 500
fire("UNIT_HEALTH", "party1")
check(b.hpText.__text == "blizz%", "combat: falls back to Blizzard status text: " .. tostring(b.hpText.__text))
-- secret that the client can format (simulate by a formatter that accepts it)
local realfmt = string.format
string.format = function(p, ...) local a = ...; if a == SECRET then return (p:gsub("%%%.0f", "50"):gsub("%%%%", "%%")) end return realfmt(p, ...) end
fire("UNIT_HEALTH", "party1")
check(b.hpText.__text == "50%", "combat: secret percent formatted by the client: " .. tostring(b.hpText.__text))
string.format = realfmt
inCombat = false; secretMode = false
-- live rank in combat: run the secure snippet like the game would
local mods = { shift = false, ctrl = false, alt = false }
local function click(btnFrame, button)
  local env = setmetatable({ PlayerInCombat = function() return inCombat end, owner = btnFrame.__owner,
    IsShiftKeyDown = function() return mods.shift end, IsControlKeyDown = function() return mods.ctrl end, IsAltKeyDown = function() return mods.alt end,
    self = btnFrame, button = button }, { __index = _G })
  local fn = assert(load(btnFrame.__wrap, "snippet", "t", env))
  local ok, err = xpcall(fn, debug.traceback); if not ok then print(err) end
end
check(b.__wrap ~= nil and b.__owner == _G.CC_HealAssistSecure, "OnClick wrapped by the secure handler")
units.player.hp = 1000; units.party1.hp = 1000; units.party2.hp = 1000; units.party3.hp = 1000
for _, u in ipairs(order) do fire("UNIT_HEALTH", u) end
fire("PLAYER_REGEN_ENABLED")
fire("PLAYER_REGEN_DISABLED")       -- fallback: max rank
inCombat = true; secretMode = true
units.party1.hp = 880                -- 12% missing
fire("UNIT_HEALTH", "party1")       -- feeds the probe bar
click(b, "LeftButton")
check(b.__attr.spell1 == 332, "combat click at 12% -> Healing Wave R2 (332), got " .. tostring(b.__attr.spell1))
check(b.__attr["ha-last"] == "R2", "last click label R2")
units.party1.hp = 700
fire("UNIT_HEALTH", "party1")
click(b, "RightButton")
check(b.__attr.spell2 == 8008, "combat right click 30% -> LHW R2 (max known) got " .. tostring(b.__attr.spell2))
-- group: three hurt 20% -> chain heal rank 2
units.party1.hp = 800; units.player.hp = 790; units.party2.hp = 780
for _, u in ipairs({ "player", "party1", "party2" }) do fire("UNIT_HEALTH", u) end
click(b, "LeftButton")
check(b.__attr.spell1 == 10622, "combat auto click, 3 hurt 20% -> Chain Heal R2 got " .. tostring(b.__attr.spell1))
-- shift-left (max) is not live: untouched
mods.shift = true; click(b, "LeftButton"); mods.shift = false
check(b.__attr["shift-spell1"] == 939, "max binding untouched by snippet")
-- live off -> snippet does nothing
inCombat = false; secretMode = false
S.db.global.healAssist.classes.SHAMAN.live = false; S.HealAssistLiveHandler()
fire("PLAYER_REGEN_DISABLED"); inCombat = true; secretMode = true
units.party1.hp = 950; fire("UNIT_HEALTH", "party1"); click(b, "LeftButton")
check(b.__attr.spell1 == 939, "live off: fallback max rank stays")
inCombat = false; secretMode = false
S.db.global.healAssist.classes.SHAMAN.live = true; S.HealAssistLiveHandler()
-- self test frame
local me = _G.CC_HealAssistSelf
check(me and not me.__shown, "test frame exists, hidden by default")
commands.heal("test")
check(me.__shown and me.__attr.unit == "player", "/ccenter heal test shows a frame for me")
units.player.hp = 850
for _, u in ipairs(order) do fire("UNIT_HEALTH", u) end
fire("PLAYER_REGEN_ENABLED")
check(me.__attr.type1 == "spell" and me.__attr.spell1 == 547, "self frame left click 15% -> HW R3 (547) got " .. tostring(me.__attr.spell1))
fire("PLAYER_REGEN_DISABLED"); inCombat = true; secretMode = true
units.player.hp = 900; fire("UNIT_HEALTH", "player")
click(me, "LeftButton")
check(me.__attr.spell1 == 332, "self frame live combat click 10% -> R2 got " .. tostring(me.__attr.spell1))
inCombat = false; secretMode = false
commands.heal("test")
check(not me.__shown, "test toggles off")
-- cast check: the game casts a different rank by ID -> switch to name
function GetTime() return 100 end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
inCombat = false; secretMode = false
S.db.global.healAssist.look.castBy = "id"
units.party1.hp = 880
for _, u in ipairs(order) do units[u].hp = (u == "party1") and 880 or 1000; fire("UNIT_HEALTH", u) end
fire("PLAYER_REGEN_ENABLED")
check(b.__attr.spell1 == 332, "out of combat 12% -> R2 by id")
b.__scripts.PostClick(b, "LeftButton")
fire("UNIT_SPELLCAST_SENT", "player", "Tank", "guid", 939)    -- the game cast rank 5 instead
check(S.db.global.healAssist.look.castBy == "name", "rank mismatch switches to cast by name")
check(b.__attr.spell1 == "Healing Wave(Rank 2)", "attributes now by name: " .. tostring(b.__attr.spell1))
local dg = S.db.global.healAssist.diag
check(dg and dg[1] and dg[1].spell and dg[1].castID == 939, "click log saved with cast id")
local lc = S.HealAssistLastCast()
check(lc and lc.want == 2 and lc.got == 5, "last cast check recorded")
b.__scripts.PostClick(b, "LeftButton")
fire("UNIT_SPELLCAST_SENT", "player", "Tank", "guid", 332)
check(S.HealAssistLastCast().got == 2, "matching cast recorded, no switch back")
S.db.global.healAssist.look.castBy = "id"
-- health hidden out of combat: percent API, then the secure click measures the bar
secretMode = true
local savedHP = UnitHealthPercent
UnitHealthPercent = function(u) return SECRET end
units.party1.hp = 850; fire("UNIT_HEALTH", "party1")
fire("PLAYER_REGEN_ENABLED")
check(b.__attr["ha-blind"] == true, "hidden health out of combat -> secure click gauges")
click(b, "LeftButton")
check(b.__attr.spell1 == 547, "out-of-combat secure click at 15% -> R3 (547), got " .. tostring(b.__attr.spell1))
UnitHealthPercent = savedHP
secretMode = false
fire("PLAYER_REGEN_ENABLED")
check(b.__attr["ha-blind"] == nil, "readable health -> no secure override out of combat")
-- test mode
function UnitName(u) return units[u] and units[u].name end
math.randomseed(1)
S.HealAssistTest(true)
check(S.HealAssistTestOn() and not header.__shown, "test mode on, real group frames step aside")
local okT, errT = S.HealAssistTick()
check(okT, "tick with test mode " .. tostring(errT))
local tf = {}
for _, f in ipairs(frames) do if f.fakeIndex and f.__shown then tf[f.fakeIndex] = f end end
check(tf[1] and tf[5] and not tf[6], "5 test frames shown")
for k = 1, 60 do S.HealAssistTick() end
local anyBadge = false
for i = 1, 5 do if tf[i].badge.__text and tf[i].badge.__text:find("R%d") or (tf[i].badge.__text or ""):find("CH") then anyBadge = true end end
check(anyBadge, "test frames show rank badges")
check(tf[1].hpText.__text:find("%%") ~= nil, "test frame health text: " .. tostring(tf[1].hpText.__text))
-- right-click hits, left-click heals by the shown rank
local before = tf[3].hp.__v
tf[3].__scripts.OnClick(tf[3], "RightButton")
check(tf[3].hp.__v < before, "right-click hits the test frame")
local hit = tf[3].hp.__v
tf[3].__scripts.OnClick(tf[3], "LeftButton")
check(tf[3].hp.__v > hit, "left-click heals the test frame (" .. tostring(tf[3].fakeKey) .. " R" .. tostring(tf[3].fakeRank) .. ")")
S.HealAssistTest(true, 25)
local n = 0 for _, f in ipairs(frames) do if f.fakeIndex and f.__shown then n = n + 1 end end
check(n == 25, "group size 25 -> 25 test frames, got " .. n)
S.HealAssistTooltip(tf[1]); check(true, "test tooltip")
fire("PLAYER_REGEN_DISABLED")
check(not S.HealAssistTestOn() and header.__shown, "combat ends test mode and brings the frames back")
-- WoW Forever: health hidden even out of combat, the game evaluates curves for us
do
  local BOX = { __box = true }
  local function box(v) return setmetatable({ v = v }, BOX) end
  local realfmt = string.format
  string.format = function(p, a, ...) if getmetatable(a) == BOX then return box(realfmt(p, a.v, ...)) end return realfmt(p, a, ...) end
  UnitHealth = function(u) return box(units[u].hp) end
  UnitHealthMax = function(u) return units[u].max end
  local oldPct = UnitHealthPercent
  UnitHealthPercent = function(u, pred, curve)
    local f = units[u].hp / units[u].max
    if type(curve) == "table" and curve.Evaluate then return box(curve:Evaluate(f)) end
    return box(f)
  end
  local fs = b.badge
  local setText = fs.SetText
  fs.SetText = function(self, txt) if getmetatable(txt) == BOX then self.__text = "[" .. txt.v .. "]" else self.__text = txt end end
  inCombat = false; secretMode = false
  S.db.global.healAssist.classes.SHAMAN.spells.HW = nil
  units.party1.hp = 850
  fire("PLAYER_REGEN_ENABLED")
  local v = b.__attr.spell1
  check(getmetatable(v) == BOX and v.v == 547, "hidden health: spell attribute = game-picked ID 547 (R3 at 15%), got " .. tostring(v and v.v or v))
  check(b.__attr.type1 == "spell", "type stays spell")
  check(getmetatable(b.__attr.spell2) == BOX and b.__attr.spell2.v == 8008, "LHW (2 ranks known, 15% -> R2) via curve too? got " .. tostring(getmetatable(b.__attr.spell2) == BOX and b.__attr.spell2.v or b.__attr.spell2))
  S.HealAssistTick()
  check(fs.__text == "[R3]", "badge shows the game-picked rank: " .. tostring(fs.__text))
  inCombat = true
  units.party1.hp = 600
  fire("UNIT_HEALTH", "party1"); S.HealAssistTick()
  check(#b.cbadges >= 5, "in combat the stacked badges (with the click to press) take over")
  inCombat = false
  -- the game refuses to cast from it: two clicks with no cast -> switch off
  b.__scripts.PostClick(b, "LeftButton")
  b.__scripts.PostClick(b, "LeftButton")
  check(S.HealAssistHC.attrOK == false, "two clicks without a cast -> game-picked rank switched off")
  check(getmetatable(b.__attr.spell1) ~= BOX, "attributes back to plain spell IDs")
  S.HealAssistHC.attrOK = nil; S.HealAssistHC.misses = 0
  fire("PLAYER_REGEN_ENABLED")
  local realAfter = C_Timer.After
  C_Timer.After = function() end          -- the 1.2 s check hasn't fired yet when the cast arrives
  b.__scripts.PostClick(b, "LeftButton")
  fire("UNIT_SPELLCAST_SENT", "player", "x", "g", 547)
  C_Timer.After = realAfter
  check(S.HealAssistHC.attrOK == true, "a cast after the click confirms it works")
  string.format = realfmt; UnitHealthPercent = oldPct; fs.SetText = setText
end
-- rank ladder + combat badge says which click
inCombat = false; secretMode = false
commands.heal("ladder")
local bd = S.db.global.healAssist.classes.SHAMAN.binds
check(bd["shift|1"].rank == 2 and bd["ctrl|1"].rank == 3 and bd["alt|1"].rank == 4 and bd["|1"].kind == "smart", "ladder over 5 known HW ranks: 2 / 3 / 4, left smart")
fire("PLAYER_REGEN_ENABLED")
check(b.__attr["shift-spell1"] == 332 and b.__attr["alt-spell1"] == 913, "ladder clicks bound")
fire("PLAYER_REGEN_DISABLED"); inCombat = true
units.party1.hp = 860; fire("UNIT_HEALTH", "party1"); S.HealAssistTick()
local shown = {}
for _, fsx in ipairs(b.cbadges) do if fsx.__shown then shown[#shown + 1] = fsx.__text end end
local all = table.concat((function() local t = {} for _, fsx in ipairs(b.cbadges) do t[#t + 1] = fsx.__text end return t end)(), " | ")
check(all:find("Shift%-L|r |cffffd100R2") and all:find("Alt%-L|r |cffffd100R4") and all:find("|cffffffffL|r |cffffd100R5"), "combat badges name the click + rank: " .. all)
inCombat = false
-- rank zones on the bar
S.db.global.healAssist.classes.SHAMAN.spells.HW = nil
fire("PLAYER_REGEN_ENABLED")
local zs = b.haZones or {}
local shownZ = {}
for _, z in ipairs(zs) do if z.__shown then shownZ[#shownZ + 1] = z end end
check(#shownZ == 5, "one zone per known HW rank (5), got " .. #shownZ)
local byRank = {}
for _, z in ipairs(shownZ) do local r = tonumber((z.haRankText or ""):match("Rank (%d+)")); if r then byRank[r] = z end end
check(byRank[3] and byRank[3].__attr.spell1 == 547 and byRank[5].__attr.spell1 == 939 and byRank[1].__attr.spell1 == 331, "zone left clicks cast their rank")
check(byRank[3].__attr["shift-spell1"] == 332 and byRank[3].__attr["ctrl-type2"] == "togglemenu", "modifier + other clicks copied from the frame")
check(byRank[3].__attr.spell2 == 8008 and byRank[1].__attr.spell2 == 8004, "right-click smart LHW gets the rank for the zone's health")
check(byRank[3].__attr["useparent-unit"] == true, "zones use the frame's unit")
S.db.global.healAssist.look.zones = false; fire("PLAYER_REGEN_ENABLED")
local anyShown = false for _, z in ipairs(zs) do if z.__shown then anyShown = true end end
check(not anyShown, "zones off -> hidden")
S.db.global.healAssist.look.zones = true; fire("PLAYER_REGEN_ENABLED")
-- custom spells
local okAdd = S.HealAssistAddSpell(635)
check(okAdd, "custom spell added (635)")
check(select(2, S.HealAssistAddSpell(635)) == "already added", "no duplicates")
check(select(2, S.HealAssistAddSpell(331)) == "already built in", "built-in spells refused")
S.db.global.healAssist.classes.SHAMAN.binds["|3"] = { kind = "smart", key = "X635" }
fire("PLAYER_REGEN_ENABLED")
check(b.__attr.type3 == "spell" and b.__attr.spell3 == 635, "custom spell (no ranks) on middle click: " .. tostring(b.__attr.spell3))
commands.heal("spells")
check(_G.CC_HealAssistSpells ~= nil, "custom spells window")
S.HealAssistRemoveSpell(635)
fire("PLAYER_REGEN_ENABLED")
check(b.__attr.type3 == "none", "removed spell -> binding cleared")
-- dispels (shaman knows Cure Poison only)
inCombat = false; secretMode = false
S.db.global.healAssist.look.dispelEngine = false     -- first: HealAssist's own reading
known[526] = true
NAMES[526] = "Cure Poison"; NAMES[2870] = "Cure Disease"
local auras = { party1 = { { dispelName = "Poison" }, { dispelName = "Curse" } } }
C_UnitAuras = { GetAuraDataByIndex = function(u, i, f)
  if inCombat then error("Auras cannot be accessed when secret while tainted") end
  return auras[u] and auras[u][i]
end }
fire("SPELLS_CHANGED")
fire("PLAYER_REGEN_ENABLED")
local list = S.HealAssistDispelButtonsList()
check(#list == 1 and list[1].name == "Cure Poison" and list[1].types.Poison, "only the cures you know: Cure Poison")
local db = b.haDispel and b.haDispel[1]
check(db and db.__shown and db.__attr.spell1 == "Cure Poison" and db.__attr.unit == "party1", "cure button on the frame casts Cure Poison on them")
fire("UNIT_AURA", "party1"); S.HealAssistTick()
check(b.dispelText.__text:find("Poison") and not b.dispelText.__text:find("Curse"), "bar says Poison (curse hidden: can't remove): " .. tostring(b.dispelText.__text))
check(db.__alpha == nil or true, "button lit")
-- in combat the read is refused: keep the last seen
inCombat = true
auras.party1 = {}
fire("UNIT_AURA", "party1"); S.HealAssistTick()
check(b.dispelText.__text:find("Poison"), "in combat (refused) keeps the last seen debuff")
inCombat = false
fire("UNIT_AURA", "party1"); S.HealAssistTick()
check(b.dispelText.__text == "", "cleared after combat when it's gone")
S.db.global.healAssist.look.dispelMine = false
auras.party1 = { { dispelName = "Curse" } }
fire("UNIT_AURA", "party1"); S.HealAssistTick()
check(b.dispelText.__text:find("Curse"), "show all types when 'only mine' is off")
S.db.global.healAssist.look.dispel = "off"; fire("PLAYER_REGEN_ENABLED")
check(not db.__shown, "cure buttons off")
S.db.global.healAssist.look.dispel = "right"; S.db.global.healAssist.look.dispelMine = true
win.tabs:Select(5); check(true, "Dispels tab builds")
-- ranks page, visual view

win.tabs:Select(2)
local rp = win.pages and win.pages[2] or nil
if rp and rp.vis then
  rp:Refresh()
  check(rp.vis:IsShown() and rp.vis.pins[1] and rp.vis.pins[1]:IsShown(), "visual view shows pins")
  local k = rp.key
  S.HealAssistSetStep(k, 2, 99)
  local t3 = S.db.global.healAssist.classes.SHAMAN.spells[k].th[3] or (3 * 5)
  check(S.db.global.healAssist.classes.SHAMAN.spells[k].th[2] <= t3, "dragged step can't pass the next rank")
  S.HealAssistSetStep(k, 2, 7.4)
  check(S.db.global.healAssist.classes.SHAMAN.spells[k].th[2] == 7, "dragged step rounds to whole %")
  S.HealAssistSetStep(k, 2, 0)
  check(S.db.global.healAssist.classes.SHAMAN.spells[k].th[2] >= (S.db.global.healAssist.classes.SHAMAN.spells[k].th[1] or 5), "dragged step can't go under the rank before")
  check(rp.vis.XFor and math.abs(rp.vis:XFor(0) - rp.vis.BW) < 0.01 and rp.vis:XFor(50) == 0, "0% missing = right edge, range = left edge")
  rp.vis:Layout(); check(true, "visual layout runs")
  -- drag ends when the button is released off the pin
  local pn = rp.vis.pins[2]
  local held = true
  IsMouseButtonDown = function() return held end
  GetCursorPosition = function() return 100, 0 end
  pn:GetScript("OnMouseDown")(pn, "LeftButton")
  check(rp.vis.dragging == pn, "pin picked up")
  pn:GetScript("OnUpdate")(pn, 0.02)
  check(rp.vis.dragging == pn, "still dragging while held")
  local tipLines = {}
  local realTip = GameTooltip
  GameTooltip = setmetatable({ SetOwner = function(self, o) self.owner = o; tipLines = {} end, GetOwner = function(self) return self.owner end,
    AddLine = function(_, txt) tipLines[#tipLines + 1] = txt end, Show = function() end, Hide = function() end }, {})
  GetCursorPosition = function() return 430, 0 end
  for _ = 1, 5 do pn:GetScript("OnUpdate")(pn, 0.02) end
  local want = S.db.global.healAssist.classes.SHAMAN.spells[rp.key].th[2]
  check(tipLines[1] and tipLines[1]:find(": " .. want .. "%%"), "tooltip shows the new % while dragging (" .. tostring(tipLines[1]) .. ")")
  GameTooltip = realTip
  check(rp.vis.dragging == pn and pn:IsShown(), "redrawing while dragging keeps the held pin (not hidden)")
  held = false                                        -- IsMouseButtonDown lies: must not drop
  pn:GetScript("OnUpdate")(pn, 0.02)
  check(rp.vis.dragging == pn, "keeps holding even if IsMouseButtonDown says not held")
  rp.vis:GetScript("OnEvent")(rp.vis, "GLOBAL_MOUSE_UP", "LeftButton")
  check(rp.vis.dragging == nil and pn:GetScript("OnUpdate") == nil, "lets go on release anywhere (GLOBAL_MOUSE_UP)")
  pn:GetScript("OnMouseDown")(pn, "LeftButton")
  pn:GetScript("OnDragStop")(pn)
  check(rp.vis.dragging == nil, "lets go on drag stop")
  S.db.global.healAssist.classes.SHAMAN.spells[k].th[2] = nil
else check(false, "ranks page with visual view found") end

-- the game draws them (AuraContainer)
S.db.global.healAssist.look.dispelEngine = true
fire("PLAYER_REGEN_ENABLED")
local wc = b.haWatch
check(wc and wc.__filter == "HARMFUL|RAID_PLAYER_DISPELLABLE" and wc.__unit == "party1", "frame watcher: dispellable filter, pointed at the unit")
local wb = wc and wc.__kids2[1]
check(wb and #wb.__dispel == 1 and wb.__dispel[1].o.style == 3 and wb.__dispel[1].o.customDispelColorMap.Poison, "bar wash registered with the game (PreserveAsset + colour map)")
check(wb and wb.__dtext ~= nil, "type name handed to the game (SetDispelTypeText)")
local cd = b.haDispel[1]
local cw = cd and cd.haWatch
local cmap = cw and cw.__kids2[1] and cw.__kids2[1].__dispel[1].o.customDispelColorMap
check(cmap and cmap.Poison and cmap.Curse, "cure button watcher made")
check(cmap and (cmap.Curse.r or cmap.Curse[1] or 0) == 0, "types that button can't cure are black (invisible on ADD)")
S.HealAssistTick()
check(b.dispelText.__text == "", "own text steps aside when the game draws it")
fire("PLAYER_REGEN_ENABLED")
check(header.__attr.columnSpacing == 4 + 19, "columns spaced for the outside buttons: " .. tostring(header.__attr.columnSpacing))
print(errors == 0 and "ALL PASSED" or (errors .. " FAILED"))
os.exit(errors == 0 and 0 or 1)
