local ADDON, ns = ...

-- Install: the setup tour. It opens by itself the first time CHUD loads (and for anyone upgrading from an earlier version), and
-- /chud install runs it again at any time. Six short pages: welcome, choose a look, choose what the bar points to, connect the
-- gathering and rare data, fading, and a summary. It only changes what the player picks. The bar behind the window is live, so each
-- choice is visible straight away. Closing the window in any way counts as finishing the tour (db.tourDone).

local UI = ns.UI   -- widgets shared with Settings.lua
local W, H = 560, 460
local STEPS = 6
local GOLD, GREY, GREEN, ORANGE, RED = { 1, 0.82, 0 }, { 0.65, 0.65, 0.65 }, { 0.4, 0.9, 0.4 }, { 1, 0.7, 0.3 }, { 1, 0.35, 0.35 }

local frame, cur = nil, 0
local pages, dots = {}, {}
local pageT = 1   -- fade-in progress of the current page, 0 to 1

-- A wrapped block of text at x, y inside parent.
local function Text(parent, str, x, y, w, color, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", x, y); fs:SetWidth(w); fs:SetJustifyH("LEFT"); fs:SetWordWrap(true)
  fs:SetText(str)
  if color then fs:SetTextColor(color[1], color[2], color[3]) end
  return fs
end

-- The heading and one-line subtitle every page starts with.
local function PageTitle(p, title, sub)
  Text(p, title, 24, -14, 500, GOLD, "GameFontNormalHuge")
  Text(p, sub, 24, -46, 500, GREY, "GameFontHighlightSmall")
end

-- Pages -------------------------------------------------------------------------------------------

-- 1. Welcome: what the tour covers, as four small cards.
local function BuildWelcome(p)
  local title = p:CreateFontString(nil, "OVERLAY"); title:SetFont(STANDARD_TEXT_FONT, 32, "OUTLINE")
  title:SetPoint("TOP", p, "TOP", 0, -22); title:SetText("Welcome to CHUD"); title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  sub:SetPoint("TOP", title, "BOTTOM", 0, -8); sub:SetText("A compass bar for your adventures"); sub:SetTextColor(GREY[1], GREY[2], GREY[3])
  local CARDS = {
    { "1", "A look", "Pick a theme. The bar on your screen changes as you choose." },
    { "2", "Markers", "Choose what it points to: quests, party, herbs, ore, chests." },
    { "3", "Data", "Connect GatherLite so the gathering markers have something to show. Rare NPCs are built in." },
    { "4", "Fading", "Optionally hide the bar until you need it." },
  }
  local cw, gap = 120, 10
  local x0 = (W - (4 * cw + 3 * gap)) / 2
  for i, c in ipairs(CARDS) do
    local card = CreateFrame("Frame", nil, p)
    card:SetSize(cw, 156); card:SetPoint("TOPLEFT", x0 + (i - 1) * (cw + gap), -108)
    local edge = card:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1); edge:SetColorTexture(unpack(UI.RULE))
    local bg = card:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.09, 0.09, 0.10, 1)
    local num = card:CreateFontString(nil, "OVERLAY"); num:SetFont(STANDARD_TEXT_FONT, 26, "OUTLINE")
    num:SetPoint("TOPLEFT", 12, -10); num:SetText(c[1]); num:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local head = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", 12, -46); head:SetText(c[2]); head:SetTextColor(1, 1, 1)
    Text(card, c[3], 12, -68, cw - 22, GREY, "GameFontHighlightSmall")
  end
  local foot = Text(p, "About a minute. Every choice can be changed later with /chud or by right-clicking the bar.", 40, -290, W - 80, GREY, "GameFontHighlightSmall")
  foot:SetJustifyH("CENTER")
end

