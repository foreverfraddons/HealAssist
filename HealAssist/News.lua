-- HealAssist: "What's new" (patch notes after an update) and the new-version notice.
-- Patch notes come from Changelog.lua. The first login after an update shows every version you
-- haven't seen yet. Addons can't reach the internet, so a new version is found the way DBM / BigWigs
-- do it: HealAssist users in your guild and group tell each other which version they run.
-- (Standalone only - inside Command Center, Command Center has its own patch notes.)
local _, S = ...
if S.yield then return end
local UI = S.UI
local N = {}
S.News = N

local PREFIX = "HealAssist"
local function db() return S.db and S.db.global end
local function after(t, fn) if C_Timer and C_Timer.After then C_Timer.After(t, fn) else fn() end end
local function color(hex, s) return "|cff" .. hex .. s .. "|r" end

-- "1.0.3" -> comparable numbers; "next" (an unreleased build) counts as this version
local function parts(v)
  if v == "next" then v = S.version end
  local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)")
  if not a then return end
  return tonumber(a), tonumber(b), tonumber(c) or 0
end
function N.Newer(x, y)            -- is version x newer than y?
  local a1, b1, c1 = parts(x)
  local a2, b2, c2 = parts(y)
  if not a1 then return false end
  if not a2 then return true end
  if a1 ~= a2 then return a1 > a2 end
  if b1 ~= b2 then return b1 > b2 end
  return c1 > c2
end

---------------------------------------------------------------------------
-- Patch notes window
---------------------------------------------------------------------------
local SECTIONS = {
  { "added", "New", "7fdc5a" },
  { "changed", "Changed", "e0b04a" },
  { "fixed", "Fixed", "6fb7ff" },
}

