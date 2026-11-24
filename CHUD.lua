local ADDON, ns = ...

-- Colors are {r, g, b, a}. Gradient mode draws two half-textures that blend from
-- the center color (middle of the bar) out to the edge color (left and right ends).
ns.defaults = {
  width = 520, height = 38, x = 0, y = -24, span = 180, fontSize = 14,
  bgMode = "gradient",              -- "solid" or "gradient"
  bgSolid  = { 0.00, 0.00, 0.00, 0.55 },
  bgCenter = { 0.10, 0.10, 0.12, 0.90 },
  bgEdge   = { 0.00, 0.00, 0.00, 0.00 },
  textColor     = { 1.00, 1.00, 1.00, 1.00 },
  cardinalColor = { 1.00, 0.82, 0.00, 1.00 },
  northColor    = { 1.00, 0.96, 0.85, 1.00 },
  tickColor     = { 1.00, 1.00, 1.00, 0.55 },
  markerColor   = { 1.00, 0.82, 0.00, 1.00 },
  degreeColor   = { 1.00, 1.00, 1.00, 1.00 },
  showDegrees = false, flipTicks = false, degreeInline = true, showIntercardinals = true, showTicks = true, fadeEdges = true,
  locked = true,
  fontName = "Default (Game Font)", fontPath = "",   -- "" means the game default
  fadeAmount = 0.50,   -- fraction of the half-width over which edges fade
  bgOpacity = 1.0,     -- master multiplier for all background alpha
  themes = {},         -- user-saved themes: name -> snapshot
  markerStyle = "short",   -- "short" line over the tick area, or "notch" triangle (no full-height line)
  outlineWidth = 0,    -- text outline thickness in pixels (0 = off, the default)
  outlineColor = { 0.00, 0.00, 0.00, 1.00 },   -- outline color; its alpha is multiplied by the text's own alpha
  scanlines = true,    -- thin dark lines over the bar background and inside the XP tooltip (not part of themes)
  tipAuto = true,      -- XP tooltip colors follow the theme; off uses the tip* colors below (not part of themes)
  tipBg = { 0.05, 0.05, 0.07, 1 }, tipEdge = { 1, 0.82, 0, 1 }, tipAccent = { 1, 0.82, 0, 1 },
  tipTitle = { 1, 0.82, 0, 1 }, tipText = { 0.95, 0.95, 0.95, 1 },
  tipGood = { 0.45, 0.95, 0.50, 1 }, tipRest = { 0.40, 0.65, 1, 1 },
  showNumbers = false, -- the 30 / 60 / 120 ... degree labels between the letters (off by default)
  -- Experience: a soft wash of the XP color behind the compass.
  xpBar = true,        -- show the XP fill; also enables the hover XP tooltip
  xpPulse = true,      -- the fill pulses brighter/warmer when XP is gained
  xpColor = { 0.58, 0.00, 0.55, 1.00 },
  edgeLines = true,    -- thin glowing line along the top and bottom edges, fading out toward both ends
  edgeColor = { 0.90, 0.75, 0.30, 0.90 },
  xpFillMode = "left",         -- "left" (left to right), "edges" (both edges inward) or "center" (middle outward)
  xpFillStyle = "fadeCenter",  -- "fadeCenter", "fadeBottom", "fadeTop", "band" or "full"
  xpFillStrength = 0.30,       -- opacity multiplier for the wash and its leading edge
  xpWave = true,               -- the leading edge ripples like liquid; /chud xpwave turns it off and on
  -- Markers (the menu that opens when you click the compass)
  mk_tracked = true,       -- tracked quest / waypoint
  mk_objectives = true,    -- quest objectives and turn-ins on this map
  mk_givers = false,       -- quests you can pick up
  mk_rares = false, mk_treasures = false,
  mk_corpse = true, mk_gm2 = true, mk_gm2data = true, mk_gl = true, mk_gmFilter = true, mk_gnext = true, mk_gnextOnly = true, mk_partySmooth = true,        -- your corpse, while you are a ghost
  -- Fading (see Fade.lua). Off by default; these are not part of a theme.
  fadeOn = false,          -- fade the bar out when none of the "show when" situations apply
  fadeCombat = false, fadeMap = true, fadeMouse = true, fadeRun = true, fadeAuto = false, fadeDead = true,   -- when to show it
  tourDone = false,        -- the setup tour has been shown or skipped (Install.lua)
  masterAlpha = 1,         -- overall opacity of the bar, fading or not
  fadeAlpha = 0,           -- opacity while faded out
  mk_party = true,         -- party members (names show only when icons are outside the bar)
  mk_partyLimit = false,   -- true = party members obey Max Distance; false = shown at any distance
  mk_herbs = false, mk_ore = false, mk_containers = false,   -- recorded gathering spots
  mk_distance = true,      -- distance under the tracked marker
  mk_size = 16, mk_range = 500,
  mk_questie = true,       -- use Questie's icons for quests when Questie is installed
  mk_qRange = 600,         -- yards: Questie icons farther than this are hidden (the focused quest ignores it)
  mk_qFocusOnly = false,   -- show Questie icons only for the focused quest
  mk_areaGlow = true,      -- the focused quest's icon glows while you are inside that quest's area (if the client reports it)
  mk_rate = 24,            -- updates per second for close-up icons while you move (higher = smoother, a little more CPU)
  mk_giverRange = 300,     -- yards over which quest giver icons shrink and fade
  mk_objRange = 300,       -- yards over which quest objective icons shrink and fade
  mk_outside = true,       -- icons sit just outside the bar instead of inside its edge
  mk_depth = true,         -- icons get smaller the farther away they are (the focused icon is always the largest)
  mk_color = { 1.00, 0.82, 0.00, 1.00 },        -- icon color (themes set it from their accent)
  mk_shadowAlpha = 0.6, mk_shadowDist = 1.5,   -- icon drop shadow: opacity (0 = off) and distance in pixels
  mk_native = false,                            -- true = keep the game's own icon colors instead of mk_color
  nodes = {},              -- recorded gathering spots: nodes[kind][mapID] = { {x, y, name}, ... }
  hideBlizzXP = true,   -- hide the default Blizzard XP bar, since CHUD has its own (not part of themes or the group resets)
  rightClickMenu = true,   -- right-click the bar to open the marker/quick menu (it holds unlock, center and every marker option)
  glitchFx = true,     -- glitch/"broken HUD" effect in dungeons; off = plain fade
  optimize = true,     -- low-CPU rendering (skips redundant updates)
}

-- Deep copy of a value (tables are copied recursively), so defaults are never shared with saved settings.
local function Copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = Copy(x) end
  return t
end
ns.Copy = Copy