-- 2. Look: a row of swatches, one per theme, plus previous and next.
local function BuildLook(p)
  PageTitle(p, "Choose a look", "The bar behind this window changes as you pick.")
  local name = p:CreateFontString(nil, "OVERLAY"); name:SetFont(STANDARD_TEXT_FONT, 28, "OUTLINE")
  name:SetPoint("TOP", p, "TOP", 0, -92); name:SetTextColor(1, 1, 1)
  local count = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  count:SetPoint("TOP", name, "BOTTOM", 0, -6); count:SetTextColor(GREY[1], GREY[2], GREY[3])

  local list = {}
  local function Reload()
    wipe(list)
    for _, n in ipairs(ns.BuiltinNames) do list[#list + 1] = n end
    for _, n in ipairs(ns.UserThemeNames()) do list[#list + 1] = n end
  end
  Reload()

  local swatches = {}
  local function Update()
    local match = ns.MatchTheme()
    local idx = 0
    for i, n in ipairs(list) do if n == match then idx = i end end
    if ns.DaylightOn() then name:SetText("Daylight"); count:SetText("Colors follow the game clock")
    elseif idx > 0 then name:SetText(match); count:SetText(format("%d of %d", idx, #list))
    else name:SetText("Custom"); count:SetText("Your current settings") end
    for i, s in ipairs(swatches) do
      local on = (i == idx) and not ns.DaylightOn()
      s.edge:SetVertexColor(on and GOLD[1] or 0.25, on and GOLD[2] or 0.25, on and GOLD[3] or 0.25, 1)
      s:SetSize(on and 20 or 16, on and 20 or 16)
    end
  end
  local function Pick(n) ns.ApplyTheme(n); Update() end
  local function Step(dir)
    local match = ns.MatchTheme()
    local idx = 0
    for i, n in ipairs(list) do if n == match then idx = i end end
    if idx == 0 then idx = (dir > 0) and 0 or 1 end
    Pick(list[(idx - 1 + dir) % #list + 1])
  end

  UI.Button(p, "<", 40, -96, 44, function() Step(-1) end)
  UI.Button(p, ">", W - 40 - 44, -96, 44, function() Step(1) end)

  -- One swatch per theme, in the theme's accent color. Click to apply it.
  local total = #list * 19
  for i, n in ipairs(list) do
    local s = CreateFrame("Button", nil, p)
    s:SetSize(16, 16); s:SetPoint("TOPLEFT", (W - total) / 2 + (i - 1) * 19, -176)
    s.edge = s:CreateTexture(nil, "BACKGROUND"); s.edge:SetPoint("TOPLEFT", -2, 2); s.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    s.edge:SetTexture("Interface\\Buttons\\WHITE8X8")
    local fill = s:CreateTexture(nil, "ARTWORK"); fill:SetAllPoints(); fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    local d = ns.GetThemeData(n)
    local c = d and (d.cardinalColor or d.mk_color) or { 1, 0.82, 0, 1 }
    fill:SetVertexColor(c[1], c[2], c[3], 1)
    s:SetScript("OnClick", function() Pick(n) end)
    s:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(n, 1, 1, 1); GameTooltip:Show() end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    swatches[i] = s
  end

  local day = UI.Check(p, "Daylight: colors follow the game clock", (W - 300) / 2, -222,
    function() return ns.DaylightOn() end, function(v) ns.SetDaylight(v); Update() end)
  day:SetHitRectInsets(0, -260, 0, 0)
  Text(p, "Daylight changes the colors every half hour: pale blue at noon, golden at dusk, deep blue at night.", 60, -252, 440, GREY, "GameFontHighlightSmall"):SetJustifyH("CENTER")
  local native = UI.Check(p, "Original Icon Colors on marker icons", (W - 300) / 2, -276,
    function() return ns.db.mk_native == true end, function(v) ns.db.mk_native = v; if ns.MarkersStyle then ns.MarkersStyle() end end)
  native:SetHitRectInsets(0, -260, 0, 0)
  p.OnOpen = function() Reload(); Update(); native:SetChecked(ns.db.mk_native == true) end
end

-- 3. What the bar points to
local function BuildWhat(p)
  PageTitle(p, "What should the bar point to?", "Tick what you want. Every one of these can be changed later in the right-click menu.")
  local function Col(x, y, title, items)
    Text(p, title, x, y, 230, GOLD, "GameFontNormal")
    for i, it in ipairs(items) do
      local key = it[1]
      local c = UI.Check(p, it[2], x, y - 22 - (i - 1) * 24, function() return ns.db[key] == true end,
        function(v) ns.db[key] = v; ns.MarkersChanged() end)
      c:SetHitRectInsets(0, -190, 0, 0)
    end
  end
  Col(24, -88, "Quests", { { "mk_tracked", "Tracked quest or waypoint" }, { "mk_objectives", "Quest objectives and turn-ins" }, { "mk_givers", "Quest givers" } })
  Col(24, -214, "People", { { "mk_party", "Party members" }, { "mk_corpse", "Your corpse when you are a ghost" } })
  Col(290, -88, "Gathering", { { "mk_herbs", "Herbs" }, { "mk_ore", "Ore" }, { "mk_containers", "Chests" }, { "mk_gnext", "Next Node pointer" }, { "mk_gnextOnly", "Only show the Next Node" } })
  Col(290, -250, "Rare", { { "mk_rares", "Rare NPCs" }, { "mk_treasures", "Map treasures" } })
  Text(p, "The icons around the bar are a demo. Untick \"Only show the Next Node\" to see every nearby herb, ore and chest too.",
    24, -318, 510, GREY, "GameFontHighlightSmall")
end

-- 4. Data: what CHUD found, how the import works, and the import itself.
local function BuildData(p)
  PageTitle(p, "Gathering and rare data", "CHUD reads addons you already use. It never changes them.")
  local rows = {}
  local marks = {}   -- a green check or a red X in front of each row
  for i = 1, 3 do
    rows[i] = Text(p, "", 46, -80 - (i - 1) * 20, 480, nil, "GameFontHighlightSmall")
    marks[i] = p:CreateTexture(nil, "ARTWORK"); marks[i]:SetSize(16, 16); marks[i]:SetPoint("TOPLEFT", 24, -78 - (i - 1) * 20)
  end
  Text(p, "1.  CHUD looks for GatherLite (best: herbs, ore and chests) or GatherMate2 with GatherMate2_Data (herbs and ore).\n" ..
    "2.  It copies the node positions once into its own saved data, so the markers keep working even if you later remove those addons. This takes a moment.\n" ..
    "3.  Rare NPC spawn points are built into CHUD, so there is nothing to import. CHUD hides rares you kill for 30 minutes.",
    24, -150, 500, { 0.85, 0.85, 0.85 }, "GameFontHighlightSmall")
  local result = Text(p, "", 246, -266, 280, nil, "GameFontHighlightSmall")
  local note = Text(p, "", 24, -306, 500, ORANGE, "GameFontHighlightSmall")
  local btn
  local function Refresh()
    local s = ns.GatherSources()
    local function Row(i, label, state, good)
      rows[i]:SetText(label .. "  " .. state)
      local c = good and GREEN or RED
      rows[i]:SetTextColor(c[1], c[2], c[3])
      marks[i]:SetTexture(good and "Interface\\RaidFrame\\ReadyCheck-Ready" or "Interface\\RaidFrame\\ReadyCheck-NotReady")
    end
    Row(1, "GatherLite", s.gl and "found" or "not found", s.gl)
    Row(2, "GatherMate2 + GatherMate2_Data", (s.gm2 and s.data) and "found" or s.gm2 and "found, GatherMate2_Data missing" or "not found", s.gm2 and s.data)
    local inst, readable, n = ns.RareStatus()
    Row(3, "Rare NPC data (built in)", readable and format("%d rares", n) or "missing", readable)
    if s.gl or s.gm2 then btn:Enable() else btn:Disable() end
    local g = s.own
    if g and g.counts then
      result:SetText(format("CHUD has its own copy: %d herbs, %d ore, %d chests.", g.counts.herb, g.counts.ore, g.counts.box)); result:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
    elseif s.gl or s.gm2 then
      result:SetText("Not imported yet. Press the button."); result:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    else
      result:SetText("Nothing to import. Install GatherLite, then run /chud install again."); result:SetTextColor(GREY[1], GREY[2], GREY[3])
    end
    if s.gl and (s.gm2 or s.data) then
      note:SetText("GatherLite and GatherMate2 overlap and can interfere with each other. Consider turning GatherMate2 off in the AddOns list. CHUD keeps its own merged copy, so nothing is lost.")
    else
      note:SetText("")
    end
  end
  btn = UI.Button(p, "Import Gathering Data", 24, -262, 210, function()
    btn:Disable(); result:SetText("Reading nodes..."); result:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    C_Timer.After(0.15, function()   -- a moment for the message to show before the import runs
      for _, line in ipairs(ns.ImportGatherDataSafe()) do print("|cffd9bf4dCHUD:|r " .. line) end
      Refresh()
    end)
  end)
  -- Highlight Node: on by default, with its side effect stated up front.
  local hl = UI.Check(p, "Highlight Node (lights up the real herb, ore or chest when you arrive)", 24, -338,
    function() return ns.db.mk_hl ~= false end, function(v) ns.db.mk_hl = v; if ns.HighlightChanged then ns.HighlightChanged() end end)
  hl:SetHitRectInsets(0, -440, 0, 0)
  Text(p, "Warning: " .. (ns.HL_WARN or ""), 48, -362, 480, ORANGE, "GameFontHighlightSmall")
  p.OnOpen = function() Refresh(); hl:SetChecked(ns.db.mk_hl ~= false) end
end

-- 5. Fading
local function BuildFade(p)
  PageTitle(p, "Fade when you don't need it", "Optional. You can change this later under Advanced, Fading.")
  local always = UI.Check(p, "Always visible", 24, -92, function() return not ns.db.fadeOn end, function(v) ns.db.fadeOn = not v end)
  always:SetHitRectInsets(0, -300, 0, 0)
  Text(p, "The bar stays up all the time. This is the default.", 48, -114, 460, GREY, "GameFontHighlightSmall")
  local fade = UI.Check(p, "Fade out when idle", 24, -150, function() return ns.db.fadeOn == true end, function(v) ns.db.fadeOn = v end)
  fade:SetHitRectInsets(0, -300, 0, 0)
  Text(p, "The bar fades away after a moment and comes back when you open the map or quest log, hover the bar or the minimap, or die. " ..
    "Combat, running and autorun can be added to that list in Advanced, each on its own.", 48, -172, 460, GREY, "GameFontHighlightSmall")
  Text(p, "Fading is handy with addons that hide your interface while you run. It also has a Master Opacity slider for a dimmer bar at all times.",
    24, -238, 500, { 0.85, 0.85, 0.85 }, "GameFontHighlightSmall")
end

-- 6. Summary: the commands worth knowing, then the one choice left.
local function BuildDone(p)
  PageTitle(p, "You're all set", "A few things worth knowing.")
  local ROWS = {
    { "Right-click the bar", "Opens the marker menu. Right-click a node on the bar to skip it." },
    { "/chud", "Opens the full settings." },
    { "/chud unlock | lock | center", "Move the bar, fix it in place, or center it." },
    { "/chud install", "Runs this tour again." },
  }
  for i, r in ipairs(ROWS) do
    local y = -84 - (i - 1) * 30
    Text(p, r[1], 24, y, 190, GOLD, "GameFontHighlightSmall")
    Text(p, r[2], 224, y, 312, { 0.85, 0.85, 0.85 }, "GameFontHighlightSmall")
  end
  local rule = p:CreateTexture(nil, "ARTWORK"); rule:SetPoint("TOPLEFT", 24, -214); rule:SetSize(W - 48, 1); rule:SetColorTexture(unpack(UI.RULE))
  -- CHUD has its own XP fill, so the game's experience bar at the bottom of the screen is hidden by default.
  local xp = UI.Check(p, "Hide the game's default XP bar", 24, -228,
    function() return ns.db.hideBlizzXP == true end,
    function(v) ns.db.hideBlizzXP = v; if ns.ApplyBlizzXP then ns.ApplyBlizzXP() end end)
  xp:SetHitRectInsets(0, -260, 0, 0)
  UI.Tip(xp, "Default XP Bar", "CHUD includes its own XP tracker: the fill on the bar, with your numbers when you hover the bar. Hiding the game's bar is safe as long as CHUD's XP Bar stays on (in /chud).")
  Text(p, "CHUD's XP fill on the bar replaces it. Untick this to bring it back, or change it later in /chud with the Default XP Bar button.",
    48, -256, 480, GREY, "GameFontHighlightSmall")
  p.OnOpen = function() xp:SetChecked(ns.db.hideBlizzXP == true) end
end

local BUILDERS = { BuildWelcome, BuildLook, BuildWhat, BuildData, BuildFade, BuildDone }

-- The window ---------------------------------------------------------------------------------------

local backBtn, nextBtn, stepText

-- Shows page n: builds it the first time, fades it in, and updates the dots and buttons.
local function Go(n)
  n = math.max(1, math.min(STEPS, n))
  if pages[cur] then pages[cur]:Hide() end
  cur = n
  local p = pages[n]
  if not p then
    p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 0, -44); p:SetPoint("BOTTOMRIGHT", 0, 58)
    pages[n] = p
    BUILDERS[n](p)
  end
  p:SetAlpha(0); p:Show(); pageT = 0
  if p.OnOpen then p.OnOpen() end
  for i, d in ipairs(dots) do
    if i == cur then d:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1); d:SetSize(10, 10)
    elseif i < cur then d:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.45); d:SetSize(8, 8)
    else d:SetVertexColor(0.4, 0.4, 0.4, 1); d:SetSize(8, 8) end
  end
  stepText:SetText(format("Step %d of %d", cur, STEPS))
  backBtn:SetEnabled(cur > 1)
  nextBtn:SetText(cur == 1 and "Begin" or cur == STEPS and "Finish" or "Next")
  if ns.RefreshSettings then ns.RefreshSettings() end   -- keep every checkbox in step with the saved settings
end

local told
local function Build()
  local f = CreateFrame("Frame", "CHUDInstall", UIParent)
  f:SetSize(W, H); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetToplevel(true)
  f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true); f:Hide()
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  local edge = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1); edge:SetColorTexture(unpack(UI.BORDER))
  local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.06, 0.07, 0.98)
  tinsert(UISpecialFrames, "CHUDInstall")   -- Esc closes it

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 20, -14); title:SetText("C.H.U.D. SETUP")
  stepText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  stepText:SetPoint("TOPRIGHT", -96, -19); stepText:SetTextColor(GREY[1], GREY[2], GREY[3])
  local skip = CreateFrame("Button", nil, f)
  skip:SetSize(70, 18); skip:SetPoint("TOPRIGHT", -16, -17)
  local skipText = skip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  skipText:SetAllPoints(); skipText:SetJustifyH("RIGHT"); skipText:SetText("Skip tour"); skipText:SetTextColor(GREY[1], GREY[2], GREY[3])
  skip:SetScript("OnEnter", function() skipText:SetTextColor(1, 1, 1) end)
  skip:SetScript("OnLeave", function() skipText:SetTextColor(GREY[1], GREY[2], GREY[3]) end)
  skip:SetScript("OnClick", function() f:Hide() end)
  local top = f:CreateTexture(nil, "ARTWORK"); top:SetPoint("TOPLEFT", 20, -40); top:SetSize(W - 40, 1); top:SetColorTexture(unpack(UI.RULE))
  local bottom = f:CreateTexture(nil, "ARTWORK"); bottom:SetPoint("BOTTOMLEFT", 20, 56); bottom:SetSize(W - 40, 1); bottom:SetColorTexture(unpack(UI.RULE))

  backBtn = UI.Button(f, "Back", 20, -(H - 44), 100, function() Go(cur - 1) end)
  nextBtn = UI.Button(f, "Next", W - 20 - 120, -(H - 44), 120, function()
    if cur >= STEPS then f:Hide() else Go(cur + 1) end
  end)
  for i = 1, STEPS do
    local d = f:CreateTexture(nil, "ARTWORK"); d:SetTexture("Interface\\Buttons\\WHITE8X8")
    d:SetPoint("BOTTOM", f, "BOTTOM", (i - (STEPS + 1) / 2) * 18, 24)
    dots[i] = d
  end

  -- Fades the window in when it opens and each page in when it appears.
  f.openT = 1
  f:SetScript("OnUpdate", function(self, elapsed)
    if self.openT < 1 then self.openT = math.min(1, self.openT + elapsed / 0.35); self:SetAlpha(self.openT) end
    if pageT < 1 and pages[cur] then pageT = math.min(1, pageT + elapsed / 0.3); pages[cur]:SetAlpha(pageT) end
  end)
  -- Closing in any way counts as done, so it does not open again by itself.
  f:SetScript("OnHide", function()
    if ns.db then ns.db.tourDone = true end
    if ns.SetDemoMarkers then ns.SetDemoMarkers(false) end   -- the fake markers exist only while the tour is open
    if not told then told = true; print("|cffd9bf4dCHUD:|r setup closed. Type /chud install to run it again.") end
    if ns.db and not ns.db.gdata then
      print("|cffd9bf4dCHUD:|r |cffffb34dNo gathering data was imported, and CHUD never imports it by itself, so herb, ore and chest markers stay empty. Press Refresh Gathering Data in the marker menu (opened from /chud), or run /chud install.|r")
    end
  end)
  return f
