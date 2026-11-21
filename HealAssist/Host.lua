-- HealAssist standalone host: the small part of Command Center that HealAssist.lua needs
-- (events, messages, saved settings, chat output, slash command), so the same
-- HealAssist.lua runs on its own.
--
-- Command Center compatibility: Command Center has HealAssist built in. When it is
-- installed (it loads first - OptionalDeps), this standalone copy steps aside: S.yield
-- makes UI.lua and HealAssist.lua return at once, so the frames never show twice.
-- /healassist then simply runs Command Center's /ccenter heal.
local ADDON, S = ...
_G.HealAssist = S

S.name = "HealAssist"
S.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
  or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "?"
S.HA_CMD = "/healassist"
S.ACCENT_HEX = "4fd1c5"

local CC = _G.CommandCenter
S.yield = (type(CC) == "table" and CC.HEALASSIST_SPELLS ~= nil) and true or false

local function ccHeal(rest)
  for _, c in ipairs(CC.commands or {}) do
    if c.cmd == "heal" then c.fn(rest or "") return true end
  end
end

SLASH_HEALASSIST1, SLASH_HEALASSIST2 = "/healassist", "/hassist"

if S.yield then
  -- Command Center runs HealAssist: forward the slash command, say so once.
  SlashCmdList.HEALASSIST = function(input)
    input = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then
      if CC.ShowHealAssist then CC:ShowHealAssist() end
    elseif not ccHeal(input) and CC.Print then
      CC:Print("HealAssist: unknown command. Try /ccenter heal.")
    end
  end
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_LOGIN")
  f:SetScript("OnEvent", function()
    -- say it once (not every login)
    HealAssistDB = type(HealAssistDB) == "table" and HealAssistDB or {}
    if HealAssistDB.ccNotice then return end
    HealAssistDB.ccNotice = true
    if CC.Print then
      CC:Print("HealAssist runs inside Command Center (|cffffff00/ccenter heal|r) - the standalone HealAssist addon stays off. Your HealAssist settings stay in Command Center while it is installed.")
    end
  end)
  return
end

---------------------------------------------------------------------------
-- Events + internal messages (same shape as Command Center's S:On / S:Listen)
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
S.eventFrame = eventFrame
local handlers, bus = {}, {}
local function report(err)
  local h = geterrorhandler and geterrorhandler()
  if h then h(err) else print(err) end
end
S.report = report

function S:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    pcall(eventFrame.RegisterEvent, eventFrame, event)   -- unknown events are ignored
  end
  table.insert(handlers[event], fn)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], event, ...)
    if not ok then report(err) end
  end
end)
function S:Listen(msg, fn)
  bus[msg] = bus[msg] or {}
  table.insert(bus[msg], fn)
