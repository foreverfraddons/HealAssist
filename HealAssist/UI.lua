-- UI toolkit: Command Center's own look (see the redesign preview): flat dark panels
-- with thin trim, a gold/green accent per theme, clean Inter text, round
-- gold-ringed icons, underline tabs and soft animations. Three themes:
-- Horde war-camp, Classic Blizzard and fel-green. Everything here
-- re-colours live when the theme changes.
-- (HealAssist standalone: a copy of Command Center's UI kit, so HealAssist looks the same
-- on its own. Media paths and frame / font names changed to HealAssist's. Regenerate
-- with tools/sync_ui.py instead of editing by hand.)
local _, S = ...
if S.yield then return end
local UI = {}
S.UI = UI

local BACKDROP_T = BackdropTemplateMixin and "BackdropTemplate" or nil
local WHITE = "Interface\\Buttons\\WHITE8x8"
local MEDIA = "Interface\\AddOns\\HealAssist\\Media\\"
UI.MEDIA = MEDIA
UI.ICON = setmetatable({}, { __index = function(_, k) return MEDIA .. "UI\\i_" .. k end })

-- Game art still used by a few pages (calendar, item slots, highlights)
UI.ART = {
  dialogBg     = "Interface\\DialogFrame\\UI-DialogBox-Background",
  dialogBgDark = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
  dialogBorder = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tipBg        = "Interface\\Tooltips\\UI-Tooltip-Background",
  tipBorder    = "Interface\\Tooltips\\UI-Tooltip-Border",
  questHL      = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
  questSel     = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight",
  statusBar    = "Interface\\TargetingFrame\\UI-StatusBar",
  horde        = "Interface\\TargetingFrame\\UI-PVP-Horde",
  check        = MEDIA .. "UI\\i_check",
  ring         = MEDIA .. "UI\\ring",
  disc         = MEDIA .. "UI\\disc",
  glow         = MEDIA .. "UI\\glow",
  noise        = MEDIA .. "UI\\noise",
}

---------------------------------------------------------------------------
-- Themes (colours from the preview)
---------------------------------------------------------------------------
local function hex(h)
  return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end
local function theme(key, name, t)
  local out = { key = key, name = name }
  for k, v in pairs(t) do out[k] = hex(v) end
  return out
end
UI.THEMES = {
  horde = theme("horde", "Horde war-camp", { bg = "1b120d", panel = "271a12", panel2 = "3a2216", edge = "6b4a2e", gold = "e0b04a",
    ribbon = "8f1d16", text = "f3e3c3", muted = "b79f80", live = "7fdc5a", line = "3b2a1d", head1 = "3c1712", head2 = "1e0f0a", field = "120c08" }),
  classic = theme("classic", "Classic Blizzard", { bg = "15110b", panel = "211a10", panel2 = "2c2214", edge = "8a6d2f", gold = "ffd100",
    ribbon = "5a4416", text = "f6e9c8", muted = "bfae86", live = "9be27a", line = "33291a", head1 = "2a2010", head2 = "140f08", field = "0e0b07" }),
  fel = theme("fel", "Fel green", { bg = "0b110c", panel = "111b13", panel2 = "16271a", edge = "2f5a35", gold = "9dff5e",
    ribbon = "1d4a1f", text = "ddf5d2", muted = "93b38a", live = "c7ff8a", line = "1d2e20", head1 = "132a15", head2 = "08100a", field = "070b08" }),
}
UI.THEME_ORDER = { "horde", "classic", "fel", "custom" }

