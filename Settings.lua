local ADDON, ns = ...

local refreshers = {}
-- Re-reads every control from the saved settings. An error in one control is reported but does not stop the rest.
local function Refresh()
  for _, f in ipairs(refreshers) do
    local ok, err = pcall(f)
    if not ok then geterrorhandler()(err) end   -- report it, but keep refreshing the rest
  end
end
ns.RefreshSettings = Refresh

local BORDER = { 0.6, 0.5, 0.3, 1 }
local RULE = { 0.55, 0.42, 0.24, 0.8 }

-- Widgets ----------------------------------------------------------------------
local function Label(parent, text, x, y, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", x, y); fs:SetText(text); fs:SetJustifyH("LEFT")
  return fs
end

-- A section heading with a thin rule under it.
local function Header(parent, text, x, y, w)
  Label(parent, text, x, y, "GameFontNormalLarge")
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", x, y - 22); line:SetSize(w, 1); line:SetColorTexture(unpack(RULE))
end

-- A checkbox with a label. get and set read and write the setting; Dim(true) greys it out.
local function Check(parent, text, x, y, get, set)
  local b = CreateFrame("CheckButton", nil, parent)
  b:SetSize(18, 18); b:SetPoint("TOPLEFT", x + 2, y - 2)
  local border = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1); border:SetColorTexture(unpack(BORDER))
  local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.08, 0.08, 1)
  b:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  b:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", b, "RIGHT", 6, 0); fs:SetText(text)
  b.label = fs
  b:SetHitRectInsets(0, -(fs:GetStringWidth() + 6), 0, 0)   -- hovering or clicking the label counts too
  b:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); Refresh() end)
  refreshers[#refreshers + 1] = function() b:SetChecked(get()) end
  b.Dim = function(off)   -- grey out and block clicks (used for options that need something else enabled)
    b:SetEnabled(not off)
    local v = off and 0.45 or 1
    fs:SetTextColor(v, v, v)
  end
  return b
end

-- A standard button.
local function Button(parent, text, x, y, w, fn)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(w, 24); btn:SetPoint("TOPLEFT", x, y); btn:SetText(text)
  btn:SetScript("OnClick", fn)
  return btn
end

-- Plain hover tooltip for a control: a white title and a wrapped grey explanation.
local function HoverTip(w, title, body, anchor)
  w:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  w:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Shared with the setup tour.
ns.UI = { Label = Label, Header = Header, Check = Check, Button = Button, Tip = HoverTip, BORDER = BORDER, RULE = RULE }

-- Slider with optional title above it. When `editable`, the value sits in a box: click the box,
-- type a number and press Enter. `scale` is 100 for percent sliders (typed 55 = 0.55).
-- `maxFn` lets the slider's upper bound follow something dynamic (e.g. the screen width).
-- The idle value is a plain FontString (reliable to render); an EditBox only appears while typing.
local function Slider(parent, text, x, y, width, minv, maxv, step, get, set, fmt, editable, scale, maxFn, default)
  scale = scale or 1
  local title = text and Label(parent, text, x, y, "GameFontNormal")
  local s = CreateFrame("Slider", nil, parent)
  s:SetOrientation("HORIZONTAL"); s:SetSize(width, 14)
  s:SetPoint("TOPLEFT", x, text and (y - 20) or y)
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4); track:SetColorTexture(0.25, 0.25, 0.25, 1)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  s:GetThumbTexture():SetSize(14, 22)
  s:SetMinMaxValues(minv, maxFn and maxFn() or maxv); s:SetValueStep(step); s:SetObeyStepOnDrag(true)

  local val, box, edit, setBorder
  if editable then
    box = CreateFrame("Button", nil, parent)
    box:SetSize(50, 20); box:SetPoint("LEFT", s, "RIGHT", 8, 0)
    local border = box:CreateTexture(nil, "BACKGROUND", nil, -1)
    border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
    local fill = box:CreateTexture(nil, "BACKGROUND"); fill:SetAllPoints(); fill:SetColorTexture(0.08, 0.08, 0.08, 1)
    setBorder = function(c) border:SetColorTexture(c[1], c[2], c[3], c[4]) end
    setBorder(BORDER)
    val = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("CENTER")

    edit = CreateFrame("EditBox", nil, box)
    edit:SetAllPoints(box); edit:SetAutoFocus(false); edit:SetFontObject("GameFontHighlightSmall")
    edit:SetJustifyH("CENTER"); edit:SetMaxLetters(8); edit:Hide()
    local ef = edit:CreateTexture(nil, "BACKGROUND"); ef:SetAllPoints(); ef:SetColorTexture(0.12, 0.12, 0.12, 1)

    box:SetScript("OnEnter", function(self)
      setBorder({ 1, 0.82, 0, 1 })
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Click To Type A Value", 1, 1, 1)
      if default ~= nil then GameTooltip:AddLine("Default: " .. fmt(default), 0.7, 0.7, 0.7) end
      GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function()
      if not edit:IsShown() then setBorder(BORDER) end
      GameTooltip:Hide()
    end)
  else
    val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("LEFT", s, "RIGHT", 8, 0)
  end

  local function show() val:SetText(fmt(get())) end
  local refreshing = false
  s:SetScript("OnValueChanged", function(_, v)
    val:SetText(fmt(v))
    if refreshing then return end
    set(v)
  end)

  if editable then
    box:SetScript("OnClick", function()
      val:Hide()
      edit:SetText(format("%d", scale == 100 and (get() * 100 + 0.5) or get()))
      edit:Show(); edit:SetFocus(); edit:HighlightText()
      setBorder({ 1, 0.82, 0, 1 })
    end)
    edit:SetScript("OnEnterPressed", function(self)
      local n = tonumber((self:GetText() or ""):match("[%d%.]+"))
      if n then
        local lo, hi = s:GetMinMaxValues()
        n = n / scale
        n = math.max(lo, math.min(hi, floor(n / step + 0.5) * step))   -- clamp, then snap to step
        s:SetValue(n)                                                   -- fires OnValueChanged -> set()
      end
      self:ClearFocus()
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", function(self)
      self:Hide(); val:Show(); show(); setBorder(BORDER)
    end)
  end
  show()
  refreshers[#refreshers + 1] = function()
    refreshing = true
    if maxFn then s:SetMinMaxValues(minv, maxFn()) end
    s:SetValue(get()); show()
    refreshing = false
  end
  s.Dim = function(off)   -- grey out and block input
    local a = off and 0.4 or 1
    s:SetAlpha(a); s:EnableMouse(not off)
    if title then title:SetAlpha(a) end
    if box then box:SetAlpha(a); box:EnableMouse(not off) else val:SetAlpha(a) end
  end
  return s
end

-- Value formatters for sliders: a whole number, pixels and a percent.
local function Plain(v) return format("%d", v) end
local function Px(v) return format("%.1f px", v) end
local function Pct(v) return format("%d%%", v * 100 + 0.5) end

-- What each color setting colors, shown when you hover its swatch.
local COLOR_TIPS = {
  bgSolid = "The flat plate behind the bar. Used when the background is Solid.",
  bgCenter = "The color in the middle of the background. Used when the background is Gradient.",
  bgEdge = "The color at the left and right ends of the background. Used when the background is Gradient.",
  textColor = "The color of the number labels and other text on the bar.",
  cardinalColor = "The color of the E, S and W letters.",
  northColor = "The color of the N letter.",
  tickColor = "The color of the tick marks.",
  markerColor = "The color of the center marker.",
  degreeColor = "The color of the degree readout.",
  xpColor = "The color of the XP fill.",
  edgeColor = "The color of the thin lines along the top and bottom edges of the bar.",
}
-- Color swatch + label + opacity slider on one row.
local function ColorRow(parent, text, key, x, y, noAlpha)
  local sw = CreateFrame("Button", nil, parent)
  sw:SetSize(18, 18); sw:SetPoint("TOPLEFT", x + 2, y - 2)   -- same size and inset as the checkboxes
  local border = sw:CreateTexture(nil, "BACKGROUND"); border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetColorTexture(unpack(BORDER))
  local tex = sw:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints()
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  fs:SetPoint("LEFT", sw, "RIGHT", 8, 0); fs:SetWidth(108); fs:SetJustifyH("LEFT"); fs:SetText(text)
  if COLOR_TIPS[key] then HoverTip(sw, text, COLOR_TIPS[key] .. " Click to pick a color; the slider sets its opacity.") end
  sw:SetScript("OnClick", function()
    local c = ns.db[key]
    local prev = { c[1], c[2], c[3] }
    -- The marker menu sits in FULLSCREEN_DIALOG; lift the picker above it so it can be clicked.
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG"); ColorPickerFrame:SetToplevel(true); ColorPickerFrame:Raise()
    ColorPickerFrame:SetupColorPickerAndShow({
      r = c[1], g = c[2], b = c[3], hasOpacity = false,
      swatchFunc = function() c[1], c[2], c[3] = ColorPickerFrame:GetColorRGB(); Refresh(); ns.Apply(); if ns.TipColorsChanged then ns.TipColorsChanged() end end,
      cancelFunc = function() c[1], c[2], c[3] = prev[1], prev[2], prev[3]; Refresh(); ns.Apply(); if ns.TipColorsChanged then ns.TipColorsChanged() end end,
    })
  end)
  refreshers[#refreshers + 1] = function() local c = ns.db[key]; tex:SetColorTexture(c[1], c[2], c[3], 1) end
  local op = noAlpha and { Dim = function() end } or Slider(parent, nil, x + 144, y - 4, 44, 0, 1, 0.05,
    function() return ns.db[key][4] end,
    function(v) ns.db[key][4] = v; ns.Apply() end, Pct, false)
  if not noAlpha and COLOR_TIPS[key] then HoverTip(op, text .. " Opacity", "How solid this color is. 100% is fully opaque, 0% hides it.") end
  sw.Dim = function(off)   -- locked while Daylight controls the colors
    sw:SetEnabled(not off); sw:SetAlpha(off and 0.4 or 1)
    local v = off and 0.45 or 1
    fs:SetTextColor(v, v, v)
    op.Dim(off)
  end
  return sw
end

-- Font dropdown -----------------------------------------------------------------
-- WoW cannot enumerate font files, so the list is the stock fonts plus whatever other
-- addons registered with LibSharedMedia. Each entry previews in its own typeface.
local fontTest
-- Every font the game offers, for the font picker.
local function FontList()
  local list, seen = {}, {}
  fontTest = fontTest or UIParent:CreateFontString(nil, "OVERLAY")
  local function add(name, path)
    if not name or not path or path == "" then return end
    local key = path:lower()
    if seen[key] then return end
    local ok = pcall(function() return fontTest:SetFont(path, 12, "") end)
    if not ok or fontTest:SetFont(path, 12, "") == false then return end   -- skip unusable files
    seen[key] = true
    list[#list + 1] = { name = name, path = path }
  end
  add("Default (Game Font)", STANDARD_TEXT_FONT)
  add("Friz Quadrata", "Fonts\\FRIZQT__.TTF")
  add("Arial Narrow", "Fonts\\ARIALN.TTF")
  add("Morpheus", "Fonts\\MORPHEUS.ttf")
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM then
    for _, n in ipairs(LSM:List("font")) do add(n, LSM:Fetch("font", n)) end
  end
  return list
end

-- A font picker with a scrolling list that previews each font.
local function FontDropdown(parent, x, y, width)
  Label(parent, "Font", x, y, "GameFontNormal")
  local btn = CreateFrame("Button", nil, parent)
  HoverTip(btn, "Font", "The font for the text on the bar and in the XP tooltip. The list holds the game's own fonts plus any that other addons register with LibSharedMedia.")
  btn:SetSize(width, 24); btn:SetPoint("TOPLEFT", x, y - 20)
  local border = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
  border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1); border:SetColorTexture(unpack(BORDER))
  local bg = btn:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.08, 0.08, 1)
  btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  local arrow = btn:CreateTexture(nil, "ARTWORK")
  arrow:SetSize(18, 18); arrow:SetPoint("RIGHT", -3, 0)
  arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", 8, 0); text:SetPoint("RIGHT", arrow, "LEFT", -2, 0); text:SetJustifyH("LEFT")

  -- Popup list: scrollable, lives above the settings window, closes on outside click / Esc.
  local ROW = 22
  local popup = CreateFrame("Frame", "CHUDFontPopup", UIParent)
  popup:SetSize(width, 300); popup:SetFrameStrata("FULLSCREEN_DIALOG"); popup:SetClampedToScreen(true)
  popup:Hide()
  local pb = popup:CreateTexture(nil, "BACKGROUND", nil, -1)
  pb:SetPoint("TOPLEFT", -1, 1); pb:SetPoint("BOTTOMRIGHT", 1, -1); pb:SetColorTexture(unpack(BORDER))
  local pg = popup:CreateTexture(nil, "BACKGROUND"); pg:SetAllPoints(); pg:SetColorTexture(0.06, 0.06, 0.07, 0.98)
  tinsert(UISpecialFrames, "CHUDFontPopup")
  local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(width - 32, 10); scroll:SetScrollChild(child)

  local catcher = CreateFrame("Frame", nil, UIParent)
  catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("FULLSCREEN"); catcher:EnableMouse(true); catcher:Hide()
  catcher:SetScript("OnMouseDown", function() popup:Hide() end)
  popup:SetScript("OnShow", function() catcher:Show() end)
  popup:SetScript("OnHide", function() catcher:Hide() end)

  local rows = {}
  local function Populate()
    local list = FontList()
    child:SetHeight(math.max(#list * ROW, 10))
    for i, f in ipairs(list) do
      local r = rows[i]
      if not r then
        r = CreateFrame("Button", nil, child)
        r:SetSize(width - 32, ROW); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        r:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetColorTexture(1, 0.82, 0, 0.15)
        -- Sample of what the compass draws (a letter, digits, degree sign) in the row's own font,
        -- so a font missing a glyph is obvious before you pick it.
        r.sample = r:CreateFontString(nil, "OVERLAY")
        r.sample:SetPoint("RIGHT", -4, 0); r.sample:SetJustifyH("RIGHT"); r.sample:SetWidth(46)
        r.fs = r:CreateFontString(nil, "OVERLAY")
        r.fs:SetPoint("LEFT", 6, 0); r.fs:SetPoint("RIGHT", r.sample, "LEFT", -4, 0); r.fs:SetJustifyH("LEFT")
        r:SetScript("OnClick", function(self)
          ns.db.fontName, ns.db.fontPath = self.name, self.path
          ns.Apply(); Refresh(); popup:Hide()
        end)
        rows[i] = r
      end
      r.name, r.path = f.name, f.path
      if r.fs:SetFont(f.path, 13, "") == false then r.fs:SetFont(STANDARD_TEXT_FONT, 13, "") end
      if r.sample:SetFont(f.path, 13, "") == false then r.sample:SetFont(STANDARD_TEXT_FONT, 13, "") end
      r.fs:SetText(f.name); r.fs:SetTextColor(1, 1, 1)
      r.sample:SetText("N 90\194\176"); r.sample:SetTextColor(0.85, 0.85, 0.85)
      r.sel:SetShown(f.name == ns.db.fontName)
      r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    popup:SetHeight(math.min(#list * ROW + 8, 300))
  end

  btn:SetScript("OnClick", function()
    if popup:IsShown() then popup:Hide() return end
    Populate()
    popup:ClearAllPoints(); popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    scroll:SetVerticalScroll(0)
    popup:Show()
  end)
  refreshers[#refreshers + 1] = function()
    local path = (ns.db.fontPath ~= "" and ns.db.fontPath) or STANDARD_TEXT_FONT
    if text:SetFont(path, 12, "") == false then text:SetFont(STANDARD_TEXT_FONT, 12, "") end
    text:SetText(ns.db.fontName)
  end
  return btn, popup
end

-- Modal dialog (used for naming a theme and confirming a delete) ------------------------
local dialog
-- The shared popup used for naming and confirming (created on first use).
local function GetDialog()
  if dialog then return dialog end
  local f = CreateFrame("Frame", "CHUDDialog", UIParent)
  f:SetSize(320, 140); f:SetPoint("CENTER", 0, 80)
  f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:EnableMouse(true); f:Hide()
  local b = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  b:SetPoint("TOPLEFT", -1, 1); b:SetPoint("BOTTOMRIGHT", 1, -1); b:SetColorTexture(unpack(BORDER))
  local g = f:CreateTexture(nil, "BACKGROUND"); g:SetAllPoints(); g:SetColorTexture(0.06, 0.06, 0.07, 0.98)
  tinsert(UISpecialFrames, "CHUDDialog")

  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.text:SetPoint("TOP", 0, -14); f.text:SetWidth(290)

  local e = CreateFrame("EditBox", nil, f)
  e:SetSize(280, 22); e:SetPoint("TOP", f.text, "BOTTOM", 0, -10)
  e:SetAutoFocus(false); e:SetFontObject("GameFontHighlight"); e:SetMaxLetters(24); e:SetTextInsets(6, 6, 0, 0)
  local eb = e:CreateTexture(nil, "BACKGROUND", nil, -1)
  eb:SetPoint("TOPLEFT", -1, 1); eb:SetPoint("BOTTOMRIGHT", 1, -1); eb:SetColorTexture(unpack(BORDER))
  local ef = e:CreateTexture(nil, "BACKGROUND"); ef:SetAllPoints(); ef:SetColorTexture(0.08, 0.08, 0.08, 1)
  f.edit = e

  f.err = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.err:SetPoint("TOP", e, "BOTTOM", 0, -6); f.err:SetWidth(290); f.err:SetTextColor(1, 0.35, 0.3)

  local function accept()
    local msg = f.onYes and f.onYes(e:GetText() or "")
    if msg then f.err:SetText(msg) else f:Hide() end
  end
  f.yes = Button(f, "OK", 0, 0, 100, accept)
  f.yes:ClearAllPoints(); f.yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 14)
  f.no = Button(f, "Cancel", 0, 0, 100, function() f:Hide() end)
  f.no:ClearAllPoints(); f.no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 14)
  e:SetScript("OnEnterPressed", accept)
  e:SetScript("OnEscapePressed", function() f:Hide() end)

  -- Full-screen click blocker so the dialog is modal.
  local c = CreateFrame("Frame", nil, UIParent)
  c:SetAllPoints(UIParent); c:SetFrameStrata("FULLSCREEN"); c:EnableMouse(true); c:Hide()
  f:SetScript("OnShow", function() c:Show() end)
  f:SetScript("OnHide", function() c:Hide() end)
  dialog = f
  return f
end

-- opts: text, edit (show a text box), default, yes (button label), onYes(text) -> error string or nil
local function ShowDialog(opts)
  local f = GetDialog()
  f.text:SetText(opts.text)
  f.onYes = opts.onYes
  f.pendingOverwrite = nil
  f.err:SetText("")
  f.edit:SetMaxLetters(opts.maxLetters or 24)   -- set before the text: theme codes are long
  f.yes:SetText(opts.yes or "OK")
  local h = 14 + f.text:GetStringHeight() + 10 + 16 + 24 + 14
  if opts.edit then
    f.edit:Show(); f.edit:SetText(opts.default or ""); h = h + 22 + 6 + 14
  else
    f.edit:Hide()
  end
  f:SetHeight(h)
  f:Show()
  if opts.edit then f.edit:SetFocus(); f.edit:HighlightText() end
end

-- Generic scrolling dropdown. getItems() -> { {text, value, selected, header}, ... }
local function ListDropdown(parent, x, y, width, getLabel, getItems, onPick, popupName, popupWidth)
  local pw = popupWidth or width   -- the list can be wider than the button so long names stay on one line
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(width, 24); btn:SetPoint("TOPLEFT", x, y)
  local border = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
  border:SetPoint("TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", 1, -1); border:SetColorTexture(unpack(BORDER))
  local bg = btn:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.08, 0.08, 0.08, 1)
  btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  local arrow = btn:CreateTexture(nil, "ARTWORK")
  arrow:SetSize(18, 18); arrow:SetPoint("RIGHT", -3, 0)
  arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", 8, 0); text:SetPoint("RIGHT", arrow, "LEFT", -2, 0); text:SetJustifyH("LEFT"); text:SetWordWrap(false)

  local ROW = 22
  local popup = CreateFrame("Frame", popupName, UIParent)
  popup:SetSize(pw, 200); popup:SetFrameStrata("FULLSCREEN_DIALOG"); popup:SetClampedToScreen(true); popup:Hide()
  local pb = popup:CreateTexture(nil, "BACKGROUND", nil, -1)
  pb:SetPoint("TOPLEFT", -1, 1); pb:SetPoint("BOTTOMRIGHT", 1, -1); pb:SetColorTexture(unpack(BORDER))
  local pg = popup:CreateTexture(nil, "BACKGROUND"); pg:SetAllPoints(); pg:SetColorTexture(0.06, 0.06, 0.07, 0.98)
  tinsert(UISpecialFrames, popupName)
  local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4); scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(pw - 32, 10); scroll:SetScrollChild(child)
  local catcher = CreateFrame("Frame", nil, UIParent)
  catcher:SetAllPoints(UIParent); catcher:SetFrameStrata("FULLSCREEN"); catcher:EnableMouse(true); catcher:Hide()
  catcher:SetScript("OnMouseDown", function() popup:Hide() end)
  popup:SetScript("OnShow", function() catcher:Show() end)
  popup:SetScript("OnHide", function() catcher:Hide() end)

  local rows = {}
  local function Populate()
    local items = getItems()
    child:SetHeight(math.max(#items * ROW, 10))
    for i, it in ipairs(items) do
      local r = rows[i]
      if not r then
        r = CreateFrame("Button", nil, child)
        r:SetSize(pw - 32, ROW); r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        r:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        r.sel = r:CreateTexture(nil, "BACKGROUND"); r.sel:SetAllPoints(); r.sel:SetColorTexture(1, 0.82, 0, 0.15)
        r.fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.fs:SetPoint("LEFT", 6, 0); r.fs:SetPoint("RIGHT", -4, 0); r.fs:SetJustifyH("LEFT"); r.fs:SetWordWrap(false)
        r:SetScript("OnClick", function(self)
          if self.value ~= nil then onPick(self.value); popup:Hide() end
        end)
        rows[i] = r
      end
      r.value = it.value
      r.fs:SetText(it.text)
      if it.header then
        r.fs:SetFontObject("GameFontNormalSmall"); r.fs:SetTextColor(0.7, 0.6, 0.3)
        r:EnableMouse(false); r.sel:Hide()
      else
        r.fs:SetFontObject("GameFontHighlight")
        r:EnableMouse(true); r.sel:SetShown(it.selected and true or false)
      end
      r:Show()
    end
    for i = #items + 1, #rows do rows[i]:Hide() end
    popup:SetHeight(math.min(#items * ROW + 8, 300))
  end

  btn:SetScript("OnClick", function()
    if popup:IsShown() then popup:Hide() return end
    Populate()
    popup:ClearAllPoints(); popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    scroll:SetVerticalScroll(0)
    popup:Show()
  end)
  local function update() text:SetText(getLabel()) end
  update()
  return btn, popup, update
end

-- Panel ----------------------------------------------------------------------------
-- Marker menu ----------------------------------------------------------------------------
-- Opens when the compass is right-clicked: checkboxes for what to point at, plus icon size and range.
local markerMenu
-- Builds the right-click marker menu (quick toggles, data sources) and the options panel beside it.
local function BuildMarkerMenu()
  local f = CreateFrame("Frame", "CHUDMarkerMenu", UIParent)
  f:SetSize(500, 670); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
  f:EnableMouse(true); f:SetClampedToScreen(true); f:Hide()
  -- Drag the menu by any empty part of it. Once moved it stays where you put it until you reload.
  f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self.userMoved = true end)
  local b = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  b:SetPoint("TOPLEFT", -1, 1); b:SetPoint("BOTTOMRIGHT", 1, -1); b:SetColorTexture(unpack(BORDER))
  local g = f:CreateTexture(nil, "BACKGROUND"); g:SetAllPoints(); g:SetColorTexture(0.06, 0.06, 0.07, 0.97)
  tinsert(UISpecialFrames, "CHUDMarkerMenu")   -- Esc closes it

  -- Full-screen catcher behind the menu: a click anywhere else closes it.
  local c = CreateFrame("Button", nil, UIParent)
  c:SetAllPoints(UIParent); c:SetFrameStrata("FULLSCREEN"); c:Hide()
  c:SetScript("OnClick", function() f:Hide() end)
  f:SetScript("OnShow", function() c:Show(); Refresh() end)
  f:SetScript("OnHide", function() c:Hide() end)
  -- Everything below the quick toggles lives on `adv`, shown by the Advanced button.
  local adv = CreateFrame("Frame", nil, f)
  -- A second panel to the left of the menu, with two columns of its own.
  adv:SetPoint("TOPRIGHT", f, "TOPLEFT", -6, 0); adv:SetSize(500, 670)
  adv:EnableMouse(true); adv:RegisterForDrag("LeftButton")   -- empty parts of the panel catch clicks and drag the whole menu
  adv:SetScript("OnDragStart", function() f:StartMoving() end)
  adv:SetScript("OnDragStop", function() f:StopMovingOrSizing(); f.userMoved = true end)
  do
    local ab = adv:CreateTexture(nil, "BACKGROUND", nil, -1)
    ab:SetPoint("TOPLEFT", -1, 1); ab:SetPoint("BOTTOMRIGHT", 1, -1); ab:SetColorTexture(unpack(BORDER))
    local ag = adv:CreateTexture(nil, "BACKGROUND"); ag:SetAllPoints(); ag:SetColorTexture(0.06, 0.06, 0.07, 0.97)
    local at = adv:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); at:SetPoint("TOPLEFT", 14, -12); at:SetText("ADVANCED")
    local ar = adv:CreateTexture(nil, "ARTWORK")
    ar:SetPoint("TOPLEFT", 14, -36); ar:SetSize(472, 1); ar:SetColorTexture(unpack(RULE))
  end

  -- Hover explanation for an option: what data it uses and when it shows up.
  -- `extra` (optional) is called when the tooltip opens and may return one more paragraph, shown in orange.
  local function Tip(w, title, text, extra)
    w:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(f, "ANCHOR_NONE")
      GameTooltip:SetPoint("TOPLEFT", f, "TOPRIGHT", 6, 0)
      GameTooltip:AddLine(title, 1, 0.82, 0)
      GameTooltip:AddLine(text, 1, 1, 1, true)
      local more = extra and extra()
      if more then GameTooltip:AddLine(" "); GameTooltip:AddLine(more, 1, 0.55, 0.3, true) end
      GameTooltip:Show()
    end)
    w:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  local function opt(key) return function() return ns.db[key] end, function(v) ns.db[key] = v; ns.MarkersChanged() end end
  -- The everyday switches sit in a grid at the top: key -> { column, row, short label }.
  local QUICK = {
    mk_tracked = { 14, -76, "Tracked Quest" }, mk_objectives = { 14, -99, "Objectives" }, mk_givers = { 14, -122, "Quest Givers" },
    mk_party = { 176, -76, "Party" }, mk_corpse = { 176, -99, "Corpse" },
    mk_rares = { 14, -176, "Rare NPCs" }, mk_treasures = { 176, -176, "Map Treasures" },
    mk_herbs = { 14, -232, "Herbs" }, mk_ore = { 176, -232, "Ore" }, mk_containers = { 338, -232, "Chests" },
    mk_gnextOnly = { 176, -255, "Only Next Node" },   -- the Next Node check itself sits at the left of this row
  }
  -- When a marker kind has no data behind it, say so: the toggle's label turns orange and its tooltip explains what is missing.
  local WARN_KIND = { mk_herbs = "herb", mk_ore = "ore", mk_containers = "box", mk_rares = "rare" }
  local function DataWarn(kind)
    if kind == "rare" then
      local _, readable = ns.RareStatus()
      if not readable then return "CHUD's rare NPC data did not load. Reinstall CHUD." end
      return nil
    end
    local s = ns.GatherSources()
    local n = s.own and s.own.counts and s.own.counts[kind] or 0
    if n > 0 then return nil end
    if not (s.gl or s.gm2) then
      return "No gathering data found. Without GatherLite (recommended) or GatherMate2 with GatherMate2_Data, nothing will show here except spots you gather yourself. Install one, then press Refresh Gathering Data in this menu."
    end
    if kind == "box" and not s.gl then
      return "GatherMate2 has no chest data, so nothing will show here except chests you open yourself. Install GatherLite to get chests."
    end
    return "CHUD's imported copy has no entries for this yet, so nothing will show except spots you gather yourself. Press Refresh Gathering Data in this menu. GatherLite only supplies the kinds whose tracking is switched on in GatherLite."
  end
  local function C(text, key, y, tip, extra)
    local g2, s2 = opt(key)
    local kind = WARN_KIND[key]
    if kind then
      local inner = extra
      extra = function() return DataWarn(kind) or (inner and inner()) end
    end
    local q = QUICK[key]
    local b
    if q then
      b = Check(f, q[3], q[1], q[2], g2, s2)
      b:SetHitRectInsets(0, -110, 0, 0)
    else
      b = Check(adv, text, 14, y, g2, s2)
      b:SetHitRectInsets(0, -190, 0, 0)
    end
    Tip(b, text, tip, extra)
    if kind then
      refreshers[#refreshers + 1] = function()
        if DataWarn(kind) then b.label:SetTextColor(1, 0.7, 0.3) else b.label:SetTextColor(1, 1, 1) end
      end
    end
    return b
  end

  -- Questie's own settings can hide a kind of icon before CHUD ever sees it. CHUD only reads Questie and never
  -- changes its settings, so the matching option greys out and its tooltip says which Questie option to turn on.
  local function QuestieHides(kind)
    local Qe = _G.Questie
    if not (Qe and ns.db.mk_questie ~= false and type(Qe.db) == "table" and type(Qe.db.profile) == "table") then return end
    local p = Qe.db.profile
    local where = "In Questie's options (/questie), Icons tab, tick "
    if p.enabled == false then return "Questie's icons are turned off. " .. where .. "Enable Icons." end
    if p.enableMapIcons == false and p.enableMiniMapIcons == false then
      return "Questie's map and minimap icons are both turned off. " .. where .. "Enable Map Icons or Enable Minimap Icons."
    end
    if kind == "giver" and (p.enableAvailable == false or p.showAvailableQuests == false) then
      return "Questie is hiding available quests, so CHUD never receives them. " .. where .. "Available Normal Quests."
    end
    if kind == "objective" and p.enableObjectives == false then return "Questie is hiding quest objectives. " .. where .. "Objectives." end
    if kind == "turnin" and p.enableTurnins == false then return "Questie is hiding turn-ins. " .. where .. "Completed Quests." end
  end
  local function Section(text, y) Header(adv, text, 14, y, 224) end

  Label(f, "C.H.U.D. MARKERS", 14, -12, "GameFontNormalLarge")
  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("TOPLEFT", 14, -36); rule:SetSize(472, 1); rule:SetColorTexture(unpack(RULE))

  Header(f, "Quests & Party", 14, -50, 472)
  Header(f, "Rares & Treasures", 14, -150, 472)
  Header(f, "Gathering", 14, -206, 472)
  Header(f, "Highlight Node", 14, -350, 472)
  Header(f, "Screen Marker (beta)", 14, -424, 472)
  C("Tracked Quest / Waypoint", "mk_tracked", -86,
    "Points to the quest you are tracking (click a quest in the tracker or quest log to track it) or the map waypoint you are tracking. It shows whenever the game provides a position for it, and sticks to the edge of the bar when it is off to the side, so you know which way to turn. Not available in dungeons.")
  local objB = C("Quest Objectives & Turn-Ins", "mk_objectives", -109,
    "Quests in your log that have a marker on this zone's map: objective areas, and turn-in spots for quests you have completed. The positions come from the same data as the world map's quest markers, so a quest with no map marker will not show. Updates when your quest log changes. Limited by Max Distance.", function() return QuestieHides("objective") or QuestieHides("turnin") end)
  local giverB = C("Quest Givers", "mk_givers", -132,
    "Quests you could pick up in this zone (the same ones the world map marks). Only quest givers the map shows will appear. Limited by Max Distance.", function() return QuestieHides("giver") end)
  C("Rare NPCs", "mk_rares", -200,
    "Rare elites on the bar. Two sources: the game's own live markers (the same ones as the minimap, shown while the game reports them), and the rare spawn points and patrol paths built into CHUD. CHUD hides rares you kill for 30 minutes (a guess; there is no published respawn figure), and honors RareScanner's kill records too when it is installed. Limited by Max Distance.")
  C("Map Treasures (game-reported)", "mk_treasures", -223,
    "Treasure markers the game itself is reporting nearby right now, the same kind of live marker as rare elites. They are not saved or imported. Chests from your gathering data are the separate Chests toggle. Limited by Max Distance.")
  C("Corpse", "mk_corpse", -246,
    "Points to your body while you are a ghost, so a corpse run has a heading on the bar. It sticks to the edge of the bar when your body is off to the side, and disappears when you come back to life. Uses the game's own corpse position, so it only shows when the game reports one.")
  C("Party Members", "mk_party", -269,
    "One icon per online party member, chosen by role (tank, healer, damage) when the game reports roles, otherwise by class. Offline members are hidden. Names show under the icon only when Icons Outside Bar is on. Shown at any distance unless Party Respects Max Distance is on. Not used in raids.")
  local partyLim = C("Party Respects Max Distance", "mk_partyLimit", -300,
    "Off (default): party members show at any distance, whenever they are in front of you. On: party members farther away than Max Distance are hidden, like other markers.")
  local smoothB = C("Smooth Party Movement", "mk_partySmooth", -323,
    "Party member positions only arrive from the game in jumps, so their icons would hop. This makes each icon glide to its newest position instead. A member who teleports or changes zone is shown at once. Turn it off to show the game's raw positions.")
  refreshers[#refreshers + 1] = function() partyLim.Dim(not ns.db.mk_party) end
  -- these two belong with the right column, under the icon style
  Header(adv, "Party", 262, -432, 224)
  for i, w in ipairs({ partyLim, smoothB }) do
    w:ClearAllPoints(); w:SetPoint("TOPLEFT", adv, "TOPLEFT", 264, -468 - (i - 1) * 23)
  end
  C("Herbs", "mk_herbs", -360,
    "Herb node positions from GatherLite or GatherMate2 (kept in CHUD's own copy, see Data Sources) plus spots where you gathered herbs yourself. The nearest 8 show on the bar and grow as you get closer. The game gives addons no way to see live nodes, so a spot can be empty until the node respawns. Limited by Max Distance. With Next Node on, the nearest one is drawn as the large pointer instead.")
  C("Ore", "mk_ore", -383,
    "Ore vein positions from GatherLite or GatherMate2 (kept in CHUD's own copy, see Data Sources) plus spots where you mined yourself. The nearest 8 show on the bar and grow as you get closer. The game gives addons no way to see live veins, so a spot can be empty until the vein respawns. Limited by Max Distance. With Next Node on, the nearest one is drawn as the large pointer instead.")
  C("Chests / Containers", "mk_containers", -406,
    "Chest and container positions from GatherLite (GatherMate2 has none) plus spots where you opened something with the Opening cast. The nearest 8 show on the bar and grow as you get closer. A chest you have opened comes back after 20 minutes. Limited by Max Distance. With Next Node on, the nearest one is drawn as the large pointer instead.")
  C("Only Show Next Node", "mk_gnextOnly", -429,
    "Hides every herb, ore and chest icon except the large Next Node pointer, for a cleaner bar. It does nothing while Next Node is off. The pointer still moves on to the next closest node once you reach or skip one.")
  Section("Questie", -50)
  local qs = Label(adv, "", 14, -76, "GameFontHighlightSmall")
  refreshers[#refreshers + 1] = function()
    if _G.Questie then qs:SetText("Questie detected"); qs:SetTextColor(0.4, 0.9, 0.4)
    else qs:SetText("Questie not detected"); qs:SetTextColor(0.65, 0.65, 0.65) end
  end
  local useQ = C("Use Questie Markers", "mk_questie", -94,
    "When Questie is installed, quest objectives, turn-ins and quest givers come from Questie's map icons instead of the game's. Turned on automatically once Questie is detected. Untick it to go back to the game's own quest markers. Quest Objectives and Quest Givers above still decide which kinds show.")
  local focusOnly = C("Focused Quest Only", "mk_qFocusOnly", -117,
    "Shows Questie icons only for the quest you have focused (click a quest icon on the bar, or focus it in Questie's tracker or the quest log). Every other quest icon is hidden.")
  local qr = Slider(adv, "Questie Max Distance", 14, -150, 130, 20, 1000, 10,
    function() return ns.db.mk_qRange end, function(v) ns.db.mk_qRange = v; ns.MarkersChanged() end,
    function(v) return format("%d yd", v) end, true)
  Tip(qr, "Questie Max Distance", "Questie icons farther away than this are hidden. Questie draws one icon per spawn, so only the nearest icon of each quest is shown. The focused quest's marker ignores this and always shows.")
  -- These only mean something with Questie: grey them out when it is missing or turned off.
  refreshers[#refreshers + 1] = function()
    local installed = _G.Questie ~= nil
    local active = installed and ns.db.mk_questie ~= false
    useQ.Dim(not installed); focusOnly.Dim(not active); qr.Dim(not active)
    -- Greyed out when Questie's own settings hide everything this option would show.
    objB.Dim(QuestieHides("objective") ~= nil and QuestieHides("turnin") ~= nil)
    giverB.Dim(QuestieHides("giver") ~= nil)
  end
  local orng = Slider(adv, "Objective Fade Distance", 14, -198, 130, 20, 500, 10,
    function() return ns.db.mk_objRange end, function(v) ns.db.mk_objRange = v; ns.MarkersStyle() end,
    function(v) return format("%d yd", v) end, true)
  Tip(orng, "Objective Fade Distance", "Quest objective icons get smaller and more transparent the farther away they are. This is the distance at which they are smallest and faintest. Lower it to fade them sooner; raise it to keep them strong for longer. The focused quest's large marker never fades.")
  local gr = Slider(adv, "Giver Fade Distance", 14, -246, 130, 20, 500, 10,
    function() return ns.db.mk_giverRange end, function(v) ns.db.mk_giverRange = v; ns.MarkersStyle() end,
    function(v) return format("%d yd", v) end, true)
  local gs = Slider(adv, "Next Node Size", 14, -474, 130, 1, 2.5, 0.1,
    function() return ns.db.mk_gnextScale or 1.6 end, function(v) ns.db.mk_gnextScale = v; ns.MarkersStyle() end,
    function(v) return format("%d%%", v * 100 + 0.5) end, true)
  Tip(gs, "Next Node Size", "How large the Next Node pointer is compared with other icons on the bar. 100% is the normal icon size.")
  Tip(gr, "Giver Fade Distance", "Quest giver icons are the least urgent, so they get smaller and more transparent the farther away they are. This is the distance at which they are smallest and faintest. Lower it to fade them sooner; raise it to keep them strong for longer.")
  local advBtn
  local function SetAdvanced(on)
    ns.db.mk_advanced = on and true or false
    adv:SetShown(on)
    f:SetClampRectInsets(on and -506 or 0, 0, 0, 0)
    if advBtn then advBtn:SetText(on and "Advanced <" or "Advanced") end
  end
  advBtn = Button(f, "Advanced", 232, -8, 92, function() SetAdvanced(not (ns.db.mk_advanced == true)) end)
  Tip(advBtn, "Advanced", "Shows or hides the second panel beside this menu: Questie, display, icon style, party, fading and the option to delete CHUD's imported gathering data. Most players only need this menu.")
  Tip(Button(f, "Settings", 330, -8, 78, function()
    f:Hide()
    if ns.categoryID then Settings.OpenToCategory(ns.categoryID) end
  end), "Open Settings", "Closes this menu and opens CHUD's main settings page: size, fonts, colors, themes and the experience bar.")
  Tip(Button(f, "Close", 412, -8, 74, function() f:Hide() end), "Close", "Closes this menu. Esc or a click outside it works too.")

  -- Right column: display options and icon style. Style settings are saved with themes.
  local X = 262    -- right column of the options panel (icon style)
  local DX = 14    -- left column (Questie, then display)
  local function CR(text, key, y, tip)
    local g2, s2 = opt(key)
    local b = Check(adv, text, DX, y, g2, s2)
    b:SetHitRectInsets(0, -190, 0, 0)
    Tip(b, text, tip)
  end
  local function StyleCheck(text, key, y, tip)
    local b = Check(adv, text, X, y, function() return ns.db[key] end,
      function(v) ns.db[key] = v; ns.MarkersStyle() end)
    b:SetHitRectInsets(0, -190, 0, 0)
    Tip(b, text, tip)
  end
  Header(adv, "Display", DX, -300, 224)
  CR("Show Distance", "mk_distance", -336, "Shows the distance in yards under the main icons: the tracked quest or waypoint, your corpse and the Next Node pointer.")
  local unlock = Check(adv, "Unlock (Drag To Move)", DX, -359, function() return not ns.db.locked end,
    function(v) ns.db.locked = not v; ns.Apply() end)
  unlock:SetHitRectInsets(0, -190, 0, 0)
  Tip(unlock, "Unlock (Drag To Move)", "Lets you drag CHUD to a new position with the left mouse button. The same as /chud unlock and /chud lock. Untick it to lock the position again.")
  Tip(Button(adv, "Center", DX, -388, 108, function() ns.CenterHorizontal() end),
    "Center", "Moves the bar to the horizontal middle of the screen and keeps its height.")
  Tip(Button(adv, "Reset Position", DX + 116, -388, 108, function() ns.ResetPosition() end),
    "Reset Position", "Puts the bar back at its default spot. Nothing else is changed.")
  local rg = Slider(adv, "Max Distance", DX, -424, 130, 100, 1500, 50,
    function() return ns.db.mk_range end, function(v) ns.db.mk_range = v; ns.MarkersChanged() end,
    function(v) return format("%d yd", v) end, true)
  Tip(rg, "Max Distance", "Markers farther away than this are hidden. The tracked quest or waypoint marker ignores this and always shows. Questie icons use their own Questie Max Distance.")

  Header(adv, "Icon Style", X, -50, 224)
  local sz = Slider(adv, "Icon Size", X, -86, 130, 10, 28, 1,
    function() return ns.db.mk_size end, function(v) ns.db.mk_size = v; ns.MarkersStyle() end, Plain, true)
  Tip(sz, "Icon Size", "How big the marker icons are, in pixels. Icon style is saved with themes.")
  local sw = ColorRow(adv, "Icon Color", "mk_color", X, -140)
  Tip(sw, "Icon Color", "Tints every marker icon. The slider sets opacity. New themes start with their accent color here.")
  StyleCheck("Original Icon Colors", "mk_native", -170,
    "Keeps the game's own icon colors (gold quest marks, skulls, etc.) instead of tinting them with Icon Color.")
  local sa = Slider(adv, "Shadow Opacity (0 = Off)", X, -202, 130, 0, 1, 0.05,
    function() return ns.db.mk_shadowAlpha end, function(v) ns.db.mk_shadowAlpha = v; ns.MarkersStyle() end, Pct, true, 100)
  Tip(sa, "Shadow Opacity", "How dark the drop shadow under each icon is. 0 turns it off.")
  local sd = Slider(adv, "Shadow Distance", X, -252, 130, 0, 4, 0.5,
    function() return ns.db.mk_shadowDist end, function(v) ns.db.mk_shadowDist = v; ns.MarkersStyle() end, Px, true)
  Tip(sd, "Shadow Distance", "How far the shadow is offset down and to the right of the icon, in pixels.")
  StyleCheck("Smaller When Far", "mk_depth", -308,
    "Icons shrink the farther away they are, down to 60% of Icon Size at the edge of their range. Herb, ore and chest nodes and quest icons size themselves by their own distance rules instead. The focused quest's icon is always the largest, and no icon makes the bar taller.")
  StyleCheck("Icons Outside Bar", "mk_outside", -331,
    "Puts the marker icons just outside the bar instead of inside its edge. They go below the bar when it is in the upper half of the screen and above it when it is in the lower half, so they never leave the screen.")
  local rate = Slider(adv, "Icon Update Rate", X, -384, 130, 4, 60, 2,
    function() return ns.db.mk_rate end, function(v) ns.db.mk_rate = v end,
    function(v) return format("%d /s", v) end, true)
  Tip(rate, "Icon Update Rate", "How many times per second icons close to you are re-aimed while you move. Higher is smoother, lower uses a little less CPU. Icons farther than about 150 yards, and every icon while you stand still, cost nothing extra. 4 is the old, steppy behavior.")
  if ns.QuestAreaSupported and ns.QuestAreaSupported() then
    StyleCheck("Glow In Quest Area", "mk_areaGlow", -354,
      "The focused quest's icon pulses with a soft glow while you are inside that quest's area (the blue zone on the map).")
  end

  -- Fading: see Fade.lua. Master Opacity always applies; the rest only matters while Fade Out When Idle is on.
  Header(adv, "Fading", DX, -526, 224)
  local fadeChk = Check(adv, "Fade Out When Idle", DX, -562, function() return ns.db.fadeOn == true end,
    function(v) ns.db.fadeOn = v end)
  fadeChk:SetHitRectInsets(0, -190, 0, 0)
  Tip(fadeChk, "Fade Out When Idle", "Off by default. When on, the bar fades to Faded Opacity unless something ticked in Show When is happening. It comes back quickly and fades out slowly, about 1.5 seconds after the last reason to show it ends. The bar stays fully shown while this menu or the settings are open and while the bar is unlocked, so you can set it up.")
  local FADE_WHEN = {
    { "fadeCombat", "In combat" }, { "fadeMap", "Map or quest log open" }, { "fadeMouse", "Mouse over the bar or minimap" },
    { "fadeRun", "Running (keys or mouse held)" }, { "fadeAuto", "Autorun, follow or flight path" }, { "fadeDead", "Dead or a ghost" },
  }
  local whenBtn
  local whenPop = CreateFrame("Frame", nil, adv)
  whenPop:SetSize(250, #FADE_WHEN * 23 + 12); whenPop:SetPoint("BOTTOMLEFT", adv, "TOPLEFT", DX, -586)   -- opens upward from the button, so it stays inside the screen
  whenPop:SetFrameStrata("FULLSCREEN_DIALOG"); whenPop:SetFrameLevel(adv:GetFrameLevel() + 20); whenPop:EnableMouse(true); whenPop:Hide()
  do
    local pb = whenPop:CreateTexture(nil, "BACKGROUND", nil, -1)
    pb:SetPoint("TOPLEFT", -1, 1); pb:SetPoint("BOTTOMRIGHT", 1, -1); pb:SetColorTexture(unpack(BORDER))
    local pg = whenPop:CreateTexture(nil, "BACKGROUND"); pg:SetAllPoints(); pg:SetColorTexture(0.06, 0.06, 0.07, 1)
  end
  for i, w in ipairs(FADE_WHEN) do
    local key = w[1]
    local cb = Check(whenPop, w[2], 6, -6 - (i - 1) * 23, function() return ns.db[key] == true end, function(v) ns.db[key] = v end)
    cb:SetHitRectInsets(0, -220, 0, 0)
  end
  whenBtn = Button(adv, "", DX, -590, 224, function() whenPop:SetShown(not whenPop:IsShown()) end)
  Tip(whenBtn, "Show When", "Opens a list of situations that keep the bar fully shown while Fade Out When Idle is on: in combat, the map or quest log open, the mouse over the bar or minimap, running by hand, autorunning (which also covers following another player and flight paths), and dead or a ghost. Running and autorun are separate, so you can keep the bar up for one and fade it for the other. The game has no autorun check, so autorun means moving with no movement key or mouse steering held. Hovering the bar is how you bring it back when it has faded.")
  adv:HookScript("OnHide", function() whenPop:Hide() end)
  refreshers[#refreshers + 1] = function()
    local n = 0
    for _, w in ipairs(FADE_WHEN) do if ns.db[w[1]] then n = n + 1 end end
    whenBtn:SetText("Show When: " .. (n > 0 and (n .. " selected") or "None"))
    whenBtn:SetEnabled(ns.db.fadeOn == true)
    if not ns.db.fadeOn then whenPop:Hide() end
  end
  local masterS = Slider(adv, "Master Opacity", X, -520, 130, 0.2, 1, 0.05,
    function() return ns.db.masterAlpha or 1 end, function(v) ns.db.masterAlpha = v end, Pct, true, 100, nil, ns.defaults.masterAlpha)
  Tip(masterS, "Master Opacity", "How solid the whole bar is, markers and XP fill included. It applies all the time, whether or not fading is on. Background Opacity in the settings page only changes the background.")
  local fadedS = Slider(adv, "Faded Opacity", X, -568, 130, 0, 1, 0.05,
    function() return ns.db.fadeAlpha or 0 end, function(v) ns.db.fadeAlpha = v end, Pct, true, 100, nil, ns.defaults.fadeAlpha)
  Tip(fadedS, "Faded Opacity", "How solid the bar is while it is faded out. 0% hides it completely until something in Show When happens, or until you move the mouse over where it sits. It never goes above Master Opacity.")
  refreshers[#refreshers + 1] = function() fadedS.Dim(not ns.db.fadeOn) end

  -- Data sources: what is installed, in the order CHUD prefers it. CHUD keeps its own copy of the gathering data.
  Header(f, "Data Sources", 14, -500, 472)
  local srcRows = {}
  for i = 1, 3 do srcRows[i] = Label(f, "", 14, -526 - (i - 1) * 16, "GameFontHighlightSmall") end
  local rsChk = Check(f, "Known Spawns", 330, -555, function() return ns.db.mk_rsData ~= false end,
    function(v) ns.db.mk_rsData = v; ns.MarkersChanged() end)
  rsChk:SetHitRectInsets(0, -100, 0, 0)
  Tip(rsChk, "Known Rare Spawns", "Rare NPCs on the bar come from two places. The game's own live markers appear only while the game reports a rare nearby. This option adds the spawn points and patrol paths built into CHUD, so you can see where rares can be before the game shows them. Turn it off if you only want the live markers, or if the list feels cluttered. Rares you kill are hidden for 30 minutes (a guess, there is no published respawn time), and RareScanner's kill records are honored too when it is installed. Needs Rare NPCs ticked above.")
  local note = Label(f, "", 14, -578, "GameFontHighlightSmall")
  note:SetWidth(472); note:SetJustifyH("LEFT"); note:SetWordWrap(true)
  local own = Label(f, "", 14, -612, "GameFontHighlightSmall")
  own:SetWidth(238); own:SetJustifyH("LEFT"); own:SetWordWrap(true)
  local importBtn = Button(f, "Refresh Gathering Data", 262, -608, 224, function()
    for _, line in ipairs(ns.ImportGatherDataSafe()) do print("|cffd9bf4dCHUD:|r " .. line) end
    Refresh()
  end)
  Tip(importBtn, "Refresh Gathering Data", "CHUD never imports by itself: the setup tour (/chud install) or this button does it. This copies every herb, ore and chest node again into CHUD's own saved data, so CHUD keeps working even if those addons are removed later. Nothing in those addons is changed. Use it after updating or switching on more of their tracking. Your own GatherMate2 nodes are included.",
    function() local s = ns.GatherSources(); if not (s.gm2 or s.gl) then return "Neither GatherLite nor GatherMate2 was detected, so there is nothing to import." end end)
  StaticPopupDialogs["CHUD_DELETE_GATHER"] = {
    text = "Delete CHUD's imported herb, ore and chest data? GatherLite and GatherMate2 are not touched, and Refresh Gathering Data brings it back.",
    button1 = DELETE or "Delete", button2 = CANCEL or "Cancel",
    OnAccept = function() ns.ClearGatherData(); Refresh() end,
    OnShow = function(self) self:SetFrameStrata("TOOLTIP"); self:Raise() end,   -- the settings menus sit in FULLSCREEN_DIALOG, above the popup's own strata
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  local deleteBtn = Button(adv, "Delete Imported Gathering Data", 14, -636, 224, function() StaticPopup_Show("CHUD_DELETE_GATHER") end)
  Tip(deleteBtn, "Delete Imported Data", "Erases CHUD's own saved copy of the herb, ore and chest nodes, so none of them show on the bar until you import again. Nodes inside GatherLite and GatherMate2 are never touched. Press Refresh Gathering Data to import again.")
  refreshers[#refreshers + 1] = function() deleteBtn:SetEnabled(ns.db.gdata ~= nil) end
  local nextChk = Check(f, "Next Node", 14, -255, function() return ns.db.mk_gnext ~= false end,
    function(v) ns.db.mk_gnext = v; ns.MarkersChanged() end)
  nextChk:SetHitRectInsets(0, -110, 0, 0)
  Tip(nextChk, "Next Node Pointer", "Draws the nearest herb, ore or chest you have not visited as a large pointer; the other nearby nodes stay on the bar as smaller icons. Once you have been within 12 yards of the pointer for half a second, or the game confirms the object, it counts as visited and the pointer moves on. Visited and skipped nodes come back after 10 minutes (chests 20). Right-click a node to skip it. When the pointer is off the bar it stays pinned to the bar's edge, pointing the way. The Pointer button below limits it to one kind.")
  local worldChk = Check(f, "Screen Marker", 14, -450, function() return ns.db.mk_world == true end,
    function(v) ns.db.mk_world = v; ns.MarkersChanged(); if ns.Redraw then ns.Redraw() end end)
  worldChk:SetHitRectInsets(0, -110, 0, 0)
  Tip(worldChk, "Screen Marker", "Experimental, off by default. Draws a beam, a ground ring and a pin on your screen where the game puts its waypoint pin for the Next Node. That position comes from the game and can sit off on slopes, so treat it as approximate. It sets the game's map waypoint to the Next Node, which replaces any waypoint you set yourself while this is on, and the game's own pin shows too. It sits behind all other UI.")
  local hlChk = Check(f, "Highlight Node", 14, -376, function() return ns.db.mk_hl ~= false end,
    function(v)
      ns.db.mk_hl = v; if ns.HighlightChanged then ns.HighlightChanged() end
      if v then ns.HighlightWarn() end
    end)
  hlChk:SetHitRectInsets(0, -110, 0, 0)
  Tip(hlChk, "Highlight Node", "When you get within about 15 yards, lights up the real herb, ore vein or chest with brackets and a ring, using the game's own interact targeting. Once you have been within 12 yards of the Next Node for half a second it counts as visited and the pointer moves on; if you are facing the spot and nothing is there, a Node Not Here effect plays. It needs a few of the game's targeting settings (the same ones Lueur uses): CHUD changes only the ones that differ, and gives them back when you turn this off or log out. If Lueur is also drawing a highlight you will see both; turn one off. |cffffb347Side effect: the game's soft interact targeting also puts a nameplate on nearby NPCs you can interact with while this is on. Turn this off to stop that; your own settings are put back.|r")
  local KIND_CYCLE = { { nil, "Pointer: Any Node" }, { "herb", "Pointer: Herbs Only" }, { "ore", "Pointer: Ore Only" }, { "box", "Pointer: Chests Only" } }
  local kindBtn = Button(f, "", 14, -283, 238, function()
    local cur = 1
    for i, k in ipairs(KIND_CYCLE) do if k[1] == ns.db.mk_gnextKind then cur = i end end
    ns.db.mk_gnextKind = KIND_CYCLE[cur % #KIND_CYCLE + 1][1]
    ns.MarkersChanged(); Refresh()
  end)
  Tip(kindBtn, "Pointer Kind", "Which nodes the Next Node pointer walks to. Chests Only skips every herb and ore node. Click to switch to the next option.")
  local hint = Label(f, "Right-click a node on the bar to skip it. Reached and skipped nodes come back by themselves (herbs and ore after 10 minutes, chests after 20).", 14, -313, "GameFontHighlightSmall")
  hint:SetWidth(472); hint:SetJustifyH("LEFT"); hint:SetWordWrap(true); hint:SetTextColor(0.65, 0.65, 0.65)
  local hlHint = Label(f, "Lights up the real herb, ore or chest when you arrive. The game also shows nameplates on nearby NPCs while this is on.", 14, -398, "GameFontHighlightSmall")
  hlHint:SetWidth(472); hlHint:SetJustifyH("LEFT"); hlHint:SetWordWrap(true); hlHint:SetTextColor(1, 0.7, 0.3)
  local worldHint = Label(f, "Experimental. Draws a beam and a pin on the screen at the Next Node. Placement is approximate until terrain data is available.", 14, -474, "GameFontHighlightSmall")
  worldHint:SetWidth(472); worldHint:SetJustifyH("LEFT"); worldHint:SetWordWrap(true); worldHint:SetTextColor(0.65, 0.65, 0.65)
  refreshers[#refreshers + 1] = function()
    local s = ns.GatherSources()
    local function Row(i, text, state, good)
      srcRows[i]:SetText(text .. "  " .. state)
      if good then srcRows[i]:SetTextColor(0.4, 0.9, 0.4) else srcRows[i]:SetTextColor(0.65, 0.65, 0.65) end
    end
    Row(1, "GatherLite (recommended: herbs, ore, chests)", s.gl and "found" or "not found", s.gl)
    local gmState = (s.gm2 and s.data) and "found" or s.gm2 and "found, no GatherMate2_Data" or s.data and "data found, GatherMate2 missing" or "not found"
    Row(2, "GatherMate2 + GatherMate2_Data (supported: herbs, ore)", gmState, s.gm2 and s.data)
    local _, readable, count = ns.RareStatus()
    Row(3, "Rare NPC data (built into CHUD)", readable and format("%d rares", count) or "missing", readable)
    rsChk:SetShown(readable)
    local lines = {}
    if s.gl and (s.gm2 or s.data) then
      lines[#lines + 1] = "|cffffb347GatherLite and GatherMate2 overlap and can interfere with each other. Consider disabling GatherMate2 in the AddOns list. CHUD keeps its own merged copy, so nothing is lost.|r"
    elseif not s.gl then
      lines[#lines + 1] = "|cffffb347GatherLite is the recommended source for herbs, ore and chests. GatherMate2 with GatherMate2_Data also works, but has no chests.|r"
    else
      lines[#lines + 1] = "|cff66e666GatherLite covers everything CHUD needs for gathering.|r"
    end
    note:SetText(table.concat(lines, "\n"))
    local g = s.own
    if g then
      own:SetText(format("CHUD copy: %d herbs, %d ore, %d chests (%s)", g.counts.herb, g.counts.ore, g.counts.box, g.at)); own:SetTextColor(0.4, 0.9, 0.4)
    else
      own:SetText("No copy yet. Press Refresh Gathering Data once GatherLite or GatherMate2 is found."); own:SetTextColor(1, 0.7, 0.3)
    end
    if s.gm2 or s.gl then importBtn:Enable() else importBtn:Disable() end
    local label = KIND_CYCLE[1][2]
    for _, k in ipairs(KIND_CYCLE) do if k[1] == ns.db.mk_gnextKind then label = k[2] end end
    kindBtn:SetText(label)
  end

  -- The advanced panel is hidden until the player asks for it; the choice is remembered.
  SetAdvanced(ns.db.mk_advanced == true)
  return f
end

-- Opens or closes the marker menu, placing it next to the bar.
function ns.ToggleMarkerMenu()
  if not ns.db then return end
  markerMenu = markerMenu or BuildMarkerMenu()
  if markerMenu:IsShown() then markerMenu:Hide(); return end
  if markerMenu.userMoved then markerMenu:Show(); return end   -- the player dragged it somewhere: leave it there
  markerMenu:ClearAllPoints()
  -- Leave room under the bar (the icons and their distance text sit there) so size and style changes can be watched
  -- live. When the bar is in the lower half of the screen the menu opens above it instead.
  local _, cy = ns.root:GetCenter()
  if type(cy) == "number" and cy < UIParent:GetHeight() / 2 then
    markerMenu:SetPoint("BOTTOM", ns.root, "TOP", 0, 60)
  else
    markerMenu:SetPoint("TOP", ns.root, "BOTTOM", 0, -60)
  end
  markerMenu:Show()
end

-- Builds CHUD's page in the game's settings window.
function ns.BuildSettings()
  local panel = CreateFrame("Frame")
  panel.name = "CHUD"
  local db = ns.db
  local function bind(key) return function() return db[key] end, function(v) db[key] = v; ns.Apply() end end

  Label(panel, "CHUD Settings", 16, -14, "GameFontNormalHuge")
  local cmds = Label(panel, "/chud [unlock | lock | center | reset | install]",
    16, -44, "GameFontHighlightSmall")
  cmds:SetWidth(210); cmds:SetJustifyH("LEFT"); cmds:SetWordWrap(true)   -- two lines, so the Daylight checkbox beside it never overlaps

  -- Theme row: dropdown + Save + Delete -------------------------------------------------
  Label(panel, "Theme", 236, -17, "GameFontNormal")
  local themeBtn, themePopup, themeUpdate
  local saveBtn, delBtn
  local function tip(btn, title, body, anchor)
    btn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, anchor or "ANCHOR_BOTTOM")
      GameTooltip:SetText(title, 1, 1, 1)
      GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  themeBtn, themePopup, themeUpdate = ListDropdown(panel, 316, -12, 124,
    function() if ns.DaylightOn() then return "Daylight (Auto Colors)" end return ns.MatchTheme() or "Custom (Unsaved)" end,
    function()
      local match = ns.MatchTheme()
      local items = {}
      local user = ns.UserThemeNames()
      if #user > 0 then
        items[#items + 1] = { text = "Saved", header = true }
        for _, n in ipairs(user) do items[#items + 1] = { text = n, value = n, selected = (n == match) } end
      end
      items[#items + 1] = { text = "Built-In", header = true }
      for _, n in ipairs(ns.BuiltinNames) do items[#items + 1] = { text = n, value = n, selected = (n == match) } end
      return items
    end,
    function(name) ns.ApplyTheme(name) end,
    "CHUDThemePopup", 210)
  tip(themeBtn, "Theme", "A theme sets colors, layout, fonts and icon style together. The ones you saved come first, then the built-in themes. \"Custom (Unsaved)\" means your settings match no theme; Save keeps them as a new one.")

  saveBtn = Button(panel, "Save", 472, -12, 56, function()
    if ns.MatchTheme() then return end    -- identical to an existing theme: nothing to save
    ShowDialog({
      text = "Name your new theme:", edit = true, default = "", yes = "Save",
      onYes = function(name)
        name = strtrim(name)
        if name == "" then return "Enter a name." end
        if ns.IsBuiltin(name) then return "That name belongs to a built-in theme." end
        local f = GetDialog()
        if ns.db.themes[name] and f.pendingOverwrite ~= name then
          f.pendingOverwrite = name
          return "A theme with that name exists. Press Save again to overwrite it."
        end
        ns.SaveTheme(name)
        Refresh()
      end,
    })
  end)
  tip(saveBtn, "Save Theme", "Saves the current look as a new theme. Disabled while your settings already match a theme, and while Daylight is on (its colors change with the clock).")

  delBtn = Button(panel, "Delete", 532, -12, 60, function()
    local name = ns.MatchTheme()
    if not name or ns.IsBuiltin(name) then return end
    ShowDialog({
      text = 'Delete theme "' .. name .. '"?', yes = "Delete",
      onYes = function() ns.DeleteTheme(name); Refresh() end,
    })
  end)
  tip(delBtn, "Delete Theme", "Deletes the selected saved theme. Built-in themes cannot be deleted.")

  -- Import and Export share a theme as a line of text.
  local exportBtn = Button(panel, "Export", 532, -40, 60, function()
    local name = ns.MatchTheme()
    ShowDialog({
      text = (name and ('Theme "' .. name .. '"') or "Your current look") .. ": press Ctrl+C to copy this code, then share it.",
      edit = true, default = ns.ExportTheme(name), yes = "Done", maxLetters = 0,
      onYes = function() return nil end,
    })
  end)
  tip(exportBtn, "Export Theme", "Shows a code for the selected theme (or your current look if it matches no theme). Copy it with Ctrl+C to share it. Anyone can paste it into Import.")
  local importBtn = Button(panel, "Import", 472, -40, 56, function()
    ShowDialog({
      text = "Paste a theme code (Ctrl+V):", edit = true, default = "", yes = "Import", maxLetters = 0,
      onYes = function(code)
        local name, err = ns.ImportTheme(code)
        if not name then return err end
        Refresh()
        print("|cffd9bf4dCHUD:|r Imported theme \"" .. name .. "\". Pick it from the Theme list to use it.")
      end,
    })
  end)
  tip(importBtn, "Import Theme", "Adds a theme from a code someone shared. It is saved to your Saved list; pick it there to use it. Fonts are not imported, since they may not exist on your computer.")

  -- Previous / Next walk the whole list (built-in, then saved) and wrap around.
  local function StepTheme(dir)
    local all = {}
    for _, n in ipairs(ns.UserThemeNames()) do all[#all + 1] = n end
    for _, n in ipairs(ns.BuiltinNames) do all[#all + 1] = n end
    local cur = ns.MatchTheme()
    local idx = 0
    for i, n in ipairs(all) do if n == cur then idx = i end end
    if idx == 0 then idx = (dir > 0) and 0 or 1 end   -- unsaved look: Next starts at the first theme, Previous at the last
    ns.ApplyTheme(all[(idx - 1 + dir) % #all + 1])
  end
  tip(Button(panel, "<", 290, -12, 24, function() StepTheme(-1) end), "Previous Theme", "Applies the theme before this one in the list. Wraps around at the start.")
  tip(Button(panel, ">", 444, -12, 24, function() StepTheme(1) end), "Next Theme", "Applies the next theme in the list. Wraps around at the end.")

  local function themeRefresh()
    themeUpdate()
    local match = ns.MatchTheme()
    if match or ns.DaylightOn() then saveBtn:Disable() else saveBtn:Enable() end
    if match and not ns.IsBuiltin(match) then delBtn:Enable() else delBtn:Disable() end
  end
  refreshers[#refreshers + 1] = themeRefresh
  ns.OnSettingsChanged = themeRefresh

  -- Daylight: colors follow the game's clock; every color control is locked while it is on.
  local colorRows = {}
  local dayChk
  dayChk = Check(panel, "Daylight: Auto Colors", 236, -46, function() return ns.DaylightOn() end,
    function(v) ns.SetDaylight(v) end)
  dayChk:SetHitRectInsets(0, -200, 0, 0)
  tip(dayChk, "Daylight: Auto Colors", "Colors follow the game's clock, changing every half hour: pale blue noon, warm golden hour, purple dusk, deep blue night. While it is on, every color control is greyed out and the theme list shows Daylight. Layout, fonts and icons are unaffected. Untick it to get your previous colors back. Picking a theme also turns it off.", "ANCHOR_BOTTOM")
  refreshers[#refreshers + 1] = function()
    dayChk.label:SetText(ns.DaylightOn() and "Daylight On: Colors Locked" or "Daylight: Auto Colors")
    local on = ns.DaylightOn()
    for _, r in ipairs(colorRows) do r.Dim(on) end
    dayChk.label:SetTextColor(on and 1 or 1, on and 0.82 or 1, on and 0.2 or 1)
  end

  -- The settings canvas is ~650 units wide and ~610 tall; columns are sized to fit, with the
  -- vertical space spread out so nothing feels compressed.
  -- Column A: size, font, fade ---------------------------------------------------
  local ax, y = 16, -72
  Header(panel, "Size & Fade", ax, y, 196)
  local _, popup = FontDropdown(panel, ax, -108, 196)
  y = -164
  local function S(text, key, a, b, step, fmt, maxFn, tipText)
    local g, set = bind(key)
    fmt = fmt or Plain
    local sl = Slider(panel, text, ax, y, 132, a, b, step, g, set, fmt, true, (fmt == Pct) and 100 or 1, maxFn, ns.defaults[key])
    HoverTip(sl, text, tipText, "ANCHOR_RIGHT")
    y = y - 48
  end
  -- Width's upper bound is the real UI width, so it can span the whole top of the screen.
  S("Width", "width", 200, 1200, 10, Plain, function() return math.max(400, floor(UIParent:GetWidth())) end,
    "How wide the bar is, in pixels. The largest value is the width of your screen.")
  S("Height", "height", 20, 80, 1, nil, nil, "How tall the bar is, in pixels. Marker icons are never drawn taller than the bar.")
  S("Visible Degrees", "span", 60, 360, 10, nil, nil, "How many degrees of the compass fit across the bar. A smaller number zooms in (marks and icons spread out); 360 shows the whole circle at once.")
  S("Font Size", "fontSize", 8, 24, 1, nil, nil, "The size of the letters and numbers on the bar.")
  S("Edge Fade Amount", "fadeAmount", 0.05, 1, 0.05, Pct, nil, "How far in from each end the fade reaches, as a share of the bar. Only has an effect while Fade Edges is on.")
  S("Background Opacity", "bgOpacity", 0, 1, 0.05, Pct, nil, "How solid the bar's background is. 0% hides it completely.")
  S("XP Fill Strength", "xpFillStrength", 0, 1, 0.05, Pct, nil, "How strong the XP fill's color is. Only has an effect while the XP Bar is on.")
  S("Text Outline (0 = Off)", "outlineWidth", 0, 2, 1, Plain, nil, "The thickness of the dark outline around text, in pixels. 0 turns the outline off.")

  -- Column B: display toggles + position -----------------------------------------
  local ROW = 24   -- vertical step for every checkbox and color row, in all columns, so the spacing matches
  local bx = 228
  Header(panel, "Display", bx, -72, 170)
  y = -108
  local function C(text, key, tipText)
    local g, set = bind(key); local b = Check(panel, text, bx, y, g, set); y = y - ROW
    tip(b, text, tipText, "ANCHOR_RIGHT")
    return b
  end
  C("Show Degree Readout", "showDegrees", "Shows your heading as a number of degrees (0 to 359, 0 = north) at the center of the bar.")
  C("Degrees Inside Bar", "degreeInline", "Draws the degree readout inside the bar and shifts the letters to make room. Only matters while Show Degree Readout is on.")
  C("Show NE/SE/SW/NW", "showIntercardinals", "Shows the diagonal letters between N, E, S and W. Turn off for a cleaner bar.")
  C("Show Tick Marks", "showTicks", "Draws the small marks along the bar that show degrees between the letters.")
  C("Show Number Labels", "showNumbers", "Adds degree numbers (30, 60, 120 and so on) between the letters.")
  C("Flip Ticks / Letters", "flipTicks", "Swaps the sides: letters below and ticks above. Marker icons inside the bar move to the opposite edge too.")
  C("Fade Edges (Bar + BG)", "fadeEdges", "Fades the letters, ticks and icons out toward the left and right ends of the bar. Edge Fade Amount sets how far in the fade reaches.")
  C("Edge Hairlines", "edgeLines", "Draws thin lines along the top and bottom edges of the bar, in the Edge Lines color.")
  C("Original Icon Colors", "mk_native", "Keeps the game's own icon colors (gold quest marks, skulls and so on) on the marker icons instead of tinting them with the icon color. The same setting is in the marker menu under Icon Style.")
  C("Glitch Effect In Dungeons", "glitchFx", "Plays a short glitch animation when the compass becomes unavailable or comes back. The game withholds your facing inside some instances, so the bar shows a notice there.")
  C("Low-CPU Rendering", "optimize", "Only redraws the bar when your heading or a marker actually changes, instead of every frame. Leave it on unless you see something not updating.")
  -- Turning the right-click menu off needs a confirmation: unlocking the bar and every marker option live there.
  local rcm = Check(panel, "Right-Click Menu", bx, y, function() return db.rightClickMenu ~= false end,
    function(v)
      if v then db.rightClickMenu = true; return end
      ShowDialog({
        text = "Warning: very important functionality is locked behind the right-click menu: unlocking and moving the bar, centering it, and every quest, rare, treasure and gathering marker option.\n\nIf you turn it off, /chud unlock, /chud lock, /chud center and /chud menu still work.",
        yes = "Disable",
        onYes = function() db.rightClickMenu = false; Refresh() end,
      })
    end)   -- cancelling leaves the setting unchanged, and the Refresh after this click re-ticks the box
  tip(rcm, "Right-Click Menu", "Right-clicking the bar opens the marker menu: unlock and center the bar and every quest, rare, treasure and gathering option. Turning it off asks for confirmation. /chud menu still opens it.", "ANCHOR_RIGHT")
  y = y - ROW

  -- Everything about the XP fill in one place.
  Header(panel, "Experience Bar", bx, y - 12, 170)
  y = y - 48
  C("XP Bar + Hover Tooltip", "xpBar", "Fills the bar with your experience progress toward the next level. Hover the bar to see the numbers.")
  local pulse = Check(panel, "XP Bar Pulse On Gain", bx, y, function() return db.xpPulse end,
    function(v) db.xpPulse = v; ns.Apply(); if v then ns.PreviewXPPulse() end end)   -- plays once so you can see it
  tip(pulse, "XP Bar Pulse On Gain", "Briefly brightens the XP fill whenever you gain experience. Ticking it plays the pulse once as a preview.", "ANCHOR_RIGHT")
  y = y - ROW
  local wave = Check(panel, "XP Edge Wave", bx, y, function() return db.xpWave ~= false end,
    function(v) db.xpWave = v; ns.UpdateXP() end)
  tip(wave, "XP Edge Wave", "A small liquid ripple along the leading edge of the XP fill. Applies to horizontal bars. Also toggled with /chud xpwave.", "ANCHOR_RIGHT")
  y = y - ROW
  -- Style and direction have several states, so each is one button that cycles (a checkbox group
  -- would let you tick two or none).
  local function Cycler(list, key, x, yy, title, body)
    local btn = Button(panel, "", x, yy, 170, function()
      local cur = 1
      for i, f in ipairs(list) do if f[1] == db[key] then cur = i end end
      db[key] = list[cur % #list + 1][1]
      ns.Apply(); Refresh()
    end)
    refreshers[#refreshers + 1] = function()
      local label = list[1][2]
      for _, f in ipairs(list) do if f[1] == db[key] then label = f[2] end end
      btn:SetText(label)
    end
    tip(btn, title, body .. " Click to switch to the next option.", "ANCHOR_RIGHT")
    return btn
  end
  Cycler({ { "fadeCenter", "Style: Fade From Center" }, { "fadeBottom", "Style: Fade From Bottom" }, { "fadeTop", "Style: Fade From Top" },
    { "band", "Style: Short Band" }, { "full", "Style: Full Height" } },
    "xpFillStyle", bx, y, "XP Fill Style", "How the XP color is shaded vertically: fading from the center, bottom or top, as a short band, or filling the full height. XP Fill Strength sets how strong it is.")
  y = y - 28   -- 24 px button + 4 px gap
  Cycler({ { "left", "Fill: Left To Right" }, { "edges", "Fill: From Both Edges" }, { "center", "Fill: From Center" },
    { "up", "Fill: Bottom To Top" }, { "down", "Fill: Top To Bottom" } },
    "xpFillMode", bx, y, "XP Fill Direction", "Which way the XP fill grows as you gain experience: left to right, from both edges, from the center, bottom to top or top to bottom.")

  -- Column C: colors -------------------------------------------------------------
  local cx = 412
  Header(panel, "Background", cx, -72, 232)
  tip(Check(panel, "Solid", cx, -108, function() return db.bgMode == "solid" end,
    function() db.bgMode = "solid"; ns.Apply() end), "Solid Background", "A flat plate behind the bar, in the Solid Color.", "ANCHOR_RIGHT")
  tip(Check(panel, "Gradient", cx + 84, -108, function() return db.bgMode == "gradient" end,
    function() db.bgMode = "gradient"; ns.Apply() end), "Gradient Background", "A background that is strongest in the middle and fades out toward the ends, using the Gradient Center and Gradient Edge colors.", "ANCHOR_RIGHT")
  local function CRow(...) local r = ColorRow(...); colorRows[#colorRows + 1] = r; return r end
  CRow(panel, "Solid Color", "bgSolid", cx, -108 - ROW)
  CRow(panel, "Gradient Center", "bgCenter", cx, -108 - 2 * ROW)
  CRow(panel, "Gradient Edge", "bgEdge", cx, -108 - 3 * ROW)

  y = -108 - 3 * ROW - 28
  Header(panel, "Elements", cx, y, 232)
  y = y - 36
  for _, r in ipairs({
    { "Text / Numbers", "textColor" }, { "E / S / W", "cardinalColor" }, { "North", "northColor" },
    { "Tick Marks", "tickColor" }, { "Center Marker", "markerColor" }, { "Degree Readout", "degreeColor" },
  }) do
    CRow(panel, r[1], r[2], cx, y); y = y - ROW
  end

  -- Marker style: two checkboxes that act as a pair (one is always on).
  tip(Check(panel, "Marker: Short", cx, y, function() return db.markerStyle ~= "notch" end,
    function() db.markerStyle = "short"; ns.Apply() end), "Short Marker", "The center marker is a short vertical line over the tick area.", "ANCHOR_RIGHT")
  tip(Check(panel, "Marker: Notch", cx + 116, y, function() return db.markerStyle == "notch" end,
    function() db.markerStyle = "notch"; ns.Apply() end), "Notch Marker", "The center marker is a small triangle at the edge of the bar, with no full-height line.", "ANCHOR_RIGHT")
  y = y - ROW - 4

  Header(panel, "XP & Edge Colors", cx, y, 232)
  y = y - 36
  CRow(panel, "XP Bar", "xpColor", cx, y)
  CRow(panel, "Edge Lines", "edgeColor", cx, y - ROW)
  y = y - 2 * ROW - 4
  do
    local g, set = bind("scanlines")
    local sc = Check(panel, "Scanlines (Bar + Tooltip)", cx, y, g, set)
    sc:SetHitRectInsets(0, -170, 0, 0)
    tip(sc, "Scanlines", "Thin dark horizontal lines over the bar background and inside the XP tooltip. They drift slowly down. One switch covers both.", "ANCHOR_RIGHT")
    tip(Button(panel, "Tooltip Colors...", cx, y - ROW - 4, 232, function() ns.ToggleTipColors() end),
      "Tooltip Colors", "Opens the XP tooltip color panel. By default the tooltip colors follow the theme; there you can pick your own.", "ANCHOR_RIGHT")
  end

  -- Bottom bar: resets -------------------------------------------------------------
  local rule = panel:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("TOPLEFT", 16, -576); rule:SetSize(628, 1); rule:SetColorTexture(unpack(RULE))
  local resetColors = Button(panel, "Reset Colors", 16, -588, 120, function() ns.ResetColors() end)
  tip(resetColors, "Reset Colors", "Puts every color, the background opacity, the icon color and the tooltip colors back to the defaults for your faction. Layout, fonts and markers are untouched. Disabled while Daylight is on.", "ANCHOR_TOP")
  refreshers[#refreshers + 1] = function() if ns.DaylightOn() then resetColors:Disable() else resetColors:Enable() end end
  tip(Button(panel, "Reset Layout/Behavior", 142, -588, 160, function() ns.ResetBehavior() end),
    "Reset Layout/Behavior", "Puts size, fonts, toggles, XP bar options and icon style back to the defaults (this also locks the bar again). Colors and position are untouched.", "ANCHOR_TOP")
  tip(Button(panel, "Reset All Settings", 308, -588, 130, function() ns.Reset() end),
    "Reset All Settings", "Puts every CHUD setting back to the defaults, including Daylight and marker options. Your saved themes, recorded gathering spots and CHUD's imported gathering data are kept.", "ANCHOR_TOP")
  local xpBtn
  xpBtn = Button(panel, "", 444, -588, 190, function()
    if not ns.BlizzXPFound() then print("|cffd9bf4dCHUD:|r could not find the default XP bar on this client."); return end
    ns.db.hideBlizzXP = not ns.db.hideBlizzXP
    ns.ApplyBlizzXP()
    Refresh()
  end)
  refreshers[#refreshers + 1] = function() xpBtn:SetText("Default XP Bar: " .. (ns.db.hideBlizzXP and "Hidden" or "Shown")) end
  tip(xpBtn, "Default XP Bar", "Shows or hides the game's own experience bar at the bottom of the screen. CHUD includes its own XP tracker (the fill on the bar, with the numbers when you hover it; see XP Bar + Hover Tooltip), so hiding the default one avoids showing the same thing twice. Keep that option on if you hide this bar.", "ANCHOR_TOP")

  panel:SetScript("OnShow", Refresh)
  panel:SetScript("OnHide", function()
    popup:Hide(); themePopup:Hide()
    if dialog then dialog:Hide() end
  end)
  local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)
  ns.categoryID = category:GetID()
  Refresh()
end


-- Tooltip colors panel ------------------------------------------------------------------------------------------
-- Opened from the main settings. By default the XP tooltip colors follow the theme (with contrast checks);
-- switching "Match Theme Colors" off lets you pick them. A sample tooltip stays up beside it while it is open.
local tipColors
-- Builds the tooltip colors window.
local function BuildTipColors()
  local f = CreateFrame("Frame", "CHUDTipColors", UIParent)
  f:SetSize(300, 360); f:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
  f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:SetMovable(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:Hide()
  local b = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  b:SetPoint("TOPLEFT", -1, 1); b:SetPoint("BOTTOMRIGHT", 1, -1); b:SetColorTexture(unpack(BORDER))
  local g = f:CreateTexture(nil, "BACKGROUND"); g:SetAllPoints(); g:SetColorTexture(0.06, 0.06, 0.07, 0.97)
  tinsert(UISpecialFrames, "CHUDTipColors")
  f:SetScript("OnHide", function() if ns.TipHide then ns.TipHide(true) end end)
  f:SetScript("OnShow", function() Refresh(); if ns.TipPreview then ns.TipPreview(true) end end)

  Label(f, "C.H.U.D. TOOLTIP COLORS", 14, -12, "GameFontNormalLarge")
  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("TOPLEFT", 14, -36); rule:SetSize(272, 1); rule:SetColorTexture(unpack(RULE))

  local rows = {}
  local auto = Check(f, "Match Theme Colors", 14, -50,
    function() return ns.db.tipAuto ~= false end,
    function(v)
      if not v and ns.TipAutoColors then   -- start the custom colors from what the theme gives now
        local a = ns.TipAutoColors()
        ns.db.tipGood = { a.good[1], a.good[2], a.good[3], 1 }
        ns.db.tipRest = { a.rest[1], a.rest[2], a.rest[3], 1 }
        ns.db.tipBg, ns.db.tipEdge, ns.db.tipAccent, ns.db.tipTitle, ns.db.tipText =
          { a.bg[1], a.bg[2], a.bg[3], 1 }, { a.edge[1], a.edge[2], a.edge[3], 1 }, { a.accent[1], a.accent[2], a.accent[3], 1 },
          { a.title[1], a.title[2], a.title[3], 1 }, { a.text[1], a.text[2], a.text[3], 1 }
      end
      ns.db.tipAuto = v
      Refresh(); if ns.TipPreview then ns.TipPreview(false) end
    end)
  auto:SetHitRectInsets(0, -170, 0, 0)
  local note = Label(f, "On: colors follow the theme and are adjusted so the text stays readable.", 40, -74, "GameFontHighlightSmall")
  note:SetWidth(246); note:SetWordWrap(true); note:SetTextColor(0.65, 0.65, 0.65)
  local y = -112
  for _, r in ipairs({ { "Background", "tipBg" }, { "Border Lines", "tipEdge" }, { "Accent / Glow", "tipAccent" },
    { "Level Title", "tipTitle" }, { "Text", "tipText" },
    { "Remaining", "tipGood" }, { "Rested", "tipRest" } }) do
    rows[#rows + 1] = ColorRow(f, r[1], r[2], 14, y, true); y = y - 28
  end
  refreshers[#refreshers + 1] = function()
    local on = ns.db.tipAuto ~= false
    for _, r in ipairs(rows) do r.Dim(on) end
  end
  Button(f, "Replay Sample", 14, y - 8, 130, function() if ns.TipPreview then ns.TipPreview(true) end end)
  Button(f, "Close", 156, y - 8, 130, function() f:Hide() end)
  f:SetHeight(-y + 44)
  return f
end
-- Refreshes the tooltip colors window's preview after a setting changes.
function ns.TipColorsChanged() if tipColors and tipColors:IsShown() and ns.TipPreview then ns.TipPreview(false) end end
-- Opens or closes the tooltip colors window.
function ns.ToggleTipColors()
  tipColors = tipColors or BuildTipColors()
  if tipColors:IsShown() then tipColors:Hide() else tipColors:Show() end
end