-- Self-profiler. /chud debug perf starts timing; run it again to print, for each wrapped function, how many
-- times it ran and the time it took. Wrapped functions cost one boolean check while profiling is off.
local perf = { on = false, t0 = 0, rows = {} }
-- Wraps fn so its calls and time are counted for the performance report; returns the wrapped function.
function ns.Perf(name, fn)
  local row = { name = name, calls = 0, ms = 0 }
  perf.rows[#perf.rows + 1] = row
  return function(...)
    if not perf.on then return fn(...) end
    local t = debugprofilestop()
    local a, b, c = fn(...)
    row.calls = row.calls + 1; row.ms = row.ms + (debugprofilestop() - t)
    return a, b, c
  end
end
-- Turns the performance counters on or off.
function ns.PerfToggle()
  if not perf.on then
    for _, r in ipairs(perf.rows) do r.calls, r.ms = 0, 0 end
    perf.on, perf.t0 = true, GetTime()
    print("CHUD: profiling started. Play normally for a minute, then run /chud debug perf again.")
    return
  end
  perf.on = false
  local secs = math.max(1, GetTime() - perf.t0)
  print(format("CHUD: results over %.0f seconds (time is only what CHUD's own code used)", secs))
  for _, r in ipairs(perf.rows) do
    if r.calls > 0 then
      print(format("  %-12s %6d calls  %7.1f ms total  %.4f ms/call  %.3f ms/sec", r.name, r.calls, r.ms, r.ms / r.calls, r.ms / secs))
    end
  end
  collectgarbage("collect")
  if UpdateAddOnMemoryUsage then
    UpdateAddOnMemoryUsage()
    print(format("  memory after a garbage collection: %.0f KB", GetAddOnMemoryUsage("CHUD")))
  end
end

local db
local floor, abs, min, deg = math.floor, math.abs, math.min, math.deg

-- Frames ---------------------------------------------------------------------
local root = CreateFrame("Frame", "CHUDFrame", UIParent)
root:SetFrameStrata("MEDIUM")
root:SetClampedToScreen(true)
root:SetMovable(true)
root:RegisterForDrag("LeftButton")

-- The strip clips its children so labels/ticks vanish at the bar edges.
local strip = CreateFrame("Frame", nil, root)
strip:SetAllPoints(root)
strip:SetClipsChildren(true)

-- Ticks and letters live in `content`, so glitch effects can fade/jitter/hide them as a group
-- without touching the background, edge lines or XP fill.
local content = CreateFrame("Frame", nil, strip)
content:SetAllPoints(strip)
ns.root, ns.strip = root, strip   -- used by Markers.lua and Settings.lua

-- Background is four segments (left/right x inner/outer) so the outer part can fade to
-- transparent over a configurable distance while the inner part keeps its color.
local function NewBG()
  local t = strip:CreateTexture(nil, "BACKGROUND")
  t:SetColorTexture(1, 1, 1, 1)
  return t
end
-- Children draw above their parent's own regions, so anything that must sit on top of
-- the strip (marker, degree number, unlock tint) lives on an overlay frame above it.
local overlay = CreateFrame("Frame", nil, root)
overlay:SetAllPoints(root)
overlay:SetFrameLevel(strip:GetFrameLevel() + 5)

local bgLin, bgLout, bgRin, bgRout = NewBG(), NewBG(), NewBG(), NewBG()
-- Scanlines: one static dark tile layer per background piece, with the same alpha ramp as that piece so the
-- lines fade out with the background. Static, so they cost nothing per frame.
local function NewScan()
  local t = strip:CreateTexture(nil, "BACKGROUND", nil, 1)
  t:SetTexture("Interface\\AddOns\\CHUD\\media\\scan.tga", "REPEAT", "REPEAT")
  return t
end
local scanPieces = { { NewScan(), bgLin }, { NewScan(), bgRin }, { NewScan(), bgLout }, { NewScan(), bgRout } }
-- Slow downward drift, same speed as the tooltip's. Runs while scanlines are on. It only moves the texture coordinates of four
-- textures, so Low-CPU Rendering does not stop it; that setting just slows its updates a little.
local scanOff, scanAcc = 0, 0
local scanDrift = CreateFrame("Frame")
scanDrift:SetScript("OnUpdate", function(_, dt)
  local d = db
  if not d or d.scanlines == false then return end
  scanAcc = scanAcc + dt
  if scanAcc < (d.optimize and 0.05 or 0.03) then return end
  scanOff = (scanOff + scanAcc * 8 / 4) % 1
  scanAcc = 0
  for _, pc in ipairs(scanPieces) do
    if pc.w and pc[1]:IsShown() then pc[1]:SetTexCoord(0, pc.w / 16, -scanOff, pc.h / 4 - scanOff) end
  end
end)

-- Marker, notch and degree readout: the compass parts on the overlay. Same idea as `content`.
local contentTop = CreateFrame("Frame", nil, overlay)
contentTop:SetAllPoints(root)
ns.contentTop = contentTop   -- marker icons live here, above the letters and numbers

local unlockTint = overlay:CreateTexture(nil, "BACKGROUND")
unlockTint:SetAllPoints(); unlockTint:SetColorTexture(0.2, 1, 0.2, 0.18); unlockTint:Hide()

local marker = contentTop:CreateTexture(nil, "ARTWORK")
marker:SetWidth(2); marker:SetPoint("TOP"); marker:SetPoint("BOTTOM")
marker:SetColorTexture(1, 1, 1, 1)

-- Notch marker: a small triangle built from up to 7 one-pixel rows, base on the element edge.
local notch = {}
for i = 1, 7 do
  local t = contentTop:CreateTexture(nil, "ARTWORK", nil, 3)
  t:SetHeight(1); t:SetColorTexture(1, 1, 1, 1)
  notch[i] = t
end

-- Edge hairlines: a thin bright line plus a faint wider glow along the top and bottom edges. Each is
-- three pieces (fade in, solid middle, fade out) so both ends taper to nothing.
local edgeSets = {}
for _, side in ipairs({ "TOP", "BOTTOM" }) do
  local set = { line = {}, glow = {} }
  for i = 1, 3 do
    set.line[i] = overlay:CreateTexture(nil, "ARTWORK", nil, 0); set.line[i]:SetColorTexture(1, 1, 1, 1)
    set.glow[i] = overlay:CreateTexture(nil, "BACKGROUND", nil, 2); set.glow[i]:SetColorTexture(1, 1, 1, 1)
  end
  edgeSets[side] = set
end

-- Positions the segments of one edge line (top or bottom) of the bar.
local function PlaceEdge(segs, side, h, fw, c, a)
  local opp = (side == "TOP") and "BOTTOM" or "TOP"
  local sy = (side == "TOP") and -h or h
  local r, g, b = c[1], c[2], c[3]
  local A, B, Cc = segs[1], segs[2], segs[3]
  A:ClearAllPoints(); A:SetPoint(side .. "LEFT", root, side .. "LEFT", 0, 0); A:SetPoint(opp .. "RIGHT", root, side .. "LEFT", fw, sy)
  A:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, a))
  B:ClearAllPoints(); B:SetPoint(side .. "LEFT", root, side .. "LEFT", fw, 0); B:SetPoint(opp .. "RIGHT", root, side .. "RIGHT", -fw, sy)
  B:SetColorTexture(r, g, b, a)
  Cc:ClearAllPoints(); Cc:SetPoint(side .. "LEFT", root, side .. "RIGHT", -fw, 0); Cc:SetPoint(opp .. "RIGHT", root, side .. "RIGHT", 0, sy)
  Cc:SetGradient("HORIZONTAL", CreateColor(r, g, b, a), CreateColor(r, g, b, 0))
  for i = 1, 3 do segs[i]:Show() end
end

-- Shows or hides the top and bottom edge lines and sizes them to the bar.
function ns.UpdateEdges()
  if not db then return end
  local on = db.edgeLines
  local half = db.width / 2
  local fz = db.fadeEdges and math.max(0.15, math.min(1, db.fadeAmount)) or 0.3
  local fw = math.max(1, half * fz)
  local c = db.edgeColor
  for side, set in pairs(edgeSets) do
    if on then
      PlaceEdge(set.line, side, 1, fw, c, c[4])
      PlaceEdge(set.glow, side, 4, fw, c, c[4] * 0.2)
    else
      for i = 1, 3 do set.line[i]:Hide(); set.glow[i]:Hide() end
    end
  end
end

-- XP as a background fill: a soft wash of the XP color from the left edge to the XP fraction, with a
-- brighter leading edge. It lives on the strip (below the ticks and letters). Because the wash follows
-- the same edge fade as the background, each piece is laid out by hand: the linear fade means a
-- clipped piece is just a gradient between two known alpha values.
-- Wash textures per side: w[slice][piece] (3 pieces x up to MAX_SLICES vertical slices), plus a head glow
-- and head line. The fade styles stack many thin bands of changing opacity; 16 of them keep the steps
-- smaller than the eye can pick out on a normal bar height.
local MAX_SLICES = 16
local bf = { {}, {} }
for side = 1, 2 do
  local t = { w = {} }
  local function tex(level)
    local x = strip:CreateTexture(nil, "BACKGROUND", nil, level); x:SetColorTexture(1, 1, 1, 1); x:Hide(); return x
  end
  for k = 1, MAX_SLICES do t.w[k] = { tex(1), tex(1), tex(1) } end
  t.glow, t.line = tex(1), tex(1)
  t.wave = {}   -- the leading edge cut into thin slices that ripple sideways (see the wave driver below)
  for k = 1, 12 do t.wave[k] = tex(1) end
  bf[side] = t
end
local waveState   -- the leading edge's layout while it ripples: { lead, xh, edge, boxes = { [side] = box } }
local bfState   -- layout the repaint needs: { W, fw, x1, x2, lead, sides, slices = { {y1, y2, mult}... } }

-- The "Fade From Top" style grows the fill down from the top edge; every other style starts at the bottom.
function ns.XPAtTop() return db.xpFillStyle == "fadeTop" end

local function BackfadeAt(x)   -- 0..1 edge-fade factor at x pixels from the left (or, mirrored, the right)
  if not bfState or bfState.fw <= 0 then return 1 end
  return math.max(0, math.min(1, math.min(x, bfState.W - x) / bfState.fw))
end

-- Pieces of the fill: the part inside the left fade zone, the middle, and the part inside the right fade
-- zone. Each is a gradient between the (linear) fade alphas at its two ends, so clipping is exact.
local function Pieces(st)
  local W, fw, x1, x2 = st.W, st.fw, st.x1, st.x2
  local zones = (fw > 0) and { { 0, fw }, { fw, W - fw }, { W - fw, W } } or { false, { 0, W }, false }
  local out = {}
  for i = 1, 3 do
    local z = zones[i]
    if z then
      local p1, p2 = math.max(x1, z[1]), math.min(x2, z[2])
      if p2 > p1 then out[i] = { p1, p2 } end
    end
  end
  return out
end

-- Paints the XP fill behind the bar in color c for the current fill state.
local function PaintBackfill(c)
  local st = bfState
  if not st then return end
  local strength = db.xpFillStrength or 0.3
  local r, g, b, a = c[1], c[2], c[3], c[4] * strength
  local fw = st.fw
  local function fadeA(x) return a * ((fw > 0) and math.max(0, math.min(1, math.min(x, st.W - x) / fw)) or 1) end
  local pieces = Pieces(st)
  local xh = (st.lead == "right") and st.x2 or st.x1
  local hv = BackfadeAt(xh)
  for side = 1, st.sides do
    local t = bf[side]
    local function grad(tx, a1, a2)   -- alphas from lower x to higher x, flipped on the mirrored side
      if side == 2 then a1, a2 = a2, a1 end
      tx:SetGradient("HORIZONTAL", CreateColor(r, g, b, a1), CreateColor(r, g, b, a2))
    end
    for k = 1, #st.slices do
      local m = st.slices[k][3]
      for i = 1, 3 do
        if pieces[i] then grad(t.w[k][i], fadeA(pieces[i][1]) * m, fadeA(pieces[i][2]) * m) end
      end
    end
    -- The leading edge is brighter than the wash, scaled with the same strength so the slider tones both.
    local glowA = math.min(1, a * 1.6 * hv)
    if st.lead == "right" then grad(t.glow, 0, glowA) else grad(t.glow, glowA, 0) end
    local lineA = math.min(1, c[4] * strength * 2.2 * hv)
    t.line:SetColorTexture(r, g, b, lineA)
    for k = 1, #t.wave do t.wave[k]:SetColorTexture(r, g, b, lineA) end
  end
end

-- Hides every slice of the XP fill.
local function HideBackfill()
  for side = 1, 2 do
    local t = bf[side]
    for k = 1, MAX_SLICES do for i = 1, 3 do t.w[k][i]:Hide() end end
    t.glow:Hide(); t.line:Hide()
    for k = 1, #t.wave do t.wave[k]:Hide() end
  end
  bfState = nil
  waveState = nil