end

-- True while the tour is open on its fading page. Fade.lua keeps the bar fully visible during the rest of the tour, but lets it
-- fade here so the choices on this page can be seen working.
function ns.TourOnFadePage() return frame ~= nil and frame:IsShown() and cur == 5 end

-- Opens the setup tour at the first page.
function ns.StartTour()
  if not (ns.db and ns.UI and ns.root) then return end
  frame = frame or Build()
  frame:ClearAllPoints()
  -- Keep clear of the bar so each choice can be watched: below the bar's half of the screen goes up, otherwise down.
  local _, cy = ns.root:GetCenter()
  if type(cy) == "number" and cy < UIParent:GetHeight() / 2 then frame:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
  else frame:SetPoint("CENTER", UIParent, "CENTER", 0, -80) end
  frame.openT = 0; frame:SetAlpha(0)
  frame:Show()
  if ns.SetDemoMarkers then ns.SetDemoMarkers(true) end   -- fake markers all the way around, so the bar has something to show
  Go(1)
end

-- /chud install: after a confirmation, puts CHUD back to a first-run state (all settings, the imported gathering data) and
-- opens the tour. Saved themes, recorded gathering spots and the game settings Highlight Node must give back are kept.
StaticPopupDialogs["CHUD_RERUN_SETUP"] = {
  text = "Run the CHUD setup again? This resets every CHUD setting and deletes its imported gathering data. Saved themes are kept.",
  button1 = ACCEPT or "OK", button2 = CANCEL or "Cancel",
  OnAccept = function()
    if not ns.db then return end
    ns.Reset()
    if ns.ClearGatherData then ns.ClearGatherData() end
    ns.db.tourDone = false
    ns.StartTour()
  end,
  OnShow = function(self) self:SetFrameStrata("TOOLTIP"); self:Raise() end,   -- above the settings menus
  timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
function ns.RerunSetup() StaticPopup_Show("CHUD_RERUN_SETUP") end

-- First run: a few seconds after entering the world, once, waiting for combat to end.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
  local tries = 0
  local function Try()
    local db = ns.db
    if not db or db.tourDone then return end
    tries = tries + 1
    if InCombatLockdown() or UnitIsDeadOrGhost("player") then
      if tries < 24 then C_Timer.After(5, Try) end
      return
    end
    ns.StartTour()
  end
  C_Timer.After(6, Try)
end)