end
function S:Fire(msg, ...)
  for _, fn in ipairs(bus[msg] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then report(err) end
  end
end
function S.PerfWrap(_, fn) return fn end    -- Command Center times these for /ccenter perf

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function S:Print(msg)
  msg = tostring(msg)
  local f = DEFAULT_CHAT_FRAME or ChatFrame1
  if not f then return end
  -- HealAssist's own messages already start with "HealAssist"
  if msg:find("^HealAssist") then
    f:AddMessage("|cff" .. S.ACCENT_HEX .. "HealAssist|r" .. msg:sub(11))
  else
    f:AddMessage("|cff" .. S.ACCENT_HEX .. "HealAssist|r: " .. msg)
  end
end
function S:Debug(...)
  if S.db and S.db.global.debug then S:Print("|cff888888[debug]|r " .. strjoin(" ", tostringall(...))) end
end
function S.Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
function S.Copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = S.Copy(v) end
  return o
end

---------------------------------------------------------------------------
-- Saved settings: HealAssistDB.global (HealAssist keeps its own under .healAssist,
-- exactly like inside Command Center)
---------------------------------------------------------------------------
S.defaults = {
  theme = "horde", anim = "smooth", debug = false,
  minimap = { angle = 215, hide = false },
}
function S:InitDB()
  HealAssistDB = type(HealAssistDB) == "table" and HealAssistDB or {}
  local db = HealAssistDB
  db.global = db.global or {}
  for k, v in pairs(S.defaults) do
    if db.global[k] == nil then db.global[k] = S.Copy(v) end
  end
  S.db = db
end

---------------------------------------------------------------------------
-- Slash commands: /healassist [check|test|preview|ladder|spells|minimap|theme]
---------------------------------------------------------------------------
S.commands = {}
function S:AddCommand(cmd, args, desc, fn)
  table.insert(S.commands, { cmd = cmd, args = args, desc = desc, fn = fn })
end
local function run(cmd, rest)
  for _, c in ipairs(S.commands) do
    if c.cmd == cmd then c.fn(rest or "") return true end
  end
end
SlashCmdList.HEALASSIST = function(input)
  input = S.Trim(input)
  local cmd, rest = input:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then if S.ShowHealAssist then S:ShowHealAssist() end return end
  if cmd == "help" then
    S:Print("Commands:")
    print("  |cffffff00/healassist|r - settings")
    print("  |cffffff00/healassist preview|r - test mode (a made-up group)")
    print("  |cffffff00/healassist test|r - an extra frame for yourself")
    print("  |cffffff00/healassist ladder|r - set Shift / Ctrl / Alt to three ranks")
    print("  |cffffff00/healassist spells|r - add your own spells")
    print("  |cffffff00/healassist check|r - list the ranks you know")
    print("  |cffffff00/healassist minimap|r - show / hide the minimap button")
    print("  |cffffff00/healassist news|r - what's new (|cffffff00newsoff|r: don't open it after updates)")
    print("  |cffffff00/healassist theme|r horde / classic / fel - window colours")
    return
  end
  if cmd == "minimap" then
    local m = S.db.global.minimap
    m.hide = not m.hide
    if S.MinimapButton then S.MinimapButton:SetShown(not m.hide) end
    S:Print("Minimap button " .. (m.hide and "hidden" or "shown") .. ".")
    return
  end
  if cmd == "theme" then
    local t = rest:lower()
    if S.UI and S.UI.THEMES[t] and t ~= "custom" then
      S.db.global.theme = t
      if S.UI.ApplyTheme then pcall(S.UI.ApplyTheme, S.UI) end
      S:Print("Theme: " .. S.UI.THEMES[t].name .. ".")
    else
      S:Print("Themes: horde, classic, fel.")
    end
    return
  end
  if cmd == "debug" then
    S.db.global.debug = not S.db.global.debug
    S:Print("Debug " .. (S.db.global.debug and "on" or "off"))
    return
  end
  if cmd == "news" or cmd == "newsoff" then run(cmd, rest) return end
  -- everything else is HealAssist's own "heal" command (check, test, preview, ladder, spells)
  if not run("heal", input) then S:Print("Unknown command. Type |cffffff00/healassist help|r.") end
end

---------------------------------------------------------------------------
-- Minimap button: left-click settings, right-click test mode, drag to move
---------------------------------------------------------------------------
local function makeMinimapButton()
  if not Minimap or S.MinimapButton then return end
  local m = S.db.global.minimap
  local b = CreateFrame("Button", "HealAssist_MinimapButton", Minimap)
  b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(18, 18); icon:SetPoint("CENTER", 0, 1)
  icon:SetTexture("Interface\\AddOns\\HealAssist\\Media\\UI\\i_heal")
  icon:SetVertexColor(0.88, 0.69, 0.29)
  local bg = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  bg:SetSize(22, 22); bg:SetPoint("CENTER", 0, 1)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetSize(53, 53); ring:SetPoint("TOPLEFT")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local function place()
    local a = math.rad(m.angle or 215)
    local r = (Minimap:GetWidth() / 2) + 10
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  end
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local sc = Minimap:GetEffectiveScale()
      m.angle = math.deg(math.atan2(cy / sc - my, cx / sc - mx))
      place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
      if S.HealAssistTest then S.HealAssistTest() end
    elseif S.ShowHealAssist then
      local w = _G.CC_HealAssist
      if w and w:IsShown() then w:Hide() else S:ShowHealAssist() end
    end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("HealAssist", 0.88, 0.69, 0.29)
    GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
    GameTooltip:AddLine("Right-click: test mode", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place()
  b:SetShown(not m.hide)
  S.MinimapButton = b
end

---------------------------------------------------------------------------
-- Lifecycle (same messages Command Center fires)
---------------------------------------------------------------------------
S:On("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  S:InitDB()
  if S.UI and S.UI.ApplyTheme then pcall(S.UI.ApplyTheme, S.UI) end
  S:Fire("DB_READY")
end)
S:On("PLAYER_LOGIN", function()
  S:Fire("LOGIN")
  pcall(makeMinimapButton)
end)