-- colour maths for the custom theme
local function rgb2hsv(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    h = h * 60
  end
  return h, mx > 0 and d / mx or 0, mx
end
local function hsv2rgb(h, s, v)
  h = (h % 360) / 60
  local c = v * s
  local x = c * (1 - math.abs(h % 2 - 1))
  local r, g, b
  if h < 1 then r, g, b = c, x, 0 elseif h < 2 then r, g, b = x, c, 0 elseif h < 3 then r, g, b = 0, c, x
  elseif h < 4 then r, g, b = 0, x, c elseif h < 5 then r, g, b = x, 0, c else r, g, b = c, 0, x end
  local m = v - c
  return r + m, g + m, b + m
end
UI.RGBtoHSV, UI.HSVtoRGB = rgb2hsv, hsv2rgb
local function cl01(v) return v < 0 and 0 or v > 1 and 1 or v end

-- "Custom colours": a base theme re-tinted with your own accent and background colour
UI.CUSTOM_DEFAULT = { base = "horde", ah = 41, as = 0.67, av = 0.88, bh = 22, bs = 1, bv = 1, tintBg = false }
function UI:CustomSettings()
  local g = S.db and S.db.global
  if not g then return UI.CUSTOM_DEFAULT end
  if type(g.customTheme) ~= "table" then
    g.customTheme = {}
    for k, v in pairs(UI.CUSTOM_DEFAULT) do g.customTheme[k] = v end
  end
  return g.customTheme
end
local customCache, customKey
function UI:BuildCustomTheme()
  local c = UI:CustomSettings()
  local key = table.concat({ tostring(c.base), c.ah or 0, c.as or 0, c.av or 0, c.bh or 0, c.bs or 1, c.bv or 1, tostring(c.tintBg) }, ":")
  if customCache and customKey == key then return customCache end
  local base = rawget(UI.THEMES, c.base) or UI.THEMES.horde
  if c.base == "custom" then base = UI.THEMES.horde end
  local out = { key = "custom", name = "Custom colours" }
  for k, v in pairs(base) do if type(v) == "table" then out[k] = { v[1], v[2], v[3] } end end
  -- accent (the theme's gold)
  local r, g, b = hsv2rgb(c.ah or 41, cl01(c.as or 0.67), cl01(c.av or 0.88))
  out.gold = { r, g, b }
  -- backgrounds: optional new hue, plus saturation and brightness
  for _, k in ipairs({ "bg", "panel", "panel2", "edge", "line", "head1", "head2", "field", "ribbon" }) do
    local col = out[k]
    if col then
      local h, sat, v = rgb2hsv(col[1], col[2], col[3])
      if c.tintBg then h = c.bh or h; if sat < 0.25 then sat = 0.25 end end
      sat = cl01(sat * (c.bs or 1)); v = cl01(v * (c.bv or 1))
      out[k] = { hsv2rgb(h, sat, v) }
    end
  end
  customCache, customKey = out, key
  return out
end
UI.THEMES.custom = setmetatable({ key = "custom", name = "Custom colours" }, { __index = function(_, k) return UI:BuildCustomTheme()[k] end })
function UI:Theme()
  local k = S.db and S.db.global.theme or "horde"
  if k == "custom" then return UI:BuildCustomTheme() end
  return UI.THEMES[k] or UI.THEMES.horde
end
-- icon style for the dock, border bar and shortcuts: plain icons (default) or icons in circles
function UI:IconCircles() return S.db and S.db.global.iconStyle == "circle" or false end
function UI:AnimLevel() return (S.db and S.db.global.anim) or "smooth" end

-- the accent colour is the theme's gold (kept as functions other files use)
UI.accents = {}
for k, t in pairs(UI.THEMES) do if k ~= "custom" then UI.accents[t.name] = t.gold end end
function UI:Accent() local g = UI:Theme().gold; return g[1], g[2], g[3] end
function UI:AccentHex()
  local r, g, b = UI:Accent()
  return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end
local function C(c, a) return c[1], c[2], c[3], a or 1 end
UI.C = C

---------------------------------------------------------------------------
-- Fonts: Inter for text, a heading face for titles (Media\Fonts\Heading.ttf
-- if you drop one in, otherwise the game's own Friz Quadrata)
---------------------------------------------------------------------------
UI.fonts = {
  ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
  ["Arial Narrow"]  = "Fonts\\ARIALN.TTF",
  ["Morpheus"]      = "Fonts\\MORPHEUS.TTF",
  ["Skurri"]        = "Fonts\\SKURRI.TTF",
}
UI.BOLD = "Fonts\\FRIZQT__.TTF"
UI.HEAD = "Fonts\\FRIZQT__.TTF"
UI.HEAD_FALLBACK = "Fonts\\FRIZQT__.TTF"

-- set a font on a font string/object, falling back when a file is missing
-- Verify a font file actually loads in this client; cache result per path.
UI.fontOK = {}
local FRIZ = "Fonts\\FRIZQT__.TTF"
local probe
function UI:FontWorks(path)
  if not path then return false end
  if path == FRIZ then return true end
  local c = UI.fontOK[path]
  if c ~= nil then return c end
  local ok = false
  if not probe and UIParent and UIParent.CreateFontString then
    probe = UIParent:CreateFontString(nil, "BACKGROUND")
    if probe and probe.Hide then probe:Hide() end
  end
  if probe then
    local s1, r = pcall(probe.SetFont, probe, path, 12, "")
    if s1 and r ~= false then
      local s2 = pcall(probe.SetText, probe, "Ag")
      local w = s2 and probe.GetStringWidth and probe:GetStringWidth() or 0
      ok = s2 and (type(w) ~= "number" or w > 0)
    end
  end
  UI.fontOK[path] = ok and true or false
  return UI.fontOK[path]
end

function UI:SetFont(obj, kind, size, flags)
  flags = flags or ""
  local g = S.db and S.db.global or {}
  local body = UI.fonts[g.font or "Friz Quadrata"] or FRIZ
  local wants
  if kind == "head" then wants = { UI.HEAD, UI.BOLD, body }
  elseif kind == "bold" then wants = { body }
  else wants = { body } end
  for _, path in ipairs(wants) do
    if obj.__sf == path .. size .. flags then return path end
    if UI:FontWorks(path) then
      local ok, r = pcall(obj.SetFont, obj, path, size, flags)
      if ok and r ~= false then
        obj.__sf = path .. size .. flags
        -- a soft drop shadow keeps small text crisp on the dark panels
        if obj.SetShadowOffset then obj:SetShadowOffset(1, -1); obj:SetShadowColor(0, 0, 0, 0.95) end
        return path
      end
    end
  end
  pcall(obj.SetFont, obj, FRIZ, size, flags)
  return FRIZ
end

UI.fontObjects = {}
local function makeFont(name, kind, delta, color)
  local f = CreateFont(name)
  f:SetFont("Fonts\\FRIZQT__.TTF", 12 + delta, "")
  f:SetShadowOffset(1, -1)
  f:SetShadowColor(0, 0, 0, 0.9)
  UI.fontObjects[#UI.fontObjects + 1] = { obj = f, kind = kind, delta = delta, color = color }
  return f
end
UI.fSmall   = makeFont("HealAssist_FontSmall", "body", -1, "text")
UI.fNormal  = makeFont("HealAssist_FontNormal", "body", 0, "text")
UI.fLarge   = makeFont("HealAssist_FontLarge", "head", 3, "gold")
UI.fTitle   = makeFont("HealAssist_FontTitle", "head", 8, "gold")
UI.fButton  = makeFont("HealAssist_FontButton", "bold", 0, "gold")
UI.fButtonH = makeFont("HealAssist_FontButtonHL", "bold", 0, "text")
UI.fButtonD = makeFont("HealAssist_FontButtonDis", "bold", 0, "muted")
UI.fMuted   = makeFont("HealAssist_FontMuted", "body", -1, "muted")

function UI:FontList()
  local list = {}
  for k in pairs(UI.fonts) do list[#list + 1] = k end
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM then
    for _, k in ipairs(LSM:List("font")) do
      if not UI.fonts[k] then UI.fonts[k] = LSM:Fetch("font", k); list[#list + 1] = k end
    end
  end
  table.sort(list)
  return list
end

---------------------------------------------------------------------------
-- Theme registry: everything that colours itself from the theme
---------------------------------------------------------------------------
local skins = setmetatable({}, { __mode = "k" })
function UI:Skin(obj, fn)
  skins[obj] = fn
  local ok, err = pcall(fn, obj, UI:Theme())
  if not ok and S.Debug then S:Debug("skin: " .. tostring(err)) end
  return obj
end
local accentRegs = {}
UI.RegAccent = function(kind, obj, alpha) accentRegs[#accentRegs + 1] = { kind, obj, alpha or 1 } end

function UI:ApplyTheme()
  local g = S.db.global
  local th = UI:Theme()
  local size = tonumber(g.fontSize) or 12
  for _, f in ipairs(UI.fontObjects) do
    UI:SetFont(f.obj, f.kind, size + f.delta)
    local c = th[f.color] or th.text
    f.obj:SetTextColor(C(c))
  end
  S.ACCENT_HEX = UI:AccentHex()
  local r, gg, b = UI:Accent()
  for _, reg in ipairs(accentRegs) do
    local kind, obj, a = reg[1], reg[2], reg[3]
    if kind == "border" then obj:SetBackdropBorderColor(r, gg, b, a)
    elseif kind == "tex" then obj:SetColorTexture(r, gg, b, a)
    elseif kind == "vertex" then obj:SetVertexColor(r, gg, b, a)
    elseif kind == "text" then obj:SetTextColor(r, gg, b, a)
    elseif kind == "fn" then obj(r, gg, b) end
  end
  for obj, fn in pairs(skins) do pcall(fn, obj, th) end
  if S.ApplyMainTheme then S:ApplyMainTheme() end
end
function UI:RethemeDialogs() end   -- kept for older callers

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function ensureBackdrop(f)
  if not f.SetBackdrop and BackdropTemplateMixin then Mixin(f, BackdropTemplateMixin) end
end
UI.EnsureBackdrop = ensureBackdrop

---------------------------------------------------------------------------
-- Rounded corners: 9-slice fill + border built from Media\UI\rfill / redge
-- (64px textures, 24px corner region). Everything flat goes through this.
---------------------------------------------------------------------------
local RC = 24 / 64
local SLICE = {  -- name, texcoords
  TL = { 0, RC, 0, RC },       T = { RC, 1 - RC, 0, RC },       TR = { 1 - RC, 1, 0, RC },
  L  = { 0, RC, RC, 1 - RC },  C = { RC, 1 - RC, RC, 1 - RC },  R  = { 1 - RC, 1, RC, 1 - RC },
  BL = { 0, RC, 1 - RC, 1 },   B = { RC, 1 - RC, 1 - RC, 1 },   BR = { 1 - RC, 1, 1 - RC, 1 },
}
local function sliceSet(f, file, layer, sub, skipCenter)
  local set = { f = f }
  for k, tc in pairs(SLICE) do
    if not (skipCenter and k == "C") then
      local t = f:CreateTexture(nil, layer, nil, sub)
      t:SetTexture(file); t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
      set[k] = t
    end
  end
  return set
end
local function sliceLayout(set, r, inset)
  inset = inset or 0
  local f = set.f
  local w, h = f:GetWidth() or 0, f:GetHeight() or 0
  if w > 0 and h > 0 then r = math.max(1, math.min(r, math.floor(math.min(w, h) / 2))) end
  local function P(t, ...) if t then t:ClearAllPoints(); t:SetPoint(...) end end
  local function Z(t, a, b) if t then t:SetSize(a, b) end end
  P(set.TL, "TOPLEFT", f, "TOPLEFT", inset, -inset); Z(set.TL, r, r)
  P(set.TR, "TOPRIGHT", f, "TOPRIGHT", -inset, -inset); Z(set.TR, r, r)
  P(set.BL, "BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset); Z(set.BL, r, r)
  P(set.BR, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset); Z(set.BR, r, r)
  for _, k in ipairs({ "T", "B", "L", "R", "C" }) do if set[k] then set[k]:ClearAllPoints() end end
  set.T:SetPoint("TOPLEFT", set.TL, "TOPRIGHT"); set.T:SetPoint("BOTTOMRIGHT", set.TR, "BOTTOMLEFT")
  set.B:SetPoint("TOPLEFT", set.BL, "TOPRIGHT"); set.B:SetPoint("BOTTOMRIGHT", set.BR, "BOTTOMLEFT")
  set.L:SetPoint("TOPLEFT", set.TL, "BOTTOMLEFT"); set.L:SetPoint("BOTTOMRIGHT", set.BL, "TOPRIGHT")
  set.R:SetPoint("TOPLEFT", set.TR, "BOTTOMLEFT"); set.R:SetPoint("BOTTOMRIGHT", set.BR, "TOPRIGHT")
  if set.C then set.C:SetPoint("TOPLEFT", set.TL, "BOTTOMRIGHT"); set.C:SetPoint("BOTTOMRIGHT", set.BR, "TOPLEFT") end
end
local function sliceColor(set, r, g, b, a)
  for k in pairs(SLICE) do local t = set[k]; if t then t:SetVertexColor(r, g, b, a or 1) end end
end
local function sliceShown(set, on)
  for k in pairs(SLICE) do local t = set[k]; if t then t:SetShown(on) end end
end
UI.Slice = { new = sliceSet, layout = sliceLayout, color = sliceColor, shown = sliceShown }
UI.RADIUS = 6

-- give a frame a rounded fill + border. SetBackdropColor / SetBackdropBorderColor
-- keep working on it (they repaint the rounded pieces).
local function rounded(f, es, radius)
  if f.__round then return f.__round end
  local rd = { es = es, r = radius or (es >= 2 and 8 or UI.RADIUS) }
  rd.fill = sliceSet(f, MEDIA .. "UI\\rfill", "BACKGROUND", -8)
  rd.edge = sliceSet(f, MEDIA .. "UI\\redge" .. (es >= 2 and 2 or 1), "BACKGROUND", 7, true)
  local function relayout() sliceLayout(rd.fill, rd.r); sliceLayout(rd.edge, rd.r) end
  relayout()
  if f.HookScript then f:HookScript("OnSizeChanged", relayout) end
  rd.relayout = relayout
  -- old backdrop API, redirected
  if f.SetBackdrop and not f.__hadRealBackdrop then pcall(f.SetBackdrop, f, nil) end
  f.SetBackdropColor = function(self, r, g, b, a) sliceColor(rd.fill, r, g, b, a) end
  f.SetBackdropBorderColor = function(self, r, g, b, a) sliceColor(rd.edge, r, g, b, a); sliceShown(rd.edge, (a or 1) > 0) end
  f.__round = rd
  return rd
end
UI.Rounded = rounded

-- rounded box filled with a vertical gradient: top cap row, gradient body, bottom cap row.
-- g:Colors(capTop, gradTop, gradBottom, capBottom) - each {r,g,b[,a]}
function UI:RoundGradient(f, layer, sub, r, inset)
  r, inset = r or UI.RADIUS, inset or 0
  local s = sliceSet(f, MEDIA .. "UI\\rfill", layer or "BACKGROUND", sub or 2)
  for _, k in ipairs({ "L", "C", "R" }) do s[k]:Hide() end
  local function P(t, ...) t:ClearAllPoints(); t:SetPoint(...) end
  P(s.TL, "TOPLEFT", f, "TOPLEFT", inset, -inset); s.TL:SetSize(r, r)
  P(s.TR, "TOPRIGHT", f, "TOPRIGHT", -inset, -inset); s.TR:SetSize(r, r)
  P(s.BL, "BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset); s.BL:SetSize(r, r)
  P(s.BR, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset); s.BR:SetSize(r, r)
  s.T:SetPoint("TOPLEFT", s.TL, "TOPRIGHT"); s.T:SetPoint("BOTTOMRIGHT", s.TR, "BOTTOMLEFT")
  s.B:SetPoint("TOPLEFT", s.BL, "TOPRIGHT"); s.B:SetPoint("BOTTOMRIGHT", s.BR, "BOTTOMLEFT")
  local mid = f:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 2)
  mid:SetPoint("TOPLEFT", s.TL, "BOTTOMLEFT"); mid:SetPoint("BOTTOMRIGHT", s.BR, "TOPRIGHT")
  local g = { slices = s, mid = mid }
  function g:Colors(capTop, gTop, gBot, capBot)
    for _, k in ipairs({ "TL", "T", "TR" }) do s[k]:SetVertexColor(capTop[1], capTop[2], capTop[3], capTop[4] or 1) end
    for _, k in ipairs({ "BL", "B", "BR" }) do s[k]:SetVertexColor(capBot[1], capBot[2], capBot[3], capBot[4] or 1) end
    UI:Gradient(mid, "VERTICAL", gBot[1], gBot[2], gBot[3], gBot[4] or 1, gTop[1], gTop[2], gTop[3], gTop[4] or 1)
  end
  return g
end

-- a strip along the top of a rounded box: rounded top corners, square bottom
function UI:TopRounded(f, layer, sub, inset, r, h)
  local s = sliceSet(f, MEDIA .. "UI\\rfill", layer, sub)
  for _, k in ipairs({ "L", "C", "R", "BL", "B", "BR" }) do s[k]:Hide() end
  s.TL:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset); s.TL:SetSize(r, r)
  s.TR:SetPoint("TOPRIGHT", f, "TOPRIGHT", -inset, -inset); s.TR:SetSize(r, r)
  s.T:SetPoint("TOPLEFT", s.TL, "TOPRIGHT"); s.T:SetPoint("BOTTOMRIGHT", s.TR, "BOTTOMLEFT")
  local body = f:CreateTexture(nil, layer, nil, sub); body:SetTexture(WHITE)
  body:SetPoint("TOPLEFT", s.TL, "BOTTOMLEFT"); body:SetPoint("TOPRIGHT", s.TR, "BOTTOMRIGHT"); body:SetHeight(math.max(1, h - r))
  local o = { slices = s, body = body }
  function o:Color(r1, g1, b1, a1)
    for _, k in ipairs({ "TL", "T", "TR" }) do s[k]:SetVertexColor(r1, g1, b1, a1) end
    body:SetVertexColor(r1, g1, b1, a1)
  end
  return o
end

-- flat fill + thin border (rounded)
local function flat(f, bg, bgA, edge, edgeA, edgeSize)
  local es = edgeSize or 1
  local rd = f.__round
  if rd and rd.es ~= es then
    -- edge thickness changed: rebuild the border pieces
    sliceShown(rd.edge, false)
    rd.edge = sliceSet(f, MEDIA .. "UI\\redge" .. (es >= 2 and 2 or 1), "BACKGROUND", 7, true)
    rd.es, rd.r = es, es >= 2 and 8 or UI.RADIUS
    rd.relayout()
  end
  rd = rounded(f, es)
  f:SetBackdropColor(bg[1], bg[2], bg[3], bgA or 1)
  f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edgeA or 1)
end
UI.Flat = flat

function UI:Gradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
  tex:SetTexture(WHITE)
  if CreateColor and tex.SetGradient and pcall(tex.SetGradient, tex, orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2)) then return end
  if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, orient, r1, g1, b1, a1, r2, g2, b2, a2) then return end
  tex:SetColorTexture(r1, g1, b1, (a1 + a2) / 2)
end

-- an icon from Media\UI tinted with a theme colour
function UI:Icon(parent, name, size, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(UI.ICON[name]); t:SetSize(size or 20, size or 20)
  return t
end

-- Entrance animation (window / page / tile), following the animation setting
-- Fade + short slide. (No Scale animations: WoW rasterises text at the
-- animation's scale and keeps it, which made text shrink and look ragged.)
function UI:Animate(f, kind, delay)
  if not f or not f.CreateAnimationGroup then return end
  local level = UI:AnimLevel()
  if level == "minimal" and kind ~= "window" then return end
  f.__ag = f.__ag or {}
  local ag = f.__ag[kind]
  if not ag then
    ag = f:CreateAnimationGroup()
    if type(ag) ~= "table" and type(ag) ~= "userdata" then return end
    if not ag.CreateAnimation then return end
    local a = ag:CreateAnimation("Alpha")
    if not a then return end
    if a.SetFromAlpha then a:SetFromAlpha(0); a:SetToAlpha(1) else pcall(a.SetChange, a, 1) end
    ag.alpha = a
    ag.jump = ag:CreateAnimation("Translation")   -- instant drop
    ag.slide = ag:CreateAnimation("Translation")  -- glide back up
    if not ag.jump or not ag.slide then return end
    f.__ag[kind] = ag
  end
  ag:Stop()
  local flashy = level == "flashy"
  local dur = (kind == "window" and 0.18) or (flashy and 0.4) or 0.28
  local d = (level == "minimal") and 0 or (delay or 0)
  local dist = (level == "minimal" or kind == "window") and 0 or (flashy and (kind == "tile" and 18 or 10) or 6)
  ag.alpha:SetDuration(dur); ag.alpha:SetStartDelay(d); ag.alpha:SetOrder(1)
  ag.jump:SetDuration(0.001); ag.jump:SetStartDelay(0); ag.jump:SetOrder(1); ag.jump:SetOffset(0, -dist)
  ag.slide:SetDuration(dur); ag.slide:SetStartDelay(d); ag.slide:SetOrder(1); ag.slide:SetOffset(0, dist)
  if ag.slide.SetSmoothing then ag.slide:SetSmoothing("OUT") end
  if d > 0 and ag.alpha.SetFromAlpha then f:SetAlpha(0) end
  ag:SetScript("OnFinished", function() f:SetAlpha(1) end)
  ag:SetScript("OnStop", function() f:SetAlpha(1) end)
  if not pcall(ag.Play, ag) then f:SetAlpha(1); return end
  -- safety net: never leave a frame invisible if the animation misbehaves
  if C_Timer and C_Timer.After then C_Timer.After(d + dur * 2 + 0.3, function() if f:GetAlpha() < 1 and not ag:IsPlaying() then f:SetAlpha(1) end end) end
end

---------------------------------------------------------------------------
-- Backdrops / panels
---------------------------------------------------------------------------
-- A content panel: theme panel colour, thin edge. bg = {r,g,b,a}: only the alpha is used.
function UI:Backdrop(f, bg, borderAlpha)
  local a = bg and bg[4] or 0.9
  f.__bgA = math.max(a, 0.55)
  f.__edgeA = borderAlpha or 1
  UI:Skin(f, function(self, th) flat(self, th.panel, self.__bgA, th.edge, math.max(0.5, self.__edgeA)) end)
end

-- Windows / popups: dark base with the theme trim
function UI:DialogBackdrop(f, dark)
  UI:Skin(f, function(self, th) flat(self, th.bg, 0.97, th.edge, 1, 2) end)
end

function UI:Panel(parent, w, h, bg, borderAlpha)
  local f = CreateFrame("Frame", nil, parent, BACKDROP_T)
  if w then f:SetSize(w, h) end
  UI:Backdrop(f, bg, borderAlpha)
  return f
end

-- (the old faded crest; the new look keeps panels clean)
function UI:Watermark(parent)
  local t = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
  t:Hide()
  return t
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
function UI:Text(parent, text, size, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject((size == "small" and UI.fSmall) or (size == "large" and UI.fLarge) or (size == "title" and UI.fTitle)
    or (size == "muted" and UI.fMuted) or UI.fNormal)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetText(text or "")
  return fs
end

function UI:TextPool(parent)
  local pool = { list = {}, used = 0 }
  function pool:Reset() for _, fs in ipairs(self.list) do fs:Hide() end self.used = 0 end
  function pool:Get(text, size)
    self.used = self.used + 1
    local fs = self.list[self.used]
    if not fs then fs = UI:Text(parent, "", size); self.list[self.used] = fs end
    fs:SetFontObject((size == "small" and UI.fSmall) or (size == "large" and UI.fLarge) or UI.fNormal)
    fs:ClearAllPoints(); fs:SetWidth(0); fs:SetWordWrap(true)
    local th = UI:Theme()
    if size == "large" then fs:SetTextColor(C(th.gold)) else fs:SetTextColor(C(th.text)) end
    fs:SetText(text or ""); fs:Show()
    return fs
  end
  return pool
end

-- Section heading (heading font, theme gold)
function UI:Header(parent, text)
  return UI:Text(parent, text, "large")
end

-- thin divider fading out to the right
function UI:Line(parent, w)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetHeight(1); if w then t:SetWidth(w) end
  UI:Skin(t, function(self, th) UI:Gradient(self, "HORIZONTAL", th.edge[1], th.edge[2], th.edge[3], 1, th.edge[1], th.edge[2], th.edge[3], 0.1) end)
  return t
end

function UI:Tip(frame, title, lines)
  frame:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local g = UI:Theme().gold
    GameTooltip:SetText(type(title) == "function" and title() or title or "", g[1], g[2], g[3])
    local l = type(lines) == "function" and lines() or lines
    if type(l) == "string" then l = { l } end
    for _, line in ipairs(l or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local function makeButton(parent, text, w, h, onClick, tip, primary)
  local b = CreateFrame("Button", nil, parent, BACKDROP_T)
  b:SetSize(w or 100, h or 24)
  local fs = b:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(UI.fButton); fs:SetWordWrap(false)
  fs:SetPoint("LEFT", 6, 0); fs:SetPoint("RIGHT", -6, 0); fs:SetJustifyH("CENTER")
  b:SetFontString(fs)
  b:SetText(text or "")
  b.text, b.fs = fs, fs
  b.primary = primary
  local function paint(self, th)
    th = th or UI:Theme()
    local hot = self.__hot and self:IsEnabled()
    if self.primary then
      flat(self, hot and { th.ribbon[1] * 1.25, th.ribbon[2] * 1.25, th.ribbon[3] * 1.25 } or th.ribbon, 1, th.gold, 1)
      fs:SetTextColor(C(th.text))
    else
      flat(self, hot and { th.panel2[1] * 1.3, th.panel2[2] * 1.3, th.panel2[3] * 1.3 } or th.panel2, 1, hot and th.gold or th.edge, 1)
      fs:SetTextColor(C(hot and th.text or th.gold))
    end
    if not self:IsEnabled() then fs:SetTextColor(C(th.muted)); self:SetAlpha(0.6) else self:SetAlpha(1) end
  end
  b.Paint = paint
  UI:Skin(b, paint)
  b:HookScript("OnEnter", function(self) self.__hot = true; paint(self) end)
  b:HookScript("OnLeave", function(self) self.__hot = false; paint(self) end)
  b:HookScript("OnEnable", function(self) paint(self) end)
  b:HookScript("OnDisable", function(self) paint(self) end)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, button)
    if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
    if onClick then onClick(self, button) end
  end)
  if tip then UI:Tip(b, text, tip) end
  return b
end
function UI:Button(parent, text, w, h, onClick, tip) return makeButton(parent, text, w, h, onClick, tip, false) end
function UI:PrimaryButton(parent, text, w, h, onClick, tip) return makeButton(parent, text, w, h, onClick, tip, true) end

-- square icon button (header buttons in the preview)
-- small borderless X matching the window close button
function UI:CloseIcon(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size or 22, size or 22)
  b.icon = UI:Icon(b, "close", math.floor((size or 22) * 0.55)); b.icon:SetPoint("CENTER")
  local function paint(self) self.icon:SetVertexColor(C(self.__hot and UI:Theme().gold or UI:Theme().muted)) end
  paint(b)
  b:SetScript("OnEnter", function(self) self.__hot = true; paint(self) end)
  b:SetScript("OnLeave", function(self) self.__hot = false; paint(self) end)
  return b
end

function UI:IconButton(parent, icon, size, tip, onClick)
  local b = CreateFrame("Button", nil, parent, BACKDROP_T)
  b:SetSize(size or 40, size or 40)
  b.icon = UI:Icon(b, icon, math.floor((size or 40) * 0.5))
  b.icon:SetPoint("CENTER")
  local function paint(self, th)
    th = th or UI:Theme()
    flat(self, th.panel, 1, self.__hot and th.gold or th.edge, 1)
    self.icon:SetVertexColor(C(th.gold))
  end
  UI:Skin(b, paint)
  b:SetScript("OnEnter", function(self) self.__hot = true; paint(self) end)
  b:SetScript("OnLeave", function(self) self.__hot = false; paint(self); GameTooltip:Hide() end)
  b:HookScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", 1, -1) end)
  b:HookScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER", 0, 0) end)
  b:SetScript("OnClick", function(self, btn)
    if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
    if onClick then onClick(self, btn) end
  end)
  if tip then UI:Tip(b, tip) end
  return b
end

---------------------------------------------------------------------------
-- Edit box
---------------------------------------------------------------------------
function UI:Edit(parent, w, h, placeholder, onEnter, numeric)
  local e = CreateFrame("EditBox", nil, parent, BACKDROP_T)
  e:SetSize(w or 120, h or 24)
  e:SetFontObject(UI.fNormal)
  e:SetTextInsets(8, 8, 0, 0)
  e:SetAutoFocus(false)
  if numeric and e.SetNumeric then e:SetNumeric(true) end
  local function paint(self, th)
    th = th or UI:Theme()
    flat(self, th.field, 0.95, self:HasFocus() and th.gold or th.edge, 1)
    self:SetTextColor(C(th.text))
  end
  UI:Skin(e, paint)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus(); if onEnter then onEnter(self, self:GetText()) end end)
  e:SetScript("OnEditFocusGained", function(self) self:HighlightText(0, 0); paint(self) end)
  e:HookScript("OnEditFocusLost", function(self) paint(self) end)
  if placeholder then
    e.ph = UI:Text(e, placeholder, "muted")
    e.ph:SetPoint("LEFT", 8, 0); e.ph:SetPoint("RIGHT", -8, 0); e.ph:SetWordWrap(false)
    local function upd(self) self.ph:SetShown(self:GetText() == "" and not self:HasFocus()) end
    e:HookScript("OnTextChanged", upd)
    e:HookScript("OnEditFocusGained", upd)
    e:HookScript("OnEditFocusLost", upd)
  end
  return e
end

---------------------------------------------------------------------------
-- Check box
---------------------------------------------------------------------------
function UI:Check(parent, label, checked, onChange, tip)
  local b = CreateFrame("CheckButton", nil, parent, BACKDROP_T)
  b:SetSize(18, 18)
  local tick = UI:Icon(b, "check", 18, "OVERLAY"); tick:SetPoint("CENTER")
  b:SetCheckedTexture(tick)
  b.label = UI:Text(b, label)
  b.label:SetPoint("LEFT", b, "RIGHT", 8, 0)
  local function paint(self, th)
    th = th or UI:Theme()
    flat(self, th.field, 1, self.__hot and th.gold or th.edge, 1)
    tick:SetVertexColor(C(th.gold))
  end
  UI:Skin(b, paint)
  local function fitHit() b:SetHitRectInsets(0, -math.max(60, (b.label:GetStringWidth() or 0) + 10), 0, 0) end
  fitHit()
  b:HookScript("OnShow", fitHit)
  b:HookScript("OnEnter", function(self) self.__hot = true; paint(self) end)
  b:HookScript("OnLeave", function(self) self.__hot = false; paint(self) end)
  b:SetChecked(checked and true or false)
  b:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
      PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
    if onChange then onChange(on) end
  end)
  if tip then UI:Tip(b, label, tip) end
  return b
end

---------------------------------------------------------------------------
-- Slider: label on the left, track, value on the right
---------------------------------------------------------------------------
function UI:Slider(parent, w, label, min, max, step, value, onChange, fmt)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(w, 22)
  f.label = UI:Text(f, label, "small"); f.label:SetPoint("LEFT", 0, 0); f.label:SetWidth(130); f.label:SetJustifyH("LEFT")
  local sl = CreateFrame("Slider", nil, f, BACKDROP_T)
  sl:SetOrientation("HORIZONTAL")
  sl:SetPoint("LEFT", 136, 0); sl:SetPoint("RIGHT", -52, 0); sl:SetHeight(14)
  sl:SetMinMaxValues(min, max); sl:SetValueStep(step or 1)
  if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
  local thumb = sl:CreateTexture(nil, "OVERLAY"); thumb:SetTexture(MEDIA .. "UI\\disc"); thumb:SetSize(14, 14)
  sl:SetThumbTexture(thumb)
  f.fill = sl:CreateTexture(nil, "ARTWORK"); f.fill:SetTexture(WHITE); f.fill:SetPoint("LEFT", 2, 0); f.fill:SetHeight(4)
  f.val = UI:Text(f, "", "small", "RIGHT"); f.val:SetPoint("RIGHT", 0, 0); f.val:SetWidth(48)
  UI:Skin(sl, function(self, th)
    flat(self, th.field, 1, th.edge, 1)
    thumb:SetVertexColor(C(th.gold)); f.fill:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.6)
  end)
  local lo, hi = min, max
  local function show(v)
    f.val:SetText(fmt and fmt(v) or tostring(math.floor(v + 0.5)))
    local pct = (hi > lo) and (v - lo) / (hi - lo) or 0
    f.fill:SetWidth(math.max(1, (w - 192) * pct))
  end
  sl:SetScript("OnValueChanged", function(_, v)
    if (step or 1) >= 1 then v = math.floor(v + 0.5) end
    show(v)
    if not f.quiet and onChange then onChange(v) end
  end)
  f.slider = sl
  function f:SetValue(v) self.quiet = true; sl:SetValue(v); show(v); self.quiet = false end
  function f:GetValue() return sl:GetValue() end
  f:SetValue(value or min)
  return f
end

---------------------------------------------------------------------------
-- Popup menu + dropdown
---------------------------------------------------------------------------
local menu, blocker
function UI:CloseMenu() if menu then menu:Hide(); blocker:Hide() end end

-- items: { { text=, func=, disabled=, title=, checked= }, ... }
function UI:Menu(anchor, items)
  if not menu then
    blocker = CreateFrame("Frame", nil, UIParent)
    blocker:SetAllPoints(UIParent)
    blocker:SetFrameStrata("TOOLTIP")        -- above every window, the wizard and tour included
    blocker:EnableMouse(true)
    blocker:SetScript("OnMouseDown", function() UI:CloseMenu() end)
    menu = CreateFrame("Frame", nil, UIParent, BACKDROP_T)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(blocker:GetFrameLevel() + 10)
    UI:Skin(menu, function(self, th) flat(self, th.bg, 0.98, th.edge, 1) end)
    menu.buttons = {}
    menu:SetClampedToScreen(true)
  end
  local th = UI:Theme()
  for _, mb in ipairs(menu.buttons) do mb:Hide() end
  local width, y = 140, -6
  for i, it in ipairs(items) do
    local mb = menu.buttons[i]
    if not mb then
      mb = CreateFrame("Button", nil, menu)
      mb:SetHeight(22)
      mb.check = UI:Icon(mb, "check", 14); mb.check:SetPoint("LEFT", 4, 0)
      mb.text = UI:Text(mb, "", "normal")
      local hl = mb:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(WHITE)
      mb.hl = hl
      menu.buttons[i] = mb
    end
    mb:ClearAllPoints()
    mb:SetPoint("TOPLEFT", 6, y)
    mb:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
    mb.hl:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.14)
    mb.check:SetVertexColor(C(th.gold))
    mb.check:SetShown(it.checked and true or false)
    mb.text:SetText(it.text or "")
    mb.text:ClearAllPoints()
    if it.title then
      mb.text:SetFontObject(UI.fMuted); mb.text:SetTextColor(C(th.gold)); mb.text:SetPoint("LEFT", 4, -2)
      mb:SetHeight(20)
    else
      mb.text:SetFontObject(UI.fNormal); mb.text:SetPoint("LEFT", 24, 0)
      if it.disabled then mb.text:SetTextColor(C(th.muted)) else mb.text:SetTextColor(C(th.text)) end
      mb:SetHeight(22)
    end
    mb:SetEnabled(not it.title and not it.disabled)
    -- optional explanation on hover
    mb:SetScript("OnEnter", it.tip and function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local g = th.gold
      GameTooltip:SetText(it.text or "", g[1], g[2], g[3])
      GameTooltip:AddLine(type(it.tip) == "function" and it.tip() or it.tip, 1, 1, 1, true)
      GameTooltip:Show()
    end or nil)
    mb:SetScript("OnLeave", it.tip and function() GameTooltip:Hide() end or nil)
    mb:SetScript("OnClick", function()
      if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
      -- keep = a tick box: the menu stays open so you can tick several
      if it.keep then
        if it.func then it.func() end
        it.checked = not it.checked
        mb.check:SetShown(it.checked and true or false)
        return
      end
      UI:CloseMenu()
      if it.func then it.func() end
    end)
    mb:Show()
    width = math.max(width, (mb.text:GetStringWidth() or 0) + 44)
    y = y - mb:GetHeight()
  end
  menu:SetSize(width, -y + 6)
  menu:ClearAllPoints()
  if anchor then menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  else local x, yy = GetCursorPosition(); local s = UIParent:GetEffectiveScale(); menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, yy / s) end
  blocker:Show(); menu:Show()
  menu:SetFrameLevel(blocker:GetFrameLevel() + 10); menu:Raise()
  UI:Animate(menu, "window")
end

-- options: array of strings or { text=, value= }; onSelect(value, text)
function UI:Dropdown(parent, w, options, selected, onSelect)
  w = w or 140
  local d = CreateFrame("Button", nil, parent, BACKDROP_T)
  d:SetSize(w, 24)
  d.chev = UI:Icon(d, "down", 14); d.chev:SetPoint("RIGHT", -8, 0)
  d.text = UI:Text(d, "", "normal")
  d.text:SetPoint("LEFT", 8, 0); d.text:SetPoint("RIGHT", d.chev, "LEFT", -4, 0)
  d.text:SetWordWrap(false)
  local enabled = true
  local function paint(self, th)
    th = th or UI:Theme()
    flat(self, th.field, 0.95, (self.__hot and enabled) and th.gold or th.edge, 1)
    self.chev:SetVertexColor(C(th.gold))
    self.text:SetTextColor(C(enabled and th.text or th.muted))
  end
  UI:Skin(d, paint)
  d:SetScript("OnEnter", function(self) self.__hot = true; paint(self) end)
  d:SetScript("OnLeave", function(self) self.__hot = false; paint(self) end)
  d.options = options
  function d:GetOptions() return type(self.options) == "function" and self.options() or self.options end
  function d:SetValue(v)
    self.value = v
    for _, o in ipairs(self:GetOptions() or {}) do
      local val, txt = o, o
      if type(o) == "table" then val, txt = o.value, o.text end
      if val == v then self.text:SetText(txt) return end
    end
    self.text:SetText(v ~= nil and tostring(v) or "")
  end
  function d:SetEnabled(v) enabled = v and true or false; paint(self) end
  d:SetScript("OnClick", function(self)
    if not enabled then return end
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    local items = {}
    for _, o in ipairs(self:GetOptions() or {}) do
      local val, txt = o, o
      if type(o) == "table" then val, txt = o.value, o.text end
      items[#items + 1] = { text = txt, checked = (val == self.value), func = function() self:SetValue(val); if onSelect then onSelect(val, txt) end end }
    end
    UI:Menu(self, items)
  end)
  d:SetValue(selected)
  return d
end

---------------------------------------------------------------------------
-- Scroll bars: thin themed bar for the game's scroll-frame template
---------------------------------------------------------------------------
function UI:SkinScrollFrame(sf)
  if not sf then return end
  local bar = sf.ScrollBar or (sf.GetName and sf:GetName() and _G[sf:GetName() .. "ScrollBar"])
  if not bar and sf.GetChildren then
    for _, c in ipairs({ sf:GetChildren() }) do if c.GetObjectType and c:GetObjectType() == "Slider" then bar = c end end
  end
  if not bar or bar.__skinned then return end
  bar.__skinned = true
  -- hide the arrow buttons and the stock art
  for _, c in ipairs({ bar:GetChildren() }) do if c.Hide then c:SetAlpha(0); if c.EnableMouse then c:EnableMouse(false) end end end
  for _, r in ipairs({ bar:GetRegions() }) do if r.GetObjectType and r:GetObjectType() == "Texture" then r:SetAlpha(0) end end
  local track = bar:CreateTexture(nil, "BACKGROUND", nil, 7); track:SetTexture(WHITE)
  track:SetPoint("TOP", 0, 14); track:SetPoint("BOTTOM", 0, -14); track:SetWidth(4)
  local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
  if bar.SetThumbTexture then bar:SetThumbTexture(MEDIA .. "UI\\pill"); thumb = bar:GetThumbTexture() end
  if thumb then thumb:SetSize(6, 34); thumb:SetAlpha(1) end
  UI:Skin(bar, function(self, th)
    track:SetVertexColor(th.line[1], th.line[2], th.line[3], 1)
    if thumb then thumb:SetVertexColor(C(th.gold)) end
  end)
end

local scrollId = 0
function UI:Scroll(parent, w, h)
  scrollId = scrollId + 1
  local sf = CreateFrame("ScrollFrame", "HealAssist_Scroll" .. scrollId, parent, "UIPanelScrollFrameTemplate")
  sf:SetSize(w - 24, h)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(w - 24, 10)
  sf:SetScrollChild(child)
  sf.child = child
  UI:SkinScrollFrame(sf)
  return sf, child
end

---------------------------------------------------------------------------
-- Sortable, scrollable table
---------------------------------------------------------------------------
-- cols: { { title=, w=, get=fn(row)->text, sort=fn(row)->value } }
-- opts: { rowH=, onClick=fn(row, button), onEnter=fn(row, frame), selectable=bool }
function UI:Table(parent, w, h, cols, opts)
  opts = opts or {}
  local rowH = opts.rowH or 20
  local t = CreateFrame("Frame", nil, parent, BACKDROP_T)
  t:SetSize(w, h)
  t.cols, t.data, t.view, t.offset = cols, {}, {}, 0
  t.sortCol, t.sortAsc = opts.sortCol, opts.sortAsc ~= false
  UI:Skin(t, function(self, th) flat(self, th.panel, 0.92, th.edge, 1) end)

  -- header strip
  local head = UI:TopRounded(t, "BORDER", 0, 1, 5, 24)
  local headLine = t:CreateTexture(nil, "ARTWORK"); headLine:SetPoint("TOPLEFT", 1, -25); headLine:SetPoint("TOPRIGHT", -1, -25); headLine:SetHeight(1)
  UI:Skin(t, function(self, th) head:Color(0, 0, 0, 0.3); headLine:SetColorTexture(C(th.edge)) end)

  -- widen columns so every header title (plus its sort arrow) is readable,
  -- borrowing the room from columns that have more than they need
  do
    local probe = t:CreateFontString(nil, "OVERLAY"); probe:SetFontObject(UI.fButton); probe:Hide()
    local avail, total, need = w - 16, 0, {}
    for i, c in ipairs(cols) do
      probe:SetText(c.title or "")
      need[i] = math.ceil((probe:GetStringWidth() or 0) + 8 + 15 + 4)
      if c.w < need[i] then c.w = need[i] end
      total = total + c.w
    end
    local guard = 0
    while total > avail and guard < 500 do
      guard = guard + 1
      local best, spare = nil, 0
      for i, c in ipairs(cols) do
        local sp = c.w - math.max(need[i], 30)
        if sp > spare then best, spare = i, sp end
      end
      if not best then break end
      local take = math.min(spare, total - avail, 10)
      cols[best].w = cols[best].w - take; total = total - take
    end
  end

  -- widths the user dragged before (saved per table, keyed by its column titles)
  local titles = {}
  for i, c in ipairs(cols) do titles[i] = c.title or "" end
  t.colKey = table.concat(titles, "|")
  do
    local g = S.db and S.db.global
    local saved = g and g.colW and g.colW[t.colKey]
    if saved and #saved == #cols then for i, c in ipairs(cols) do c.w = saved[i] end end
  end

  local x = 0
  t.headers = {}
  for i, c in ipairs(cols) do
    local hb = CreateFrame("Button", nil, t)
    hb:SetPoint("TOPLEFT", x + 1, -1); hb:SetSize(c.w - 2, 24)   -- 2px gap between header cells
    hb:SetClipsChildren(true)
    hb.text = UI:Text(hb, c.title, "small"); hb.text:SetFontObject(UI.fButton); hb.text:SetPoint("LEFT", 8, 0)
    hb.text:SetWordWrap(false); hb.text:SetJustifyH("LEFT")
    hb.arrow = UI:Icon(hb, "down", 9, "OVERLAY"); hb.arrow:Hide()
    -- keep the sort arrow inside its own column: right after the title if it fits,
    -- otherwise pinned to the column's right edge with the title trimmed
    function hb:PlaceArrow(show)
      local w = self:GetWidth() or c.w
      local tw = self.text:GetStringWidth() or 0
      self.text:ClearAllPoints(); self.text:SetPoint("LEFT", 8, 0)
      self.arrow:ClearAllPoints()
      if not show then self.text:SetWidth(math.max(1, w - 10)); return end
      if 8 + tw + 4 + 9 + 4 <= w then
        self.text:SetWidth(tw + 2)
        self.arrow:SetPoint("LEFT", self.text, "RIGHT", 2, 0)
      else
        self.text:SetWidth(math.max(1, w - 8 - 15))
        self.arrow:SetPoint("RIGHT", self, "RIGHT", -4, 0)
      end
    end
    hb:PlaceArrow(false)
    local hl = hb:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(WHITE)
    UI:Skin(hb, function(self, th) hl:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.08); self.arrow:SetVertexColor(C(th.gold)) end)
    hb:SetScript("OnClick", function()
      if not c.sort and not c.get then return end
      if t.sortCol == i then t.sortAsc = not t.sortAsc else t.sortCol, t.sortAsc = i, true end
      if PlaySound and SOUNDKIT and SOUNDKIT.U_CHAT_SCROLL_BUTTON then PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON) end
      t:Refresh()
    end)
    -- optional explanation when hovering the column title
    if c.tip then UI:Tip(hb, c.title ~= "" and c.title or nil, c.tip) end
    t.headers[i] = hb
    c.x = x
    x = x + c.w
  end

  local body = CreateFrame("Frame", nil, t)
  body:SetPoint("TOPLEFT", 2, -28); body:SetPoint("BOTTOMRIGHT", -12, 2)
  t.visible = math.max(1, math.floor((h - 30) / rowH))
  t.rows = {}
  for r = 1, t.visible do
    local row = CreateFrame("Button", nil, body)
    row:SetHeight(rowH)
    row:SetPoint("TOPLEFT", 0, -(r - 1) * rowH); row:SetPoint("RIGHT", body, "RIGHT")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if r % 2 == 0 then
      local stripe = row:CreateTexture(nil, "BACKGROUND"); stripe:SetAllPoints(); stripe:SetColorTexture(1, 1, 1, 0.03)
    end
    local hl = row:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(WHITE)
    row.sel = row:CreateTexture(nil, "BORDER"); row.sel:SetAllPoints(); row.sel:SetTexture(WHITE); row.sel:Hide()
    row.selBar = row:CreateTexture(nil, "ARTWORK"); row.selBar:SetPoint("TOPLEFT"); row.selBar:SetPoint("BOTTOMLEFT"); row.selBar:SetWidth(2); row.selBar:Hide()
    UI:Skin(row, function(self, th)
      hl:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.08)
      self.sel:SetVertexColor(th.gold[1], th.gold[2], th.gold[3], 0.14)
      self.selBar:SetColorTexture(C(th.gold))
    end)
    row.tint = row:CreateTexture(nil, "BACKGROUND", nil, 1); row.tint:SetAllPoints(); row.tint:Hide()
    row.cells = {}
    for i, c in ipairs(cols) do
      local fs = UI:Text(row, "", "small")
      fs:SetPoint("LEFT", c.x + 8, 0); fs:SetWidth(c.w - 10); fs:SetHeight(rowH)
      fs:SetWordWrap(false)
      if c.justify then fs:SetJustifyH(c.justify) end
      row.cells[i] = fs
    end
    row:SetScript("OnClick", function(self, button)
      if not self.item then return end
      if opts.selectable then t.selected = self.item; t:Draw() end
      if opts.onClick then opts.onClick(self.item, button, self) end
    end)
    -- hovering a cell whose text is cut off shows the whole text
    local function cellUnderCursor(self)
      local cx = GetCursorPosition() / (self:GetEffectiveScale() or 1)
      local left = self:GetLeft() or 0
      for i, c in ipairs(t.cols) do
        if cx >= left + c.x and cx < left + c.x + c.w then return i end
      end
    end
    local function cut(fs)
      if fs.IsTruncated then return fs:IsTruncated() end
      local uw = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth() or 0
      return uw > (fs:GetWidth() or 0) + 1
    end
    local function hover(self)
      local i = cellUnderCursor(self)
      if i == self.__hoverCol then return end
      self.__hoverCol = i
      local fs = i and self.cells[i]
      if fs and (fs:GetText() or "") ~= "" and cut(fs) then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine(t.cols[i].title or "", 1, 0.82, 0)
        GameTooltip:AddLine(fs:GetText(), 1, 1, 1, true)
        GameTooltip:Show()
      else
        GameTooltip:Hide()
        if self.item and opts.onEnter then opts.onEnter(self.item, self) end
      end
    end
    row:SetScript("OnEnter", function(self) self.__hoverCol = false; hover(self); self:SetScript("OnUpdate", hover) end)
    row:SetScript("OnLeave", function(self) self:SetScript("OnUpdate", nil); self.__hoverCol = nil; GameTooltip:Hide() end)
    t.rows[r] = row
  end

  -- re-place headers and cells after a column width changes
  function t:LayoutCols()
    local xx = 0
    for i, c in ipairs(self.cols) do
      c.x = xx
      local hb = self.headers[i]
      hb:ClearAllPoints(); hb:SetPoint("TOPLEFT", xx + 1, -1); hb:SetSize(c.w - 2, 24)
      hb:PlaceArrow(i == self.sortCol)
      for _, row in ipairs(self.rows) do
        local fs = row.cells[i]
        fs:ClearAllPoints(); fs:SetPoint("LEFT", xx + 8, 0); fs:SetWidth(math.max(1, c.w - 10))
      end
      xx = xx + c.w
    end
    for i, gr in ipairs(self.grips or {}) do gr:ClearAllPoints(); gr:SetPoint("TOPLEFT", self, "TOPLEFT", self.cols[i].x + self.cols[i].w - 4, -1) end
  end
  -- drag the line between two headers to resize those columns
  t.grips = {}
  for i = 1, #cols - 1 do
    local gr = CreateFrame("Frame", nil, t)
    gr:SetSize(8, 24); gr:SetFrameLevel(t:GetFrameLevel() + 5); gr:EnableMouse(true)
    local ln = gr:CreateTexture(nil, "OVERLAY"); ln:SetPoint("TOP", 0, -5); ln:SetPoint("BOTTOM", 0, 5); ln:SetWidth(1)
    ln:SetTexture(WHITE); ln:SetAlpha(0.25)
    UI:Skin(gr, function(_, th) ln:SetVertexColor(C(th.gold)) end)
    gr:SetScript("OnEnter", function(self)
      ln:SetAlpha(1); ln:SetWidth(2)
      GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Drag to resize columns", 1, 0.82, 0); GameTooltip:Show()
    end)
    gr:SetScript("OnLeave", function(self) if not self.drag then ln:SetAlpha(0.25); ln:SetWidth(1) end GameTooltip:Hide() end)
    gr:SetScript("OnMouseDown", function(self)
      GameTooltip:Hide()
      self.drag = { x = GetCursorPosition() / (self:GetEffectiveScale() or 1), a = t.cols[i].w, b = t.cols[i + 1].w }
      self:SetScript("OnUpdate", function()
        local d = self.drag; if not d then return end
        local dx = math.floor(GetCursorPosition() / (self:GetEffectiveScale() or 1) - d.x + 0.5)
        dx = math.max(28 - d.a, math.min(d.b - 28, dx))
        t.cols[i].w, t.cols[i + 1].w = d.a + dx, d.b - dx
        t:LayoutCols()
      end)
    end)
    gr:SetScript("OnMouseUp", function(self)
      self.drag = nil; self:SetScript("OnUpdate", nil); ln:SetAlpha(self:IsMouseOver() and 1 or 0.25)
      local g = S.db and S.db.global
      if g then
        g.colW = g.colW or {}
        local ws = {}; for k, c in ipairs(t.cols) do ws[k] = c.w end
        g.colW[t.colKey] = ws
      end
    end)
    t.grips[i] = gr
  end
  t:LayoutCols()

  -- thin scroll bar
  local bar = CreateFrame("Slider", nil, t)
  bar:SetPoint("TOPRIGHT", -4, -30); bar:SetPoint("BOTTOMRIGHT", -4, 4); bar:SetWidth(6)
  bar:SetOrientation("VERTICAL")
  local track = bar:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints(); track:SetTexture(MEDIA .. "UI\\pill")
  bar:SetThumbTexture(MEDIA .. "UI\\pill")
  local thumb = bar:GetThumbTexture(); if thumb then thumb:SetSize(6, 30) end
  UI:Skin(bar, function(self, th) track:SetVertexColor(C(th.line)); if thumb then thumb:SetVertexColor(C(th.gold)) end end)
  bar:SetMinMaxValues(0, 0); bar:SetValueStep(1); bar:SetValue(0)
  if bar.SetObeyStepOnDrag then bar:SetObeyStepOnDrag(true) end
  bar:SetScript("OnValueChanged", function(_, v) v = math.floor(v + 0.5); if v ~= t.offset then t.offset = v; t:Draw() end end)
  t.bar = bar
  t:EnableMouseWheel(true)
  t:SetScript("OnMouseWheel", function(_, delta)
    local maxOff = math.max(0, #t.view - t.visible)
    t.offset = math.min(maxOff, math.max(0, t.offset - delta * 3))
    bar:SetValue(t.offset)
    t:Draw()
  end)

  t.empty = UI:Text(body, opts.emptyText or "Nothing here yet.", "muted", "CENTER")
  t.empty:SetPoint("TOP", 0, -24); t.empty:SetWidth(w - 40)

  function t:SetData(data) self.data = data or {}; self:Refresh() end
  function t:Refresh()
    local view = {}
    for _, item in ipairs(self.data) do view[#view + 1] = item end
    local c = self.cols[self.sortCol or 0]
    for i, hb in ipairs(self.headers) do
      hb.arrow:SetShown(i == self.sortCol); hb:PlaceArrow(i == self.sortCol)
      if i == self.sortCol then hb.arrow:SetTexture(UI.ICON[self.sortAsc and "up" or "down"]) end
    end
    if c then
      local key = c.sort or c.get
      local asc = self.sortAsc
      local keys = {}
      for _, item in ipairs(view) do
        local ok, v = pcall(key, item)
        if not ok then v = nil end
        if type(v) == "string" then v = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower() end
        keys[item] = v
      end
      table.sort(view, function(a, b)
        local va, vb = keys[a], keys[b]
        if va == vb then return false end
        if va == nil then return false end
        if vb == nil then return true end
        if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
        if asc then return va < vb else return va > vb end
      end)
    end
    self.view = view
    local maxOff = math.max(0, #view - self.visible)
    if self.offset > maxOff then self.offset = maxOff end
    self.bar:SetMinMaxValues(0, maxOff)
    self.bar:SetValue(self.offset)
    self.bar:SetShown(maxOff > 0)
    self:Draw()
  end
  function t:Draw()
    for r, row in ipairs(self.rows) do
      local item = self.view[r + self.offset]
      row.item = item
      if item then
        for i, c in ipairs(self.cols) do
          local ok, v = true, nil
          if c.get then ok, v = pcall(c.get, item) end
          if not ok then S:Debug("table cell error: " .. tostring(v)); v = "?" end
          row.cells[i]:SetText(v ~= nil and tostring(v) or "")
        end
        local sel = self.selected == item
        row.sel:SetShown(sel); row.selBar:SetShown(sel)
        local cr, cg, cb, ca
        if opts.rowColor then local ok; ok, cr, cg, cb, ca = pcall(opts.rowColor, item); if not ok then cr = nil end end
        if cr then row.tint:SetColorTexture(cr, cg, cb, ca or 0.3); row.tint:Show() else row.tint:Hide() end
        row:Show()
      else
        row:Hide()
      end
    end
    self.empty:SetShown(#self.view == 0)
  end
  return t
end

---------------------------------------------------------------------------
-- Windows (flat dark frame, theme trim, header band, X)
-- opts: { header = band height (default 34) }
---------------------------------------------------------------------------
function UI:Window(name, title, w, h, opts)
  opts = opts or {}
  local band = opts.header or 28
  local f = CreateFrame("Frame", name, UIParent, BACKDROP_T)
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  -- soft drop shadow
  local sh = CreateFrame("Frame", nil, f)
  sh:SetPoint("TOPLEFT", -22, 22); sh:SetPoint("BOTTOMRIGHT", 22, -26); sh:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
  local st = sh:CreateTexture(nil, "BACKGROUND"); st:SetAllPoints(); st:SetTexture(UI.ART.glow); st:SetVertexColor(0, 0, 0, 0.85)
  f.shadow = sh
  -- body, faint grain, outer black hairline
  UI:DialogBackdrop(f)
  local outer = CreateFrame("Frame", nil, f)
  outer:SetPoint("TOPLEFT", -1, 1); outer:SetPoint("BOTTOMRIGHT", 1, -1)
  outer:SetFrameLevel(math.max(0, f:GetFrameLevel()))
  rounded(outer, 1, 9)
  outer:SetBackdropColor(0, 0, 0, 0); outer:SetBackdropBorderColor(0, 0, 0, 1)
  -- header band: rounded top row + gradient body
  local cap = sliceSet(f, MEDIA .. "UI\\rfill", "BACKGROUND", 3)
  for _, k in ipairs({ "L", "C", "R", "BL", "B", "BR" }) do cap[k]:Hide() end
  cap.TL:SetPoint("TOPLEFT", 2, -2); cap.TL:SetSize(6, 6)
  cap.TR:SetPoint("TOPRIGHT", -2, -2); cap.TR:SetSize(6, 6)
  cap.T:SetPoint("TOPLEFT", cap.TL, "TOPRIGHT"); cap.T:SetPoint("BOTTOMRIGHT", cap.TR, "BOTTOMLEFT")
  f.headCap = cap
  f.header = f:CreateTexture(nil, "BACKGROUND", nil, 3)
  f.header:SetPoint("TOPLEFT", 2, -8); f.header:SetPoint("TOPRIGHT", -2, -8); f.header:SetHeight(band - 6)
  f.headLine = f:CreateTexture(nil, "BORDER")
  f.headLine:SetPoint("TOPLEFT", 2, -2 - band); f.headLine:SetPoint("TOPRIGHT", -2, -2 - band); f.headLine:SetHeight(1)
  UI:Skin(f.header, function(self, th)
    UI:Gradient(self, "VERTICAL", th.head2[1], th.head2[2], th.head2[3], 1, th.head1[1], th.head1[2], th.head1[3], 1)
    for _, k in ipairs({ "TL", "T", "TR" }) do cap[k]:SetVertexColor(C(th.head1)) end
    f.headLine:SetColorTexture(C(th.edge))
  end)
  f.title = UI:Text(f, title, "large")
  f.title:SetPoint("TOPLEFT", 16, -(band / 2) + 7)
  f.title:SetShown(band <= 40)
  -- header buttons (close, and any added with f:HeaderButton) share one look
  local function headBtn(icon, iconSize)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(24, 24)
    b.icon = UI:Icon(b, icon, iconSize or 14); b.icon:SetPoint("CENTER")
    UI:Skin(b, function(self, th) self.icon:SetVertexColor(C(self.__hot and th.gold or th.muted)) end)
    b:SetScript("OnEnter", function(self)
      self.__hot = true; self.icon:SetVertexColor(C(UI:Theme().gold))
      if self.tipTitle then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:AddLine(self.tipTitle, 1, 0.82, 0); if self.tipText then GameTooltip:AddLine(self.tipText, 1, 1, 1, true) end; GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function(self) self.__hot = false; self.icon:SetVertexColor(C(UI:Theme().muted)); GameTooltip:Hide() end)
    b:HookScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", 1, -1) end)
    b:HookScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER", 0, 0) end)
    return b
  end
  local close = headBtn("close", 14)
  close:SetPoint("TOPRIGHT", -6, -((band - 24) / 2) - 2)
  close:SetScript("OnClick", function() f:Hide() end)
  f.close = close
  f.headBtns = { close }
  function f:HeaderButton(icon, tipTitle, tipText, onClick)
    local b = headBtn(icon, 14)
    b:SetPoint("RIGHT", f.headBtns[#f.headBtns], "LEFT", -2, 0)
    b.tipTitle, b.tipText = tipTitle, tipText
    b:SetScript("OnClick", function(self, btn) if onClick then onClick(self, btn) end end)
    f.headBtns[#f.headBtns + 1] = b
    return b
  end
  f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetScript("OnShow", function(self)
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
    UI:Animate(self, "window")
  end)
  if name then tinsert(UISpecialFrames, name) end
  return f
end

local confirmWin
function UI:Confirm(text, onYes, yesText)
  if not confirmWin then
    confirmWin = UI:Window("HealAssist_Confirm", "HealAssist", 380, 160)
    confirmWin.msg = UI:Text(confirmWin, "", "normal", "CENTER")
    confirmWin.msg:SetPoint("TOP", 0, -50); confirmWin.msg:SetWidth(340)
    confirmWin.yes = UI:PrimaryButton(confirmWin, "Yes", 120, 26)
    confirmWin.yes:SetPoint("BOTTOMRIGHT", confirmWin, "BOTTOM", -6, 18)
    confirmWin.no = UI:Button(confirmWin, "Cancel", 120, 26, function() confirmWin:Hide() end)
    confirmWin.no:SetPoint("BOTTOMLEFT", confirmWin, "BOTTOM", 6, 18)
    -- Enter = Yes / OK, Escape = Cancel; every other key goes on to the game
    confirmWin:EnableKeyboard(true)
    confirmWin:SetScript("OnKeyDown", function(self, key)
      local mine = key == "ENTER" or key == "NUMPADENTER" or key == "ESCAPE"
      if not (InCombatLockdown and InCombatLockdown()) and self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(not mine) end
      if key == "ENTER" or key == "NUMPADENTER" then self.yes:Click()
      elseif key == "ESCAPE" then self:Hide() end
    end)
  end
  -- a typing box would swallow Enter: let go of it so Enter answers this
  local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
  if focus and focus.ClearFocus then focus:ClearFocus() end
  confirmWin.msg:SetText(text)
  confirmWin:SetHeight(math.max(160, (confirmWin.msg:GetStringHeight() or 30) + 120))
  confirmWin.yes:SetText(yesText or "Yes")
  confirmWin.yes:SetScript("OnClick", function() confirmWin:Hide(); if onYes then onYes() end end)
  confirmWin.no:Show()
  confirmWin.yes:ClearAllPoints(); confirmWin.yes:SetPoint("BOTTOMRIGHT", confirmWin, "BOTTOM", -6, 18)
  -- open where the mouse is (Yes button right under the cursor), kept on screen
  local scale = confirmWin:GetEffectiveScale() or 1
  local cx, cy = GetCursorPosition()
  cx, cy = (cx or 0) / scale, (cy or 0) / scale
  local w, h = confirmWin:GetWidth() or 380, confirmWin:GetHeight() or 160
  local sw = (UIParent:GetWidth() or 1920) * (UIParent:GetEffectiveScale() or 1) / scale
  local sh = (UIParent:GetHeight() or 1080) * (UIParent:GetEffectiveScale() or 1) / scale
  local left = math.max(4, math.min(sw - w - 4, cx - w / 2 + 64))     -- Yes sits left of centre
  local bottom = math.max(4, math.min(sh - h - 4, cy - 31))
  confirmWin:ClearAllPoints(); confirmWin:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
  confirmWin:Show(); confirmWin:Raise()
end
-- a message with just an OK button
function UI:Alert(text)
  UI:Confirm(text, nil, "OK")
  confirmWin.no:Hide()
  confirmWin.yes:ClearAllPoints(); confirmWin.yes:SetPoint("BOTTOM", confirmWin, "BOTTOM", 0, 18)
end

local promptWin
function UI:Prompt(text, default, onOk)
  if not promptWin then
    promptWin = UI:Window("HealAssist_Prompt", "HealAssist", 400, 170)
    promptWin.msg = UI:Text(promptWin, "", "normal", "CENTER")
    promptWin.msg:SetPoint("TOP", 0, -48); promptWin.msg:SetWidth(360)
    promptWin.edit = UI:Edit(promptWin, 340, 26)
    promptWin.ok = UI:PrimaryButton(promptWin, "Okay", 120, 26)
    promptWin.ok:SetPoint("BOTTOMRIGHT", promptWin, "BOTTOM", -6, 18)
    promptWin.no = UI:Button(promptWin, "Cancel", 120, 26, function() promptWin:Hide() end)
    promptWin.no:SetPoint("BOTTOMLEFT", promptWin, "BOTTOM", 6, 18)
  end
  promptWin.msg:SetText(text)
  local mh = promptWin.msg:GetStringHeight() or 16
  promptWin:SetHeight(math.max(170, mh + 140))
  promptWin.edit:ClearAllPoints(); promptWin.edit:SetPoint("TOP", promptWin.msg, "BOTTOM", 0, -14)
  promptWin.edit:SetText(default or "")
  local function ok() promptWin:Hide(); onOk(S.Trim(promptWin.edit:GetText())) end
  promptWin.ok:SetScript("OnClick", ok)
  promptWin.edit:SetScript("OnEnterPressed", ok)
  promptWin:Show(); promptWin:Raise()
  promptWin.edit:SetFocus(); promptWin.edit:HighlightText()
end

local copyWin
function UI:CopyBox(title, text, onImport)
  if not copyWin then
    copyWin = UI:Window("HealAssist_Copy", "Export", 640, 440)
    local inset = UI:Panel(copyWin, nil, nil, { 0, 0, 0, 0.8 })
    inset:SetPoint("TOPLEFT", 16, -48); inset:SetPoint("BOTTOMRIGHT", -16, 52)
    local sf = CreateFrame("ScrollFrame", "HealAssist_CopyScroll", inset, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -8); sf:SetPoint("BOTTOMRIGHT", -28, 8)
    UI:SkinScrollFrame(sf)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetFontObject(UI.fSmall); eb:SetWidth(560); eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() copyWin:Hide() end)
    sf:SetScrollChild(eb)
    copyWin.edit = eb
    copyWin.hint = UI:Text(copyWin, "", "muted")
    copyWin.hint:SetPoint("BOTTOMLEFT", 20, 24)
    copyWin.import = UI:PrimaryButton(copyWin, "Import", 120, 26)
    copyWin.import:SetPoint("BOTTOMRIGHT", -20, 16)
  end
  copyWin.title:SetText(title)
  copyWin.edit:SetText(text or "")
  copyWin.import:SetShown(onImport ~= nil)
  copyWin.import:SetScript("OnClick", function() if onImport then onImport(copyWin.edit:GetText()); copyWin:Hide() end end)
  copyWin.hint:SetText(onImport and "Paste data above, then press Import." or "Ctrl+A then Ctrl+C to copy. Paste into a spreadsheet.")
  copyWin:Show(); copyWin:Raise()
  copyWin.edit:SetFocus(); if not onImport then copyWin.edit:HighlightText() end
end

---------------------------------------------------------------------------
-- Sub-tabs: text tabs with a gold underline on the active one
---------------------------------------------------------------------------
function UI:SubTabs(parent, names, onSelect)
  local strip = CreateFrame("Frame", nil, parent)
  strip:SetHeight(26)
  strip.buttons = {}
  local line = strip:CreateTexture(nil, "BACKGROUND"); line:SetHeight(1)
  line:SetPoint("BOTTOMLEFT", 0, -2); line:SetPoint("BOTTOMRIGHT", 0, -2)
  local x = 0
  for i, n in ipairs(names) do
    local b = CreateFrame("Button", nil, strip)
    b.label = UI:Text(b, n, "normal", "CENTER"); b.label:SetFontObject(UI.fButton); b.label:SetPoint("CENTER", 0, 1)
    local width = math.max(60, (b.label:GetStringWidth() or (#n * 7)) + 28)
    b:SetSize(width, 26)
    b:SetPoint("BOTTOMLEFT", x, 0)
    b.bar = b:CreateTexture(nil, "ARTWORK"); b.bar:SetHeight(2); b.bar:SetPoint("BOTTOMLEFT", 8, -2); b.bar:SetPoint("BOTTOMRIGHT", -8, -2)
    b:SetScript("OnEnter", function(self) self.__hot = true; strip:Paint() end)
    b:SetScript("OnLeave", function(self) self.__hot = false; strip:Paint() end)
    b:SetScript("OnClick", function()
      if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
      strip:Select(i)
    end)
    x = x + width + 2
    strip.buttons[i] = b
  end
  function strip:Paint()
    local th = UI:Theme()
    line:SetColorTexture(C(th.line))
    for j, btn in ipairs(self.buttons) do
      local on = j == self.current
      btn.label:SetTextColor(C((on or btn.__hot) and (on and th.gold or th.text) or th.muted))
      btn.bar:SetColorTexture(C(th.gold)); btn.bar:SetShown(on)
    end
  end
  function strip:Select(i)
    self.current = i
    self:Paint()
    onSelect(i)
  end
  UI:Skin(strip, function(self) self:Paint() end)
  return strip
end

---------------------------------------------------------------------------
-- Status bar
---------------------------------------------------------------------------
function UI:Bar(parent, w, h)
  local f = CreateFrame("Frame", nil, parent, BACKDROP_T)
  f:SetSize(w, h)
  UI:Skin(f, function(self, th) flat(self, th.field, 1, th.line, 1) end)
  f.fill = f:CreateTexture(nil, "ARTWORK")
  f.fill:SetTexture(WHITE)
  f.fill:SetPoint("TOPLEFT", 1, -1); f.fill:SetPoint("BOTTOMLEFT", 1, 1)
  f.fill:SetVertexColor(UI:Accent())
  f.text = UI:Text(f, "", "small"); f.text:SetPoint("CENTER")
  function f:SetValue(v, max, r, g, b)
    local pct = (max and max > 0) and math.min(1, v / max) or 0
    self.fill:SetWidth(math.max(1, (w - 2) * pct))
    if r then self.fill:SetVertexColor(r, g, b) else self.fill:SetVertexColor(UI:Accent()) end
  end
  return f
end