-- the notes for versions newer than `since` (all of them up to this version), newest first
function N.Entries(since)
  local out = {}
  for _, e in ipairs(S.Changelog or {}) do
    local v = e.v == "next" and S.version or e.v
    if not N.Newer(v, S.version) and (not since or N.Newer(v, since)) then
      local any = false
      for _, s in ipairs(SECTIONS) do if e[s[1]] and #e[s[1]] > 0 then any = true end end
      if any then out[#out + 1] = { v = v, e = e } end
    end
  end
  return out
end

function N.Text(entries)
  local lines = {}
  for i, it in ipairs(entries) do
    if i > 1 then lines[#lines + 1] = " " end
    lines[#lines + 1] = color("4fd1c5", "Version " .. it.v)
    for _, s in ipairs(SECTIONS) do
      local list = it.e[s[1]]
      if list and #list > 0 then
        lines[#lines + 1] = color(s[3], s[2])
        for _, l in ipairs(list) do lines[#lines + 1] = color("888888", "  - ") .. color("ffffff", l) end
      end
    end
  end
  return table.concat(lines, "\n")
end

local win
local function build()
  win = UI:Window("HealAssist_News", "What's new in HealAssist", 480, 420)
  win.head = UI:Text(win, "", "small")
  win.head:SetPoint("TOPLEFT", 16, -40); win.head:SetPoint("RIGHT", -16, 0); win.head:SetJustifyH("LEFT")
  local sf, child = UI:Scroll(win, 470, 290)
  sf:SetPoint("TOPLEFT", 14, -64)
  win.scroll, win.body = sf, child
  win.text = UI:Text(child, "", "normal")
  win.text:SetPoint("TOPLEFT", 2, 0); win.text:SetWidth(420); win.text:SetJustifyH("LEFT")
  if win.text.SetSpacing then win.text:SetSpacing(3) end
  local ok = UI:PrimaryButton(win, "Got it", 90, 24, function() win:Hide() end)
  ok:SetPoint("BOTTOMRIGHT", -14, 12)
  win.update = UI:Text(win, "", "small")
  win.update:SetPoint("BOTTOMLEFT", 16, 18); win.update:SetPoint("RIGHT", ok, "LEFT", -10, 0); win.update:SetJustifyH("LEFT")
end

-- since: show the versions after this one (nil = every version)
function N:Show(since, title)
  if not win then build() end
  local entries = N.Entries(since)
  if #entries == 0 then entries = N.Entries(nil) end
  win.head:SetText(title or ("You're on version " .. S.version .. "."))
  win.text:SetText(N.Text(entries))
  win.body:SetHeight(math.max(1, (win.text:GetStringHeight() or 0) + 8))
  if win.scroll.SetVerticalScroll then win.scroll:SetVerticalScroll(0) end
  local newest = db().newestSeen
  win.update:SetText(newest and N.Newer(newest, S.version)
    and color("e0b04a", "Version " .. newest .. " is out - update on CurseForge.") or "")
  win:Show(); win:Raise()
end

-- first login after an update: the notes for every version you haven't seen
local function afterLogin()
  local g = db()
  local seen = g.newsSeen
  if seen == S.version then return end
  g.newsSeen = S.version
  if g.newsOff then return end
  if not seen then
    N:Show(nil, "Thanks for using HealAssist! Here's what's in version " .. S.version .. ".")
  elseif N.Newer(S.version, seen) then
    N:Show(seen, "HealAssist was updated to " .. S.version .. ". Here's what changed since " .. seen .. ".")
  end
end
N.AfterLogin = afterLogin

---------------------------------------------------------------------------
-- New version notice (addon messages in guild and group)
---------------------------------------------------------------------------
local told = false
local function tell(v)
  if told then return end
  told = true
  S:Print(color("e0b04a", "A new version of HealAssist is out: " .. v .. " (you have " .. S.version .. ").") .. " Update it on CurseForge.")
  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, "HealAssist " .. v .. " is available - update on CurseForge", 0.88, 0.69, 0.29)
  end
end

local function canSend()
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
  if InCombatLockdown and InCombatLockdown() then return false end
  local inInst, kind = false, nil
  if IsInInstance then inInst, kind = IsInInstance() end
  if inInst and (kind == "raid" or kind == "party") and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and locked then return false end
  end
  return true
end

local lastSent = {}
local function send(channel, force)
  if not canSend() then return end
  local now = GetTime and GetTime() or 0
  if not force and lastSent[channel] and now - lastSent[channel] < 60 then return end
  lastSent[channel] = now
  pcall(C_ChatInfo.SendAddonMessage, PREFIX, "V:" .. S.version, channel)
end

local function groupChannel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end

function N.Broadcast()
  if IsInGuild and IsInGuild() then send("GUILD") end
  local g = groupChannel()
  if g then send(g) end
end

local isSecret = issecretvalue or function() return false end
function N.OnMessage(prefix, text, channel)
  if prefix ~= PREFIX or isSecret(text) or type(text) ~= "string" then return end
  local v = text:match("^V:(%d+%.%d+%.?%d*)$")
  if not v then return end
  local g = db()
  if N.Newer(v, S.version) then
    if not g.newestSeen or N.Newer(v, g.newestSeen) then g.newestSeen = v end
    tell(v)
  elseif N.Newer(S.version, v) and channel then
    send(channel)          -- they're behind: answer with ours so they hear about it
  end
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
S:On("CHAT_MSG_ADDON", function(_, prefix, text, channel) N.OnMessage(prefix, text, channel) end)

local groupWait = false
S:On("GROUP_ROSTER_UPDATE", function()
  if groupWait then return end
  groupWait = true
  after(5, function() groupWait = false; local g = groupChannel(); if g then send(g) end end)
end)

S:Listen("LOGIN", function()
  local g = db()
  -- saw a newer version last time and still not updated: remind once
  if g.newestSeen and N.Newer(g.newestSeen, S.version) then
    after(8, function() tell(g.newestSeen) end)
  elseif g.newestSeen then
    g.newestSeen = nil
  end
  after(6, afterLogin)
  after(12, N.Broadcast)
end)

S:AddCommand("news", "", "What's new in this version (patch notes)", function() N:Show(nil) end)
S:AddCommand("newsoff", "", "Don't open the patch notes by themselves after an update (toggle)", function()
  local g = db()
  g.newsOff = not g.newsOff
  S:Print("patch notes after an update: " .. (g.newsOff and "off (type /healassist news to read them)" or "on"))
end)
