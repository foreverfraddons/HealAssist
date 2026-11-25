-- Mock harness for HealAssist.lua (texlua / Lua 5.3)
wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
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

-- ===================== class modes: heal / cure (no heals, has a cure) / off =====================
local FILE = arg[1] or "HealAssist.lua"
local CLASS = "SHAMAN"
function UnitClass() return CLASS:sub(1, 1) .. CLASS:sub(2):lower(), CLASS end
NAMES[475] = "Remove Lesser Curse"; NAMES[12345] = "Bandage Toss"
local function newS()
  local s = { db = { global = {} }, UI = UI, report = S.report }
  local ev, li, cm = {}, {}, {}
  function s:On(e, fn) ev[e] = ev[e] or {}; table.insert(ev[e], fn) end
  function s:Listen(m, fn) li[m] = li[m] or {}; table.insert(li[m], fn) end
  function s:AddCommand(c, a, d, fn) cm[c] = fn end
  s.printed = {}
  function s:Print(m) table.insert(self.printed, tostring(m)) end
  s.Trim = S.Trim
  function s:ModuleRev(n, r) s.rev = r end
  s.fire = function(e, ...) for _, fn in ipairs(ev[e] or {}) do fn(e, ...) end end
  s.listen = function(m) for _, fn in ipairs(li[m] or {}) do fn() end end
  s.cmd = cm
  return s
end
local function boot(cls, knownIds)
  CLASS = cls
  for k in pairs(known) do known[k] = nil end
  for _, id in ipairs(knownIds or {}) do known[id] = true end
  _G.CC_HealAssistGroup, _G.CC_HealAssistAnchor, _G.CC_HealAssist = nil, nil, nil
  local s = newS()
  assert(loadfile(FILE))("CommandCenter", s)
  s.listen("LOGIN")
  return s
end
local function anyPrinted(s, pat) for _, m in ipairs(s.printed) do if m:find(pat) then return true end end end

-- Mage with Remove Lesser Curse: decurse frames
local m = boot("MAGE", { 475 })
check(m.HealAssistMode() == "cure", "Mage (no heals, has a cure) -> cure mode")
local binds = m.db.global.healAssist.classes.MAGE.binds
check(binds["|1"].kind == "cure" and binds["|1"].cure == "Remove Lesser Curse", "left click = Remove Lesser Curse")
check(binds["|2"].kind == "menu" and binds["shift|1"].kind == "target", "right click = menu, Shift-left = target")
local hdr = _G.CC_HealAssistGroup
check(hdr ~= nil and hdr:IsShown(), "Mage gets frames")
local kb = hdr.__kids[1]; kb.__attr.unit = "party1"; kb.__shown = true
m.HealAssistRefreshAll()
check(kb.__attr.type1 == "spell" and kb.__attr.spell1 == 475, "the frame's left click casts the cure (spell 475)")
check(anyPrinted(m, "decurse frames"), "tells once that it's in decurse mode")
local t, v, label = m.HealAssistResolve({ kind = "cure", cure = "Remove Lesser Curse" }, "party1")
check(t == "spell" and v == 475 and label:find("Curse"), "cure click resolves with its types (" .. tostring(label) .. ")")
-- not learned yet (low level)
local m0 = boot("MAGE", {})
check(m0.HealAssistMode() == "cure", "Mage before learning the cure is still in cure mode")
local t0, _, l0 = m0.HealAssistResolve({ kind = "cure", cure = "Remove Lesser Curse" }, "party1")
check(t0 == "none" and l0:find("not learned"), "cure not learned yet -> nothing, marked not learned")
-- an existing Mage still on the old target / menu defaults is moved to cure clicks
CLASS = "MAGE"
local m1 = newS()
m1.db.global.healAssist = { classes = { MAGE = { binds = { ["|1"] = { kind = "target" }, ["|2"] = { kind = "menu" }, ["ctrl|1"] = { kind = "target" }, ["ctrl|2"] = { kind = "menu" } } } } }
_G.CC_HealAssistGroup, _G.CC_HealAssistAnchor = nil, nil
assert(loadfile(FILE))("CommandCenter", m1); m1.listen("LOGIN")
check(m1.db.global.healAssist.classes.MAGE.binds["|1"].kind == "cure", "old Mage defaults upgraded to the cure click")
-- but a Mage who set their own clicks keeps them
local m2 = newS()
m2.db.global.healAssist = { classes = { MAGE = { binds = { ["|1"] = { kind = "menu" } } } } }
_G.CC_HealAssistGroup, _G.CC_HealAssistAnchor = nil, nil
assert(loadfile(FILE))("CommandCenter", m2); m2.listen("LOGIN")
check(m2.db.global.healAssist.classes.MAGE.binds["|1"].kind == "menu", "own clicks are kept")

-- Warrior: no heals, no cures -> off
local w = boot("WARRIOR", {})
check(w.HealAssistMode() == "off", "Warrior -> off")
check(_G.CC_HealAssistGroup == nil, "no frames for a Warrior")
check(anyPrinted(w, "off on this character"), "says HealAssist is off on this character")
w.printed = {}; w.listen("LOGIN")
check(not anyPrinted(w, "off on this character"), "says it only once")
-- ...until they add a spell of their own
known[12345] = true
check(w.HealAssistAddSpell(12345) == true, "Warrior adds a spell")
check(w.HealAssistMode() == "heal" and _G.CC_HealAssistGroup ~= nil, "frames appear once the class has a spell")

-- a healer stays a healer
local sh = boot("SHAMAN", { 331, 526 })
check(sh.HealAssistMode() == "heal", "Shaman -> heal mode")
check(sh.db.global.healAssist.classes.SHAMAN.binds["|1"].kind == "auto", "healer clicks unchanged")

print(errors == 0 and "ALL PASSED (modes)" or (errors .. " FAILED (modes)"))
os.exit(errors == 0 and 0 or 1)