end

-- Sizes and places the XP fill for the current XP; hides it when the XP bar is off or you are at max level.
local function LayoutBackfill(cur, mx, isMax)
  local W, H = db.width, db.height
  if not db.xpBar or isMax then HideBackfill(); return false end
  local F = db.fadeEdges and math.max(0.02, math.min(1, db.fadeAmount)) or 0
  local fw = (W / 2) * F
  local mode = db.xpFillMode
  local frac = cur / mx
  local st = { W = W, fw = fw, sides = 2, lead = "right" }
  if mode == "edges" then          -- both edges toward the middle
    st.x1, st.x2 = 0, math.max(2, W / 2 * frac)
  elseif mode == "center" then     -- from the middle out to both edges
    st.x1, st.x2, st.lead = W / 2 - math.max(2, W / 2 * frac), W / 2, "left"
  elseif mode == "up" or mode == "down" then   -- the whole width rises (or drops) like a liquid level
    st.x1, st.x2, st.sides, st.vertical = 0, W, 1, true
  else                             -- left to right
    st.x1, st.x2, st.sides = 0, math.max(2, W * frac), 1
  end

  -- Vertical shape. Each band is {y1, y2, opacity multiplier}, measured from the origin edge (the
  -- bottom, or the top for "Fade From Top"). The leading edge gets its own height range.
  local style = db.xpFillStyle
  if style ~= "fadeBottom" and style ~= "fadeTop" and style ~= "fadeCenter" and style ~= "band" and style ~= "full" then
    style = "fadeCenter"   -- unset, or a removed style
  end
  -- Stacks MAX_SLICES thin bands whose opacity follows shape(pos), pos = 0..1 across the bar height
  -- from the origin edge. Normalized so the strongest band keeps full opacity.
  local function Bands(shape)
    local out, peak = {}, 0
    for k = 1, MAX_SLICES do
      local m = shape((k - 0.5) / MAX_SLICES)
      peak = math.max(peak, m)
      out[k] = { (k - 1) * H / MAX_SLICES, k * H / MAX_SLICES, m }
    end
    for k = 1, MAX_SLICES do out[k][3] = out[k][3] / peak end
    return out
  end
  local bands, edge = {}, { 0, H * 0.6 }
  if style == "band" then
    bands[1] = { 0, H * 0.4, 1 }; edge = { 0, H * 0.4 }
  elseif style == "full" then
    bands[1] = { 0, H, 1 }; edge = { 0, H }
  elseif style == "fadeCenter" then
    -- Strongest in the middle, fading toward both the top and the bottom.
    bands = Bands(function(pos) return (1 - math.abs(pos - 0.5) / 0.5) ^ 1.6 end)
    edge = { H * 0.2, H * 0.8 }
  else   -- fadeBottom / fadeTop: falls away from the origin edge
    bands = Bands(function(pos) return (1 - pos) ^ 1.6 end)
  end
  if st.vertical then
    -- Bottom-to-top / top-to-bottom: one wash up to the XP level, plus a brighter line at its leading edge.
    local level = math.max(2, H * frac)
    bands = { { 0, level, 1 }, { math.max(0, level - 2), level, 2.4 } }
  end
  st.slices = bands

  bfState = st
  waveState = nil

  local pieces = Pieces(st)
  local xh = (st.lead == "right") and st.x2 or st.x1
  local hw = math.min(st.x2 - st.x1, math.max(8, W * 0.06))
  local bottom = not ns.XPAtTop()
  if st.vertical then bottom = (mode == "up") end   -- "up" starts at the bottom edge, "down" at the top
  local vy, vo = bottom and "BOTTOM" or "TOP", bottom and "TOP" or "BOTTOM"
  local sg = bottom and 1 or -1
  for side = 1, 2 do
    local t = bf[side]
    if side > st.sides then
      for k = 1, MAX_SLICES do for i = 1, 3 do t.w[k][i]:Hide() end end
      t.glow:Hide(); t.line:Hide()
      for k = 1, #t.wave do t.wave[k]:Hide() end
    else
      local function box(tx, x1, x2, y1, y2)
        tx:ClearAllPoints()
        if side == 1 then
          tx:SetPoint(vy .. "LEFT", strip, vy .. "LEFT", x1, sg * y1)
          tx:SetPoint(vo .. "RIGHT", strip, vy .. "LEFT", x2, sg * y2)
        else   -- measured from the right edge instead
          tx:SetPoint(vy .. "RIGHT", strip, vy .. "RIGHT", -x1, sg * y1)
          tx:SetPoint(vo .. "LEFT", strip, vy .. "RIGHT", -x2, sg * y2)
        end
        tx:Show()
      end
      for k = 1, MAX_SLICES do
        for i = 1, 3 do
          local tx = t.w[k][i]
          local band = bands[k]
          if band and pieces[i] then box(tx, pieces[i][1], pieces[i][2], band[1], band[2]) else tx:Hide() end
        end
      end
      if st.vertical then
        t.glow:Hide(); t.line:Hide()   -- the level line is the second band instead
      elseif st.lead == "right" then
        box(t.glow, xh - hw, xh, edge[1], edge[2]); box(t.line, math.max(0, xh - 2), xh, edge[1], edge[2])
      else
        box(t.glow, xh, xh + hw, edge[1], edge[2]); box(t.line, xh, xh + 2, edge[1], edge[2])
      end
      -- The ripple replaces the straight line with slices that the wave driver moves. Off: the plain line stays.
      if db.xpWave ~= false and not st.vertical then
        t.line:Hide()
        waveState = waveState or { lead = st.lead, xh = xh, edge = edge, boxes = {} }
        waveState.boxes[side] = box
      else
        for k = 1, #t.wave do t.wave[k]:Hide() end
      end
    end
  end
  PaintBackfill(db.xpColor)
  return true
end

-- The wave driver: about 30 times a second each slice of the leading edge is moved a little sideways by two sine waves
-- (one slow, one quick), so the edge ripples like the surface of a liquid. Nothing runs while the XP fill is hidden.
-- To remove the effect, delete this block and the waveState lines above (or run /chud xpwave to turn it off).
local waveAcc, waveT = 0, 0
local waveFrame = CreateFrame("Frame")
waveFrame:SetScript("OnUpdate", function(_, dt)
  local w = waveState
  if not w then return end
  waveAcc = waveAcc + dt
  if waveAcc < 0.033 then return end
  waveT, waveAcc = waveT + waveAcc, 0
  local y0 = w.edge[1]
  local step = (w.edge[2] - w.edge[1]) / 12
  for side, box in pairs(w.boxes) do
    local t = bf[side]
    for k = 1, 12 do
      local off = (math.sin(waveT * 2.4 + k * 0.85) + 0.5 * math.sin(waveT * 4.1 - k * 1.7)) * 1.0
      local a = math.max(0, w.xh + off - (w.lead == "right" and 2 or 0))
      box(t.wave[k], a, a + 2, y0 + (k - 1) * step, y0 + k * step)
    end
  end
end)

local xpDemo   -- when set, XPInfo reports fake progress: { t = seconds elapsed, nextPulse = fraction }
-- Level, current XP, XP needed and whether you are at max level (fake values while the demo runs).
local function XPInfo()
  if xpDemo then return UnitLevel("player"), math.floor(xpDemo.t / 10 * 100000), 100000, false end
  local level, cur, mx = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
  local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
  local isMax = level >= maxLevel or not mx or mx == 0
  return level, cur, mx, isMax
end

-- Hovering anywhere on the compass opens the XP tooltip. The frame sits under the marker icons (so they
-- keep their own tooltips) and forwards dragging and right-clicks to the compass itself.
local xpHover = CreateFrame("Frame", nil, root)
xpHover:SetAllPoints(root)
xpHover:EnableMouse(true)
xpHover:RegisterForDrag("LeftButton")
xpHover:Hide()

-- Refreshes the XP bar, its fill and its hover area.
function ns.UpdateXP()
  if not db then return end
  xpHover:SetShown(db.xpBar)
  local _, cur, mx, isMax = XPInfo()
  LayoutBackfill(cur, mx, isMax)
end

ns.UpdateXP = ns.Perf("UpdateXP", ns.UpdateXP)

