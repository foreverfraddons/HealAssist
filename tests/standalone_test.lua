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


-- ===================== standalone HealAssist (Host.lua + UI.lua + HealAssist.lua) =====================
local DIR = arg[1] or "HealAssist"
SlashCmdList = {}
UISpecialFrames = {}
tinsert = table.insert
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function tostringall(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end return table.unpack(t) end
C_AddOns = { GetAddOnMetadata = function(_, k) if k == "Version" then return "1.0.0" end end }
function CreateFont(name) local f = mock(); f.__name = name; _G[name] = f; return f end
function GetCursorPosition() return 0, 0 end
Minimap = newFrame("Frame", "Minimap")
-- real scroll frames come with a scroll bar
local baseCreate = CreateFrame
CreateFrame = function(kind, name, parent, tpl)
  local f = baseCreate(kind, name, parent, tpl)
  if kind == "ScrollFrame" then
    f.ScrollBar = baseCreate("Slider")
    f.ScrollBar.ScrollUpButton = baseCreate("Button"); f.ScrollBar.ScrollDownButton = baseCreate("Button")
  end
  if name then _G[name] = _G[name] or f end
  return f
end
Enum = Enum or {}
local chatLines = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chatLines[#chatLines + 1] = m end }
function geterrorhandler() return function(e) print("ERROR: " .. tostring(e)); errors = errors + 1 end end

local function load(S, file, addon)
  local chunk = assert(loadfile(DIR .. "/" .. file))
  chunk(addon or "HealAssist", S)
end
-- fire a game event through the host's event frame
local function event(S, e, ...)
  local fn = S.eventFrame and S.eventFrame:GetScript("OnEvent")
  if fn then fn(S.eventFrame, e, ...) end
end

-- 1) alone (no Command Center)
_G.CommandCenter = nil
local S = {}
load(S, "Host.lua"); load(S, "UI.lua"); load(S, "HealAssist.lua")
check(S.yield == false, "standalone runs when Command Center isn't there")
check(S.UI and S.UI.Window, "UI kit loaded")
check(S.HEALASSIST_SPELLS ~= nil and S.HEALASSIST_REV, "HealAssist loaded (rev " .. tostring(S.HEALASSIST_REV) .. ")")
check(S.UI.MEDIA == "Interface\\AddOns\\HealAssist\\Media\\", "media points at the HealAssist folder")
event(S, "ADDON_LOADED", "HealAssist")
check(type(HealAssistDB) == "table" and S.db == HealAssistDB, "own saved settings (HealAssistDB)")
event(S, "PLAYER_LOGIN")
check(_G.CC_HealAssistGroup ~= nil, "healing frames built at login")
check(S.db.global.healAssist ~= nil, "settings stored under HealAssistDB.global.healAssist")
check(S.MinimapButton ~= nil, "minimap button made")
check(SlashCmdList.HEALASSIST ~= nil and SLASH_HEALASSIST1 == "/healassist", "/healassist registered")
SlashCmdList.HEALASSIST("")
check(_G.CC_HealAssist ~= nil and _G.CC_HealAssist:IsShown(), "/healassist opens the settings window")
local before = #chatLines
SlashCmdList.HEALASSIST("check")
check(#chatLines > before, "/healassist check runs HealAssist's command")
local helpTxt = ""
SlashCmdList.HEALASSIST("help")
SlashCmdList.HEALASSIST("theme fel"); check(S.db.global.theme == "fel", "/healassist theme fel")
SlashCmdList.HEALASSIST("minimap"); check(S.db.global.minimap.hide == true and not S.MinimapButton:IsShown(), "/healassist minimap hides the button")
local saw = false
for _, l in ipairs(chatLines) do if l:find("/healassist") then saw = true end end
S:Print("HealAssist: x"); check(chatLines[#chatLines]:find("HealAssist|r: x"), "chat prefix not doubled")

-- 2) with Command Center (it already ran HealAssist): step aside
local ranCC = nil
_G.CommandCenter = { HEALASSIST_SPELLS = {}, commands = { { cmd = "heal", fn = function(r) ranCC = r end } },
  Print = function() end, ShowHealAssist = function() ranCC = "show" end }
_G.CC_HealAssistGroup = nil
local S2 = {}
load(S2, "Host.lua"); load(S2, "UI.lua"); load(S2, "HealAssist.lua")
check(S2.yield == true, "steps aside when Command Center has HealAssist")
check(S2.UI == nil and S2.HEALASSIST_SPELLS == nil, "UI kit and HealAssist don't run twice")
check(_G.CC_HealAssistGroup == nil, "no second set of frames")
SlashCmdList.HEALASSIST("ladder"); check(ranCC == "ladder", "/healassist forwards to /ccenter heal")
SlashCmdList.HEALASSIST(""); check(ranCC == "show", "/healassist opens Command Center's HealAssist")

-- 3) Command Center without HealAssist (older version): standalone runs
_G.CommandCenter = { commands = {} }
local S3 = {}
load(S3, "Host.lua")
check(S3.yield == false, "runs next to a Command Center that has no HealAssist")

print(errors == 0 and "ALL PASSED (standalone)" or (errors .. " FAILED (standalone)"))
os.exit(errors == 0 and 0 or 1)