-- XP gain pulse -----------------------------------------------------------------------------
-- When XP goes up the fill briefly turns 20% brighter and a little warmer (hue nudged toward
-- orange), then eases back to its normal color. Only colors are repainted (no re-layout), and the
-- frame that drives it hides itself afterwards, so there is no cost while idle.
local function RGB2HSV(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d, h = mx - mn, 0
  if d > 0 then
    if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    h = h * 60
  end
  return h, (mx == 0) and 0 or d / mx, mx
end
-- Converts hue (0-360), saturation and value (0-1) to red, green and blue.
local function HSV2RGB(h, sat, v)
  local c = v * sat
  local x = c * (1 - abs((h / 60) % 2 - 1))
  local m = v - c
  local r, g, b
  if h < 60 then r, g, b = c, x, 0 elseif h < 120 then r, g, b = x, c, 0 elseif h < 180 then r, g, b = 0, c, x
  elseif h < 240 then r, g, b = 0, x, c elseif h < 300 then r, g, b = x, 0, c else r, g, b = c, 0, x end
  return r + m, g + m, b + m
end

local PULSE_RISE, PULSE_FALL, PULSE_BRIGHT, PULSE_WARM = 0.12, 0.88, 0.26, 10   -- seconds; luminance added (0-1); hue degrees
local pulseFrame, pulseT = CreateFrame("Frame"), 0
pulseFrame:Hide()
pulseFrame:SetScript("OnUpdate", function(self, elapsed)
  pulseT = pulseT + elapsed
  local base = db.xpColor
  if pulseT >= PULSE_RISE + PULSE_FALL then
    self:Hide(); PaintBackfill(base); return
  end
  local k = (pulseT < PULSE_RISE) and (pulseT / PULSE_RISE) or (1 - (pulseT - PULSE_RISE) / PULSE_FALL) ^ 1.5
  local h, sat, v = RGB2HSV(base[1], base[2], base[3])
  -- Warmer = toward orange (about 30 degrees), by the shortest way round the hue wheel.
  local diff = ((30 - h + 180) % 360) - 180
  h = h + math.max(-PULSE_WARM, math.min(PULSE_WARM, diff)) * k
  local r, g, b = HSV2RGB(h % 360, sat, v)
  -- Brightness is added by mixing toward white until the color's luminance has risen by
  -- PULSE_BRIGHT. (Raising HSV "value" fails for colors that are already near full value, and the
  -- hue shift alone can lower luminance, which made the pulse look darker.)
  local lumBase = 0.2126 * base[1] + 0.7152 * base[2] + 0.0722 * base[3]
  local lumNow = 0.2126 * r + 0.7152 * g + 0.0722 * b
  local want = math.min(1, lumBase + PULSE_BRIGHT)
  local t = (want > lumNow) and (want - lumNow) / (1 - lumNow) * k or 0
  r, g, b = r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t
  PaintBackfill({ r, g, b, base[4] })
end)

local lastLevel, lastXP

-- /chud debug xpdemo: fills the XP bar from 0 to 100% over 10 seconds (pulsing every 10%) so themes can be
-- checked without earning XP. Real XP is untouched; the display returns to normal afterwards.
local demoFrame = CreateFrame("Frame")
demoFrame:Hide()
demoFrame:SetScript("OnUpdate", function(self, elapsed)
  if not xpDemo then self:Hide(); return end
  xpDemo.t = xpDemo.t + elapsed
  if xpDemo.t >= 10 then
    xpDemo = nil; self:Hide(); ns.UpdateXP(); return
  end
  if db.xpPulse and xpDemo.t / 10 >= xpDemo.nextPulse then
    xpDemo.nextPulse = xpDemo.nextPulse + 0.1; pulseT = 0; pulseFrame:Show()
  end
  ns.UpdateXP()
end)
-- Runs a short fake XP gain to preview the XP bar effects.
function ns.XPDemo()
  if not db then return end
  if not db.xpBar then print("CHUD: turn on the XP bar first (XP Bar + Hover Tooltip)."); return end
  xpDemo = { t = 0, nextPulse = 0.1 }
  demoFrame:Show()
end
-- Notices real XP gains and level-ups and starts the matching bar effects.
-- Monster-kill experience for the tooltip's XP/h line, read from the game's "X dies, you gain N experience" messages so quests,
-- exploration and other XP are left out. Only the last 10 minutes count.
local XP_WINDOW = 600
local kills, sessStart = {}, nil   -- kills = { { time, xp }, ... } oldest first
local killPattern                  -- the game's own kill message turned into a Lua pattern, so it works in any language
-- Records the XP from one chat message, if it is a kill.
local function NoteKillXP(msg)
  if type(msg) ~= "string" then return end
  if not killPattern then
    local fmt = COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."
    killPattern = "^" .. fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
  end
  local who, xp = msg:match(killPattern)
  xp = tonumber(xp)
  if xp and xp > 0 then kills[#kills + 1] = { GetTime(), xp } end
  if who and ns.NoteRareKill then ns.NoteRareKill(nil, who) end   -- a rare that gave XP counts as killed
end
-- Kill XP per hour over the last 10 minutes (or since the game loaded, if that is shorter), or nil until there is a kill in
-- that time and at least a minute has passed.
function ns.XPPerHour()
  if not sessStart then return nil end
  local now = GetTime()
  while kills[1] and now - kills[1][1] > XP_WINDOW do table.remove(kills, 1) end
  local span = min(XP_WINDOW, now - sessStart)
  if #kills == 0 or span < 60 then return nil end
  local sum = 0
  for i = 1, #kills do sum = sum + kills[i][2] end
  return sum / span * 3600
end

local function CheckXPGain()
  if not db then return end
  if xpDemo then return end   -- demo values are fake; never treat them as a real gain
  local level, cur, _, isMax = XPInfo()
  sessStart = sessStart or GetTime()
  if not isMax and db.xpBar and db.xpPulse and lastXP and (level > lastLevel or (level == lastLevel and cur > lastXP)) then
    pulseT = 0; pulseFrame:Show()
  end
  lastLevel, lastXP = level, cur
end

-- Plays the pulse on demand (used when the option is switched on, and by the XP demo).
function ns.PreviewXPPulse()
  if db and db.xpBar then pulseT = 0; pulseFrame:Show() end
end

local degOut = {}   -- outline copies of the degree readout (filled in once MakeOutline exists, below)
local degText = contentTop:CreateFontString(nil, "OVERLAY")
degText:SetFont(STANDARD_TEXT_FONT, 14, "")

-- Notice shown in place of the compass when facing data is unavailable (e.g. inside dungeons).
local disabledText = overlay:CreateFontString(nil, "OVERLAY")
disabledText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
disabledText:SetPoint("CENTER", root, "CENTER", 0, 0)
disabledText:Hide()
degText:SetPoint("TOP", root, "BOTTOM", 0, -2)

-- Ticks every 5 degrees, labels every 15 degrees.
local ticks, labels = {}, {}
for d = 0, 355, 5 do
  local t = content:CreateTexture(nil, "ARTWORK")
  t:SetWidth(1); t:SetColorTexture(1, 1, 1, 1)
  ticks[#ticks + 1] = { tex = t, deg = d, major = (d % 15 == 0), shown = true }
end
-- Custom text outline. The game's own OUTLINE flag is always black and one fixed thickness, so
-- instead each text gets 8 copies of itself, offset around it in the outline color, drawn beneath.
-- Offsets scale with outlineWidth. Outline alpha = outlineColor alpha x the text's own alpha.
local function MakeOutline(parent)
  local o = {}
  for i = 1, 8 do
    -- BACKGROUND layer: the game always draws it beneath OVERLAY, so the outline can never cover the text.
    local f = parent:CreateFontString(nil, "BACKGROUND")
    f:SetFont(STANDARD_TEXT_FONT, 14, "")
    o[i] = f
  end
  return o
end
-- Sets the same text on all eight outline copies of a label.
local function SetOutlineText(o, text) for i = 1, 8 do o[i]:SetText(text) end end
degOut = MakeOutline(contentTop)

local LETTERS = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }
for d = 0, 345, 15 do
  local kind
  if d % 90 == 0 then kind = "cardinal" elseif d % 45 == 0 then kind = "inter" elseif d % 30 == 0 then kind = "number" end
  if kind then
    -- Each label is a tiny frame holding the text and its outline copies, so fading the label is
    -- one SetAlpha on the frame instead of nine.
    local lf = CreateFrame("Frame", nil, content)
    lf:SetSize(1, 1)
    local o = MakeOutline(lf)
    local fs = lf:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", lf, "CENTER", 0, 0)
    fs:SetFont(STANDARD_TEXT_FONT, 14, "")  -- a font must be set before SetText
    local text = LETTERS[d] or tostring(d)
    fs:SetText(text); SetOutlineText(o, text)
    labels[#labels + 1] = { fs = fs, f = lf, o = o, deg = d, kind = kind, shown = true }
  end
end

-- Apply settings -------------------------------------------------------------
-- Applies the chosen font; falls back to the game font if the file is missing/invalid.
local function SetFontSafe(fs, size, flags)
  local path = (db.fontPath and db.fontPath ~= "") and db.fontPath or STANDARD_TEXT_FONT
  flags = flags or ""
  local ok = fs:SetFont(path, size, flags)
  if ok == false then fs:SetFont(STANDARD_TEXT_FONT, size, flags) end
end

-- Styles one text: font, color, alpha and the game's native outline. Native outline and fill are one
-- glyph, so fading the label fades both together (the old 8-copy outline darkened letters near the
-- faded edges). Native outlines are always black; width 1 = OUTLINE, 2 = THICKOUTLINE.
local function OutlineFlag()
  local w = db.outlineWidth or 0
  if w <= 0 then return "" end
  return w > 1 and "THICKOUTLINE" or "OUTLINE"
end
-- Applies font, size, color and alpha to a label.
local function StyleText(fs, o, size, c)
  SetFontSafe(fs, size, OutlineFlag())
  fs:SetTextColor(c[1], c[2], c[3], 1)
  fs:SetAlpha(c[4])           -- SetTextColor's alpha is ignored by FontStrings, so alpha goes here
  for i = 1, 8 do o[i]:Hide() end   -- legacy copies stay hidden
end

-- Disabled state + glitch effect ------------------------------------------------------------
-- Facing is unavailable inside dungeons. Entering: the compass glitches (flicker, sideways jitter,
-- static bars) and cuts out, then a notice flickers in and re-glitches every few seconds. Leaving:
-- the compass "reboots" with a flicker. Only the compass parts take part; the background, edge lines
-- and XP fill never do.
local disabledMsg, instMsg
local random = math.random
local fx = { mode = nil, t = 0, acc = 0, nextGlitch = 3, glitchEnd = nil }
local BREAK_TIME, BOOT_TIME, MSG_IN, FADE_TIME = 0.9, 0.7, 0.5, 0.45
local NOTICE_HOLD, NOTICE_FADE = 3, 1.2   -- seconds the notice stays solid, then fades out

local glitchBars = {}
for i = 1, 5 do
  local b = overlay:CreateTexture(nil, "OVERLAY", nil, 5)
  b:SetColorTexture(1, 1, 1, 1); b:Hide()
  glitchBars[i] = b
end
-- Hides the glitch static bars.
local function HideBars() for i = 1, #glitchBars do glitchBars[i]:Hide() end end

-- Thin horizontal "static" slices at random spots; strength 0..1 is how many show up.
local function ScatterBars(strength)
  -- Static slices take the theme's own colors: E/S/W, North, text and the edge line color.
  local pal = { db.cardinalColor, db.northColor, db.textColor, db.edgeColor }
  for i = 1, #glitchBars do
    local b = glitchBars[i]
    local c = pal[random(1, #pal)]
    if random() < strength * 0.7 then
      local w = random(16, math.max(32, floor(db.width * 0.35)))
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", root, "TOPLEFT", random(0, math.max(0, floor(db.width - w))), -random(0, math.max(0, floor(db.height - 3))))
      b:SetSize(w, random(1, 3))
      b:SetColorTexture(c[1], c[2], c[3], 0.15 + random() * 0.45)
      b:Show()
    else
      b:Hide()
    end
  end
end

-- Shakes the whole bar by up to this many pixels (glitch effect).
local function Jitter(amount)
  amount = floor(amount)
  local jx, jy = random(-amount, amount), random(-2, 2)
  content:ClearAllPoints()
  content:SetPoint("TOPLEFT", strip, "TOPLEFT", jx, jy)
  content:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", jx, jy)
end
-- Puts the bar content back in place after a jitter.
local function ResetJitter() content:ClearAllPoints(); content:SetAllPoints(strip) end

-- Random flicker level: fully on with probability pOn, otherwise dim or off.
local function Flicker(pOn)
  local r = random()
  if r < pOn then return 1 end
  if r < pOn + (1 - pOn) * 0.4 then return 0.35 end
  return 0
end

-- Advances the disable and enable glitch animation by one frame.
local function FXStep(elapsed)
  fx.t = fx.t + elapsed
  fx.acc = fx.acc + elapsed
  local mode = fx.mode
  if mode == "breaking" then
    if fx.t >= BREAK_TIME then                       -- cut out, show the notice
      HideBars(); ResetJitter()
      content:SetAlpha(1); contentTop:SetAlpha(1)
      content:Hide(); contentTop:Hide()
      fx.mode = "broken"; fx.t = 0; fx.acc = 0; fx.glitchEnd = nil
      fx.nextGlitch = MSG_IN + 2.5 + random() * 2.5
      disabledText:SetText(disabledMsg); disabledText:SetAlpha(0); disabledText:Show()
      return
    end
    if fx.acc >= 0.05 then
      fx.acc = 0
      local k = 1 - fx.t / BREAK_TIME                -- 1 -> 0: gets worse as it dies
      content:SetAlpha(Flicker(k * 0.6)); contentTop:SetAlpha(Flicker(k * 0.6))
      Jitter(6 + 10 * (1 - k))
      ScatterBars(1 - k * 0.3)
    end
  elseif mode == "broken" then
    -- Notice flickers in (glitch mode only), holds, then fades away so it is not a permanent distraction.
    if fx.t < MSG_IN and db.glitchFx then
      if fx.acc >= 0.05 then
        fx.acc = 0
        disabledText:SetAlpha(random() < fx.t / MSG_IN and 1 or 0.1)
      end
    elseif fx.t < MSG_IN + NOTICE_HOLD then
      disabledText:SetAlpha(1)
    elseif fx.t < MSG_IN + NOTICE_HOLD + NOTICE_FADE then
      disabledText:SetAlpha(1 - (fx.t - MSG_IN - NOTICE_HOLD) / NOTICE_FADE)
    else
      disabledText:Hide(); fx.mode = nil
    end
  elseif mode == "fadeout" then                       -- plain fade: compass out, notice in
    local k = fx.t / FADE_TIME
    if k >= 1 then
      content:SetAlpha(1); contentTop:SetAlpha(1); content:Hide(); contentTop:Hide()
      disabledText:SetAlpha(1)
      fx.mode = "broken"; fx.t = MSG_IN; fx.acc = 0
      return
    end
    content:SetAlpha(1 - k); contentTop:SetAlpha(1 - k); disabledText:SetAlpha(k)
  elseif mode == "fadein" then                        -- plain fade: notice out, compass in
    local k = fx.t / FADE_TIME
    if k >= 1 then
      content:SetAlpha(1); contentTop:SetAlpha(1); disabledText:Hide(); fx.mode = nil
      return
    end
    content:SetAlpha(k); contentTop:SetAlpha(k); disabledText:SetAlpha(1 - k)
  elseif mode == "booting" then
    if fx.t >= BOOT_TIME then                        -- done: fully back
      ResetJitter(); HideBars()
      content:SetAlpha(1); contentTop:SetAlpha(1)
      disabledText:Hide(); disabledText:ClearAllPoints(); disabledText:SetPoint("CENTER", root, "CENTER", 0, 0)
      fx.mode = nil
      return
    end
    if fx.acc >= 0.05 then
      fx.acc = 0
      local k = fx.t / BOOT_TIME                     -- 0 -> 1: steadier as it comes back
      content:SetAlpha(Flicker(k)); contentTop:SetAlpha(Flicker(k))
      Jitter(10 * (1 - k))
      ScatterBars((1 - k) * 0.8)
      if fx.t < 0.25 then disabledText:SetAlpha(random() < 0.4 and 1 or 0.1) else disabledText:Hide() end
    end
  end
end

-- Starts the glitch-out animation when the HUD gets disabled (in a dungeon, say).
local function StartBreaking()
  fx.mode = db.glitchFx and "breaking" or "fadeout"; fx.t = 0; fx.acc = 0
  content:Show(); contentTop:Show(); content:SetAlpha(1); contentTop:SetAlpha(1)
  disabledText:SetText(disabledMsg); disabledText:SetAlpha(0); disabledText:Show()
  if db.glitchFx then disabledText:Hide() end
end

-- Starts the glitch-in animation when the HUD comes back.
local function StartBooting()
  fx.mode = db.glitchFx and "booting" or "fadein"; fx.t = 0; fx.acc = 0
  HideBars(); ResetJitter()
  content:Show(); contentTop:Show(); content:SetAlpha(0); contentTop:SetAlpha(0)
  ns.Apply()   -- re-lay out the compass at the current bearing
end

-- Switches the HUD off with a message, or back on when msg is nil.
local function SetDisabled(msg)
  if msg == disabledMsg then return end
  local was = disabledMsg
  disabledMsg = msg
  if msg then
    if was then disabledText:SetText(msg) else StartBreaking() end   -- wording change vs. a new break
  else
    StartBooting()
  end
end

-- Works out whether the HUD must be disabled here (dungeons and raids).
local function UpdateInstance()
  local inInstance, itype = IsInInstance()
  if inInstance and (itype == "party" or itype == "scenario") then instMsg = "HUD Disabled In Dungeons"
  elseif inInstance and itype == "raid" then instMsg = "HUD Disabled In Raids"
  else instMsg = nil end
  -- instMsg only chooses the wording; OnUpdate disables the compass while facing is missing.
end

-- Prints what the game reports for the player's facing (a number, or a hidden "secret" value).
function ns.Debug()
  local f = GetPlayerFacing()
  local secret = issecretvalue and issecretvalue(f)
  local shown = secret and "SECRET" or ((type(f) == "number") and format("%.3f", f) or tostring(f))
  local inInstance, itype = IsInInstance()
  print("CHUD debug: facing =", shown, "(" .. type(f) .. ")", "| instance:", tostring(inInstance), tostring(itype),
    "| disabled:", tostring(disabledMsg))
  local level, cur, mx, isMax = XPInfo()
  print("CHUD debug: xp", cur, "/", mx, "level", level, "| max level:", tostring(isMax), "| tracked:", tostring(lastXP),
    "level", tostring(lastLevel), "| pulse on:", tostring(db.xpPulse), "bar on:", tostring(db.xpBar),
    "| pulsing:", tostring(pulseFrame:IsShown()))
end

-- Pixels the XP bar hangs above the element when it is flipped to the top. The element's own
-- rectangle does not include it, so without this the bar can end up above the screen edge.

local dirty = true
function ns.Redraw() dirty = true end   -- Markers.lua asks for a redraw when targets move
local Layout   -- forward declaration; defined below. Apply calls it directly (see end of Apply)
-- Default Blizzard XP bar -------------------------------------------------------------------
-- Frame names differ between client versions, so every known name is tried and missing ones are
-- skipped. The wider status-tracking container also holds the reputation bar, so it is only used
-- when no XP-specific frame exists. Frames CHUD hides are remembered so that showing the bar again
-- restores exactly those and nothing else.
local BLIZZ_XP_FRAMES = { "MainMenuExpBar", "MainStatusTrackingBarContainer" }
local BLIZZ_XP_FALLBACK = { "StatusTrackingBarManager" }
local blizzHidden, blizzHooked = {}, {}

-- The default Blizzard XP bar frames that exist on this client.
local function BlizzXPFrames()
  local found = {}
  for _, name in ipairs(BLIZZ_XP_FRAMES) do
    if _G[name] then found[#found + 1] = _G[name] end
  end
  if #found == 0 then
    for _, name in ipairs(BLIZZ_XP_FALLBACK) do
      if _G[name] then found[#found + 1] = _G[name] end
    end
  end
  return found
end

-- Hides or shows the default Blizzard XP bar to match the setting.
function ns.ApplyBlizzXP()
  if not db then return end
  for _, f in ipairs(BlizzXPFrames()) do
    if db.hideBlizzXP then
      if not blizzHooked[f] then
        blizzHooked[f] = true
        -- The game re-shows these bars on level-up and zone changes; hide them again when it does.
        f:HookScript("OnShow", function(self) if db.hideBlizzXP then blizzHidden[self] = true; self:Hide() end end)
      end
      if f:IsShown() then blizzHidden[f] = true; f:Hide() end
    elseif blizzHidden[f] or blizzHooked[f] then
      -- Anything this addon ever hid or watched comes back, even if the game (not this code) was the last to hide it.
      blizzHidden[f] = nil
      f:Show()
    end
  end
  -- (The game's own bar-layout functions are not called from here: running them from an addon taints the game's code, which
  -- later blocks protected actions such as the Edit Mode party-frame setup.)
end
-- True when a default XP bar exists on this client.
function ns.BlizzXPFound() return #BlizzXPFrames() > 0 end

-- Applies every setting to the bar: size, position, fonts, colors and effects.
function ns.Apply()
  if not db then return end
  ns.ApplyBlizzXP()
  root:SetSize(db.width, db.height)
  root:ClearAllPoints()
  root:SetPoint("TOP", UIParent, "TOP", db.x, math.min(db.y, 0))   -- never above the top of the screen

  for _, l in ipairs(labels) do
    local size = db.fontSize
    if l.kind == "cardinal" then size = size + 4 elseif l.kind == "number" then size = size - 3 end
    -- Color/alpha/outline are set here once; per-frame edge fading only touches the label frame's alpha.
    local c = db.textColor
    if l.kind == "cardinal" then c = (l.deg == 0) and db.northColor or db.cardinalColor end
    StyleText(l.fs, l.o, math.max(size, 6), c)
    l.f:ClearAllPoints()   -- Layout re-anchors with the same point name, so it never needs to clear
    l.alpha = nil
  end
  -- Collision avoidance: a degree number sits 15 degrees from its neighbouring NE/SE/SW/NW letter.
  -- When that gap (in pixels) is too small for the two strings, hide the number rather than let
  -- them touch. Depends on width, visible degrees and font size, so it is decided here, not per frame.
  local gap = 15 * (db.width / db.span)
  for _, l in ipairs(labels) do
    l.suppress = false
    if l.kind == "number" and db.showIntercardinals then
      for _, r in ipairs(labels) do
        if r.kind == "inter" then
          local dd = abs(((l.deg - r.deg + 540) % 360) - 180)
          if dd <= 15 and gap < (l.fs:GetStringWidth() + r.fs:GetStringWidth()) / 2 + 5 then l.suppress = true end
        end
      end
    end
  end
  -- Inline: number sits inside the top of the bar and the marker starts below it.
  local inline = db.showDegrees and db.degreeInline
  local degSize = inline and math.max(db.fontSize - 3, 6) or db.fontSize
  StyleText(degText, degOut, degSize, db.degreeColor)
  SetFontSafe(disabledText, db.fontSize + 2, (db.outlineWidth or 0) > 0 and "OUTLINE" or ""); disabledText:SetTextColor(unpack(db.textColor))
  degText:ClearAllPoints()
  if inline and db.flipTicks then
    degText:SetPoint("BOTTOM", root, "BOTTOM", 0, 2)   -- ticks are on top, so number goes at the bottom
  elseif inline then
    degText:SetPoint("TOP", root, "TOP", 0, -2)
  else
    degText:SetPoint("TOP", root, "BOTTOM", 0, -2)   -- readout sits just below the element
  end
  root:SetHitRectInsets(0, 0, 0, 0)
  -- Center marker: a short line over the tick area, or a small triangular notch. Both sit on
  -- the tick edge, so neither runs through the letters.
  local atTop = db.flipTicks
  local edge = atTop and "TOP" or "BOTTOM"
  marker:ClearAllPoints()
  if db.markerStyle == "notch" then
    marker:Hide()
    local n = math.max(3, math.min(7, math.floor(db.height * 0.18 + 0.5)))
    local c = db.markerColor
    for r = 1, 7 do
      local t = notch[r]
      if r <= n then
        t:ClearAllPoints()
        t:SetWidth(2 * (n - r) + 1)                     -- widest row on the edge, narrowing to a point
        t:SetPoint(edge, root, edge, 0, atTop and -(r - 1) or (r - 1))
        t:SetColorTexture(c[1], c[2], c[3], c[4]); t:Show()
      else
        t:Hide()
      end
    end
  else
    for r = 1, 7 do notch[r]:Hide() end
    marker:SetPoint(edge, root, edge, 0, 0)
    marker:SetHeight(db.height * 0.34)
    marker:SetColorTexture(unpack(db.markerColor)); marker:Show()
  end
  degText:SetShown(db.showDegrees)
  if not db.showDegrees then for i = 1, 8 do degOut[i]:Hide() end end

  for _, t in ipairs(ticks) do
    t.tex:ClearAllPoints()
    t.alpha = nil
    t.tex:SetColorTexture(unpack(db.tickColor))
    t.tex:SetHeight(db.height * (t.major and 0.30 or 0.15))
  end
  marker:SetColorTexture(unpack(db.markerColor))

  -- Background. t = 0 at the center, 1 at the outer edge. Colors lerp center -> edge;
  -- with fade on, alpha additionally ramps to 0 over the outer fadeAmount of each half.
  local half = db.width / 2
  local F = db.fadeEdges and math.max(0.02, math.min(1, db.fadeAmount)) or 0
  local op = db.bgOpacity
  local cC, cE = db.bgCenter, db.bgEdge
  if db.bgMode == "solid" then cC, cE = db.bgSolid, db.bgSolid end
  local function lerp(t) -- color at fraction t of the way from center to edge
    return { cC[1] + (cE[1] - cC[1]) * t, cC[2] + (cE[2] - cC[2]) * t,
             cC[3] + (cE[3] - cC[3]) * t, cC[4] + (cE[4] - cC[4]) * t }
  end
  local function grad(tex, c1, m1, c2, m2)
    tex:SetGradient("HORIZONTAL", CreateColor(c1[1], c1[2], c1[3], c1[4] * m1),
                                  CreateColor(c2[1], c2[2], c2[3], c2[4] * m2))
  end
  local inner = (1 - F) * half
  local mid = lerp(1 - F)
  local edgeMul = (F > 0) and 0 or op

  bgLin:ClearAllPoints(); bgLin:SetPoint("TOPLEFT", strip, "TOP", -inner, 0); bgLin:SetPoint("BOTTOMRIGHT", strip, "BOTTOM")
  grad(bgLin, mid, op, cC, op)
  bgRin:ClearAllPoints(); bgRin:SetPoint("TOPLEFT", strip, "TOP"); bgRin:SetPoint("BOTTOMRIGHT", strip, "BOTTOM", inner, 0)
  grad(bgRin, cC, op, mid, op)
  bgLout:SetShown(F > 0); bgRout:SetShown(F > 0)
  if F > 0 then
    bgLout:ClearAllPoints(); bgLout:SetPoint("TOPLEFT"); bgLout:SetPoint("BOTTOMRIGHT", strip, "BOTTOM", -inner, 0)
    grad(bgLout, cE, edgeMul, mid, op)
    bgRout:ClearAllPoints(); bgRout:SetPoint("TOPLEFT", strip, "TOP", inner, 0); bgRout:SetPoint("BOTTOMRIGHT")
    grad(bgRout, mid, op, cE, edgeMul)
  end

  -- Scanline pieces copy each background piece's rectangle and alpha ramp.
  local SA = 0.28
  local function scanGrad(t, c1, m1, c2, m2)
    t:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, SA * c1[4] * m1), CreateColor(0, 0, 0, SA * c2[4] * m2))
  end
  local gset = {
    { mid, op, cC, op }, { cC, op, mid, op }, { cE, edgeMul, mid, op }, { mid, op, cE, edgeMul } }
  for i, pc in ipairs(scanPieces) do
    local st, bgp = pc[1], pc[2]
    local on = db.scanlines ~= false and bgp:IsShown()
    st:SetShown(on)
    if on then
      st:ClearAllPoints()
      st:SetPoint("TOPLEFT", bgp, "TOPLEFT"); st:SetPoint("BOTTOMRIGHT", bgp, "BOTTOMRIGHT")
      local g = gset[i]
      scanGrad(st, g[1], g[2], g[3], g[4])
      local widths = { inner, inner, half - inner, half - inner }
      local w, h = widths[i], db.height
      pc.w, pc.h = max(w, 1), h
      st:SetTexCoord(0, pc.w / 16, -scanOff, h / 4 - scanOff)
    end
  end

  if ns.MarkersStyle then ns.MarkersStyle() end   -- icon size/colors may have changed (settings or theme)
  root:EnableMouse(true)   -- right-click opens the marker menu; the XP strip has its own hover frame
  unlockTint:SetShown(not db.locked)
  -- Apply clears anchors above, so re-layout right now. Waiting for the next OnUpdate
  -- can let one frame render with no anchors, which shows up as flicker while dragging sliders.
  ns.UpdateEdges(); ns.UpdateXP()
  Layout()
  if ns.OnSettingsChanged then ns.OnSettingsChanged() end   -- keeps the theme dropdown/buttons current
end

-- Per-frame layout -----------------------------------------------------------
-- Kept cheap on purpose: runs only when the bearing changes, skips redundant
-- Show/Hide/SetAlpha/ClearAllPoints calls, and reuses precomputed degree strings.
local DEG = {}
for i = 0, 359 do DEG[i] = i .. "\194\176" end

local bearing, lastDeg, lastFacing = 0, nil, nil
-- Lays out the compass (letters, numbers, ticks and marker icons) for the current facing. Runs only when something changed.
function Layout()
  local half = db.width / 2
  local ppd = db.width / db.span          -- pixels per degree
  local fadeZone = half * math.max(0.05, db.fadeAmount)
  local fade, showTicks, showInter = db.fadeEdges, db.showTicks, db.showIntercardinals
  local edge = db.flipTicks and "TOP" or "BOTTOM"
  local yoff = db.height * 0.14
  if db.showDegrees and db.degreeInline then yoff = yoff - db.fontSize * 0.45 end
  if db.flipTicks then yoff = -yoff end   -- mirror: letters below, ticks above
  local opt = db.optimize
  local b = bearing

  for i = 1, #ticks do
    local t = ticks[i]
    local x = (((t.deg - b + 540) % 360) - 180) * ppd
    local ax = abs(x)
    if not showTicks or ax > half then
      if t.shown or not opt then t.tex:Hide(); t.shown = false end
    else
      if not opt then t.tex:ClearAllPoints() end
      t.tex:SetPoint(edge, strip, edge, x, 0)
      local a = fade and min(1, (half - ax) / fadeZone) or 1
      if not opt or a ~= t.alpha then t.tex:SetAlpha(a); t.alpha = a end
      if not opt or not t.shown then t.tex:Show(); t.shown = true end
    end
  end

  local showNum = db.showNumbers
  for i = 1, #labels do
    local l = labels[i]
    local x = (((l.deg - b + 540) % 360) - 180) * ppd
    local ax = abs(x)
    if ax > half or l.suppress or (l.kind == "inter" and not showInter) or (l.kind == "number" and not showNum) then
      if l.shown or not opt then l.f:Hide(); l.shown = false end
    else
      if not opt then l.f:ClearAllPoints() end
      l.f:SetPoint("CENTER", strip, "CENTER", x, yoff)
      local a = fade and min(1, (half - ax) / fadeZone) or 1
      if not opt or a ~= l.alpha then l.f:SetAlpha(a); l.alpha = a end
      if not opt or not l.shown then l.f:Show(); l.shown = true end
    end
  end

  if ns.LayoutMarkers then ns.LayoutMarkers(b, ppd, half, fade, fadeZone) end

  local d = floor(b + 0.5) % 360
  if not opt or d ~= lastDeg then lastDeg = d; degText:SetText(DEG[d]); SetOutlineText(degOut, DEG[d]) end
end

Layout = ns.Perf("Layout", Layout)

local badTime = 0
root:SetScript("OnUpdate", ns.Perf("OnUpdate", function(_, elapsed)
  if not db then return end
  -- GetPlayerFacing: radians, 0 = north, increasing counter-clockwise. It can return nil, or a
  -- "secret" value that must not be used in arithmetic, so validate before touching it.
  local f = GetPlayerFacing()
  local usable = false
  if issecretvalue and issecretvalue(f) then usable = false
  elseif type(f) == "number" then usable = true end
  if usable then badTime = 0 else badTime = badTime + elapsed end
  -- Disabled only while facing is actually unusable. Inside an instance the wait is short (the
  -- game withholds facing there); elsewhere one second avoids a flash during loading screens.
  local msg = nil
  if not usable and badTime > (instMsg and 0.2 or 1) then msg = instMsg or "HUD Unavailable" end
  if msg ~= disabledMsg then SetDisabled(msg) end
  if fx.mode then FXStep(elapsed) end
  if disabledMsg or not usable then return end
  if not db.optimize then
    -- Unoptimized path: recompute and re-layout every frame.
    if f then bearing = (360 - deg(f)) % 360 end
    Layout()
    return
  end
  if f and f ~= lastFacing then          -- idle frames exit here with no math
    lastFacing = f
    local nb = (360 - deg(f)) % 360      -- convert to compass bearing (clockwise)
    -- Ignore changes under 0.1 pixel; they cannot be seen.
    if abs(nb - bearing) > 0.1 * db.span / db.width then bearing = nb; dirty = true end
  end
  if dirty then dirty = false; Layout() end
end))

root:SetScript("OnDragStart", function(self) if db and not db.locked then self:StartMoving() end end)
root:SetScript("OnMouseUp", function(_, button)         -- right-click opens the marker menu (left-click is for dragging)
  if button == "RightButton" and db and db.rightClickMenu ~= false and ns.ToggleMarkerMenu then ns.ToggleMarkerMenu() end
end)
root:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local cx, top = self:GetCenter(), self:GetTop()
  local ux, utop = UIParent:GetCenter(), UIParent:GetTop()
  db.x, db.y = floor(cx - ux + 0.5), math.min(floor(top - utop + 0.5), 0)
  ns.Apply()
  if ns.RefreshSettings then ns.RefreshSettings() end
end)

-- XP tooltip -------------------------------------------------------------------
local hovered = false
-- Shows CHUD's own tooltip for the bar, or the game's tooltip when that is switched off.
local function ShowTooltip()
  -- CHUD's own tooltip (see Tooltip.lua); if it is switched off or fails for any reason, the game's tooltip below is used.
  if db.tipStyle ~= false and ns.TipShow then
    local d = { drag = not db.locked }
    if db.xpBar then
      d.level, d.cur, d.mx, d.isMax = XPInfo()
      d.rested = GetXPExhaustion and GetXPExhaustion() or nil
      d.perHour = ns.XPPerHour()
    end
    local ok, shown = pcall(ns.TipShow, xpHover, d)
    if ok and shown then return end
    if ns.TipHide then ns.TipHide() end
  end
  GameTooltip:SetOwner(xpHover, "ANCHOR_BOTTOM")
  if db.xpBar then
    local level, cur, mx, isMax = XPInfo()
    if isMax then
      GameTooltip:AddLine("Level " .. level .. " (Max Level)", 1, 0.82, 0)
    else
      GameTooltip:AddLine("Level " .. level, 1, 0.82, 0)
      GameTooltip:AddDoubleLine("XP", format("%s / %s (%.1f%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(mx), cur / mx * 100), 1, 1, 1, 1, 1, 1)
      GameTooltip:AddDoubleLine("Remaining", BreakUpLargeNumbers(mx - cur), 1, 1, 1, 0.4, 1, 0.4)
      local rested = GetXPExhaustion and GetXPExhaustion()
      if rested and rested > 0 then
        GameTooltip:AddDoubleLine("Rested", format("%s (%.1f%%)", BreakUpLargeNumbers(rested), rested / mx * 100), 1, 1, 1, 0.3, 0.6, 1)
      else
        local ph = ns.XPPerHour()
        GameTooltip:AddDoubleLine("XP/h", ph and BreakUpLargeNumbers(floor(ph + 0.5)) or "--", 1, 1, 1, 0.3, 0.6, 1)
      end
    end
  end
  if not db.locked then GameTooltip:AddLine("Drag To Move", 0.6, 0.6, 0.6) end
  GameTooltip:Show()
end
xpHover:SetScript("OnEnter", function() hovered = true; ShowTooltip() end)
xpHover:SetScript("OnLeave", function() hovered = false; if ns.TipHide then ns.TipHide() end; GameTooltip:Hide() end)
-- While unlocked, the XP strip drags the whole HUD just like the compass does.
xpHover:SetScript("OnMouseUp", function(_, button) root:GetScript("OnMouseUp")(root, button) end)   -- right-click still opens the marker menu
xpHover:SetScript("OnDragStart", function() if db and not db.locked then root:StartMoving() end end)
xpHover:SetScript("OnDragStop", function() root:GetScript("OnDragStop")(root) end)
-- Hovering the compass itself only shows a move hint, and only while unlocked.
root:SetScript("OnEnter", function()
  if db and not db.locked then
    GameTooltip:SetOwner(root, "ANCHOR_BOTTOM"); GameTooltip:AddLine("Drag To Move", 0.6, 0.6, 0.6); GameTooltip:Show()
  end
end)
root:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Saved-variable migrations -------------------------------------------------
-- db.schema records which migrations have run, so each runs once per profile. (Earlier builds used
-- one-off flags such as numbersReset; a full reset wiped those flags and the migration then ran
-- again on the next login, overwriting settings the user had chosen since.)
local SCHEMA = 2
local SETUP_VERSION = "1.0"   -- saved data from before this release is cleared once at load (see ADDON_LOADED); raise it to force that again
local OBSOLETE = {   -- settings that no longer exist
  "textOutline", "numbersReset", "outlineReset", "xpFlip", "xpHeight", "xpTicks", "xpBackfill",
  "mk_outline", "mk_outlineColor", "mk_shadow", "fadeMoving",
}
local FILL_STYLES = { fadeCenter = true, fadeBottom = true, fadeTop = true, band = true, full = true }

-- Brings older saved settings up to the current schema and drops obsolete keys.
function ns.MigrateSavedVariables(d)
  if d.numbersReset and d.outlineReset then d.schema = d.schema or 1 end   -- those one-off resets already ran
  if (d.schema or 0) < 1 then
    -- Early builds defaulted number labels on and the text outline to 1 px; both now default to off.
    d.showNumbers = false
    d.outlineWidth = 0
  end
  if d.fontName == "Default (game font)" then d.fontName = ns.defaults.fontName end   -- label was re-cased
  d.outlineWidth = math.min(d.outlineWidth or 0, 2)                                    -- older saves allowed up to 10
  if not FILL_STYLES[d.xpFillStyle] then d.xpFillStyle = ns.defaults.xpFillStyle end   -- removed or unknown style
  for _, k in ipairs(OBSOLETE) do d[k] = nil end
  d.schema = SCHEMA
end

-- Init / slash ---------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:RegisterEvent("UPDATE_EXHAUSTION")
ev:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
pcall(ev.RegisterEvent, ev, "ADDON_ACTION_BLOCKED")     -- the game tells us when an action of ours was refused, and which one
pcall(ev.RegisterEvent, ev, "ADDON_ACTION_FORBIDDEN")
ev:SetScript("OnEvent", function(_, event, name, ...)
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    if name == "CHUD" then
      local fn = ...
      local text = "The game blocked CHUD from calling " .. tostring(fn) .. " (" .. event .. "). " .. (debugstack and debugstack(3, 6, 0) or "")
      print("|cffd9bf4dCHUD:|r |cffffb347" .. text .. "|r")
      if CHUDDB then CHUDDB.lastBlocked = { at = date and date("%Y-%m-%d %H:%M:%S") or "", text = text } end
    end
    return
  end
  if event == "CHAT_MSG_COMBAT_XP_GAIN" then NoteKillXP(name); return end   -- name is the chat message here
  if event ~= "ADDON_LOADED" then
    if db then CheckXPGain(); ns.UpdateXP(); UpdateInstance() end
    if event == "PLAYER_ENTERING_WORLD" then ns.ApplyBlizzXP() end   -- Blizzard's bar can be created after our load
    if hovered and db then ShowTooltip() end   -- keep an open tooltip current
    return
  end
  if name ~= ADDON then return end
  if ns.ApplyFactionDefaults then ns.ApplyFactionDefaults() end   -- faction-colored defaults
  CHUDDB = CHUDDB or {}
  db = CHUDDB
  for k, v in pairs(ns.defaults) do
    if db[k] == nil then db[k] = Copy(v) end
  end
  ns.MigrateSavedVariables(db)
  -- Release 1.0 starts everyone from a fresh install: saved settings and imported data from any earlier version are cleared once
  -- and the setup tour runs. Saved themes, recorded gathering spots and the game settings Highlight Node must give back survive.
  if db.setupVersion ~= SETUP_VERSION then
    local themes, nodes, hlSaved = db.themes, db.nodes, db.hlSaved
    for k in pairs(db) do db[k] = nil end
    for k, v in pairs(ns.defaults) do db[k] = Copy(v) end
    db.themes, db.nodes, db.hlSaved = themes or {}, nodes or {}, hlSaved
    db.schema = SCHEMA
    db.setupVersion = SETUP_VERSION
  end
  ns.db = db
  if ns.BuildSettings then ns.BuildSettings() end
  ns.Apply()
end)

-- Resets every setting to its default. Saved themes and recorded gathering spots are kept.
function ns.Reset()
  -- saved themes, recorded gathering spots, the imported gathering data and the game settings Highlight.lua must give back
  -- all survive a full reset
  local themes, nodes, gdata, hlSaved, tourDone, setupVersion = db.themes, db.nodes, db.gdata, db.hlSaved, db.tourDone, db.setupVersion
  for k in pairs(db) do db[k] = nil end
  for k, v in pairs(ns.defaults) do db[k] = Copy(v) end
  db.themes = themes or {}
  db.nodes = nodes or {}
  db.gdata, db.hlSaved, db.tourDone, db.setupVersion = gdata, hlSaved, tourDone, setupVersion
  db.schema = SCHEMA
  ns.Apply()
  if ns.RefreshSettings then ns.RefreshSettings() end
end

-- Grouped resets. Position (x, y) belongs to neither group; it has its own reset.
local COLOR_KEYS = { "bgMode", "bgOpacity", "bgSolid", "bgCenter", "bgEdge", "textColor",
  "cardinalColor", "northColor", "tickColor", "markerColor", "degreeColor", "xpColor", "outlineColor", "mk_color", "edgeColor" }
local BEHAVIOR_KEYS = { "width", "height", "span", "fontSize", "fadeEdges", "fadeAmount",
  "showDegrees", "degreeInline", "showIntercardinals", "showTicks", "flipTicks", "xpBar", "xpPulse", "xpWave", "markerStyle", "outlineWidth", "showNumbers", "edgeLines", "xpFillMode", "xpFillStyle", "xpFillStrength", "mk_size", "mk_shadowAlpha", "mk_shadowDist", "mk_native", "locked", "fontName", "fontPath", "optimize", "glitchFx" }
ns.COLOR_KEYS, ns.BEHAVIOR_KEYS = COLOR_KEYS, BEHAVIOR_KEYS   -- used by Themes.lua
-- Resets just the listed settings to their defaults.
local function ResetKeys(keys)
  for _, k in ipairs(keys) do db[k] = Copy(ns.defaults[k]) end
  ns.Apply()
  if ns.RefreshSettings then ns.RefreshSettings() end
end
local TIP_KEYS = { "tipAuto", "tipBg", "tipEdge", "tipAccent", "tipTitle", "tipText", "tipGood", "tipRest" }
-- Resets the color settings to their defaults.
function ns.ResetColors() ResetKeys(TIP_KEYS); ResetKeys(COLOR_KEYS) end
-- Resets the behavior settings to their defaults.
function ns.ResetBehavior() ResetKeys({ "scanlines" }); ResetKeys(BEHAVIOR_KEYS) end

-- Position-only resets (leave every other setting alone).
function ns.CenterHorizontal()
  db.x = 0
  ns.Apply()
  if ns.RefreshSettings then ns.RefreshSettings() end
end
-- Puts the bar back at its default position.
function ns.ResetPosition()
  db.x, db.y = ns.defaults.x, ns.defaults.y
  ns.Apply()
  if ns.RefreshSettings then ns.RefreshSettings() end
end

-- Diagnostic output capture ------------------------------------------------------------------------------
-- Diagnostics (/chud debug) still print to chat, and the same lines are kept in CHUDLog.
-- WoW cannot write files directly: the saved copy is written to CHUDLog.lua in the SavedVariables folder
-- (WTF\Account\<account>\SavedVariables) after /reload or logout. "/chud debug" shows the same text in a copyable window.
local LOG_KEEP = 30
-- Runs fn and collects everything it prints into the log window instead of chat.
local function Capture(cmd, fn)
  local lines, old = {}, print
  print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    lines[#lines + 1] = (table.concat(t, " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    old(...)
  end
  local ok, err = pcall(fn)
  print = old
  if not ok then lines[#lines + 1] = "ERROR: " .. tostring(err); old("CHUD: " .. tostring(err)) end
  local log = _G.CHUDLog
  if type(log) ~= "table" then log = {}; _G.CHUDLog = log end
  log[#log + 1] = { when = date("%Y-%m-%d %H:%M:%S"), cmd = "/chud " .. cmd, lines = lines }
  while #log > LOG_KEEP do table.remove(log, 1) end
end

local logFrame
-- Shows the log window, a text box whose contents can be copied.
function ns.ShowLog()
  if not logFrame then
    local f = CreateFrame("Frame", "CHUDLogFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(640, 420); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText("CHUD log (Ctrl+A, Ctrl+C to copy)") end
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -32); sf:SetPoint("BOTTOMRIGHT", -32, 10)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject(ChatFontNormal); eb:SetWidth(580)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f.edit = eb
    tinsert(UISpecialFrames, "CHUDLogFrame")
    logFrame = f
  end
  local out = {}
  for _, run in ipairs(_G.CHUDLog or {}) do
    out[#out + 1] = "=== " .. run.when .. "  " .. run.cmd
    for _, l in ipairs(run.lines) do out[#out + 1] = l end
    out[#out + 1] = ""
  end
  logFrame.edit:SetText(#out > 0 and table.concat(out, "\n") or "Nothing logged yet. Run /chud debug.")
  logFrame:Show()
  logFrame.edit:SetFocus(); logFrame.edit:HighlightText()
end

-- Slash commands. Listed for players: /chud (settings), unlock, lock, center, reset, install (the setup tour).
-- Not listed anywhere in the UI: /chud menu (the marker menu, a way back in when the right-click menu is off) and
-- /chud debug, which runs every diagnostic and shows the combined log in a copyable window. A single one can be run with
-- /chud debug <facing | probe | markers | gm | soft | log | clear | xpdemo | perf>.
local DEBUG = {
  { "facing", function() return ns.Debug end },
  { "probe", function() return ns.Probe end },
  { "markers", function() return ns.MarkerDebug end },
  { "gm", function() return ns.GMProbe end },
  { "soft", function() return ns.SoftProbe end },
}
local function RunDebug(which)
  if which == "" then
    for _, d in ipairs(DEBUG) do
      local fn = d[2]()
      if fn then Capture("debug " .. d[1], fn) end
    end
    ns.ShowLog()
    return
  end
  for _, d in ipairs(DEBUG) do
    if d[1] == which then
      local fn = d[2]()
      if fn then Capture("debug " .. which, fn) end
      return
    end
  end
  if which == "log" then ns.ShowLog()
  elseif which == "clear" then _G.CHUDLog = {}; print("CHUD: log cleared")
  elseif which == "xpdemo" then ns.XPDemo()
  elseif which == "perf" then Capture("debug perf", ns.PerfToggle)
  end
end

SLASH_CHUD1 = "/chud"
SlashCmdList.CHUD = function(msg)
  msg = strlower(strtrim(msg or ""))
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  if cmd == "unlock" then db.locked = false; ns.Apply()
  elseif cmd == "lock" then db.locked = true; ns.Apply()
  elseif cmd == "center" then ns.CenterHorizontal()
  elseif cmd == "reset" then ns.Reset()
  elseif cmd == "install" then if ns.RerunSetup then ns.RerunSetup() end
  elseif cmd == "xpwave" then
    db.xpWave = (db.xpWave == false)
    ns.UpdateXP()
    print("CHUD: XP edge wave " .. (db.xpWave ~= false and "on" or "off"))
  elseif cmd == "menu" then if ns.ToggleMarkerMenu then ns.ToggleMarkerMenu() end
  elseif cmd == "debug" then RunDebug(rest)
  elseif ns.categoryID then Settings.OpenToCategory(ns.categoryID)
  end
  if ns.RefreshSettings then ns.RefreshSettings() end
end
