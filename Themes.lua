local ADDON, ns = ...
local floor = math.floor

-- A theme is a snapshot of the "look": every color and layout/behavior key, except things
-- that are not part of a look (position, width, lock state, the CPU setting, the themes list itself).
-- (mk_native, Original Icon Colors, is a preference like those: picking a theme must not switch it, and it must not stop a theme matching.)
local EXCLUDE = { locked = true, optimize = true, glitchFx = true, xpPulse = true, width = true, mk_native = true }
local KEYS = {}
for _, list in ipairs({ ns.COLOR_KEYS, ns.BEHAVIOR_KEYS }) do
  for _, k in ipairs(list) do
    if not EXCLUDE[k] then KEYS[#KEYS + 1] = k end
  end
end

-- Palettes ---------------------------------------------------------------------------------
-- A theme is described by a few colors; everything else is derived so themes stay consistent:
--   bg      background tint (gradient center at `alpha`, fading to transparent at the edges)
--   accent  E/S/W letters and center marker (override the marker with `marker`)
--   text    numbers, diagonals and the degree readout; ticks use it at lower opacity
--   north   the N letter           xp   the XP bar fill
local function Palette(p)
  local bg, ac, tx = p.bg, p.accent, p.text
  return {
    bgSolid = { bg[1], bg[2], bg[3], 0.55 },
    bgCenter = { bg[1], bg[2], bg[3], p.alpha or 0.90 },
    bgEdge = { bg[1], bg[2], bg[3], 0.00 },
    textColor = { tx[1], tx[2], tx[3], 1 },
    cardinalColor = { ac[1], ac[2], ac[3], 1 },
    northColor = { p.north[1], p.north[2], p.north[3], 1 },
    tickColor = { tx[1], tx[2], tx[3], 0.55 },
    markerColor = { (p.marker or ac)[1], (p.marker or ac)[2], (p.marker or ac)[3], 1 },
    degreeColor = { tx[1], tx[2], tx[3], 1 },
    xpColor = { p.xp[1], p.xp[2], p.xp[3], 1 },
    outlineColor = { 0, 0, 0, 1 },
    mk_color = { ac[1], ac[2], ac[3], 1 },        -- marker icons take the theme's accent
    edgeColor = { ac[1], ac[2], ac[3], 0.9 },        -- hairline edge lines use the accent
  }
end

-- Palette plus optional layout/behavior overrides (marker style, XP bar height, ...).
local function Theme(p, extra)
  local t = Palette(p)
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

-- Thin solid bar: no ticks or diagonals, degrees inside the bar, notch marker.
-- Keeps the base theme's colors and font, but resets the layout so all Minimal variants match.
local function MinimalOf(base, solid)
  local t = ns.Copy(base)
  t.bgMode = "solid"; t.bgSolid = solid
  t.height = 30; t.fontSize = 14; t.span = 180
  t.fadeEdges = true; t.fadeAmount = 0.5
  t.flipTicks = false
  t.showTicks = false; t.showIntercardinals = false
  t.showDegrees = (base.showDegrees == true); t.degreeInline = true; t.showNumbers = (base.showNumbers == true)
  t.markerStyle = "notch"
  return t
end

-- Faction-aware defaults ---------------------------------------------------------------------
-- The default look follows the character's faction. This runs at ADDON_LOADED, before saved
-- variables are merged, so a fresh install, "Reset", and the built-in Default theme all agree.
local WARM_WHITE = { 1.00, 0.96, 0.85 }    -- North in the default look: set apart without clashing
local FACTION = {
  Alliance = Palette({ bg = { 0.05, 0.09, 0.18 }, alpha = 0.88, accent = { 0.96, 0.78, 0.30 },
    text = { 0.92, 0.94, 0.98 }, north = WARM_WHITE, xp = { 0.25, 0.50, 0.95 } }),
  Horde = Palette({ bg = { 0.16, 0.05, 0.05 }, alpha = 0.88, accent = { 0.95, 0.72, 0.25 },
    marker = { 0.90, 0.25, 0.18 }, text = { 0.96, 0.91, 0.88 }, north = WARM_WHITE, xp = { 0.80, 0.15, 0.12 } }),
  Neutral = Palette({ bg = { 0.08, 0.08, 0.10 }, alpha = 0.88, accent = { 1.00, 0.82, 0.00 },
    text = { 0.95, 0.95, 0.95 }, north = WARM_WHITE, xp = { 0.58, 0.00, 0.55 } }),
}
-- Sets the default accent colors from your faction (Alliance, Horde or neutral).
function ns.ApplyFactionDefaults()
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  local pal = FACTION[faction] or FACTION.Neutral
  for k, v in pairs(pal) do ns.defaults[k] = ns.Copy(v) end
end

-- Built-in themes (cannot be deleted). Default is empty: it is the faction-aware defaults.
ns.BuiltinNames = { "Default", "Dark", "High Contrast", "Assassins", "Alliance", "Horde", "UNSC", "Nordic", "Azeroth", "Pink",
  "Tactical", "Tactical Minimal", "Frost", "Frost Minimal", "Ember", "Ember Minimal",
  "Catppuccin", "Tokyo Night", "Rose Pine", "Gruvbox", "Dracula", "Kanagawa", "Everforest", "Synthwave" }

-- Fonts that ship with the game, so themes can use them without any other addon.
local ARIAL    = { fontName = "Arial Narrow",  fontPath = "Fonts\\ARIALN.TTF" }
local MORPHEUS = { fontName = "Morpheus",      fontPath = "Fonts\\MORPHEUS.ttf" }
-- Copies the font settings into a theme table and returns it.
local function With(font, t) for k, v in pairs(font) do t[k] = v end return t end

-- Each theme pairs a palette with a different mix of features:
--   Dark      crisp solid bar, short fade          Assassins light plate, no outline, XP on top
--   Alliance  tighter view, chunkier XP bar        Horde     flipped: ticks on top, notch marker
--   UNSC      amber on olive, narrow font, notch
--   Nordic    very soft edges, quiet, narrow font  Azeroth   fantasy font, big gold XP bar
--   Pink      wide view, spotlight fade           Tactical  solid HUD plate, narrow font, notch
--   Frost     full 360 degree view, soft fade      Ember     tall bar with large letters
local BUILTIN = {
  Default = {},
  Dark = Theme({ bg = { 0.05, 0.05, 0.05 }, accent = { 0.92, 0.92, 0.92 },
    text = { 0.80, 0.80, 0.80 }, north = { 0.95, 0.42, 0.42 }, xp = { 0.45, 0.45, 0.52 } },
    { bgMode = "solid", bgSolid = { 0.04, 0.04, 0.04, 0.90 }, fadeEdges = true, fadeAmount = 0.30, outlineWidth = 1 }),
  -- High Contrast: opaque black plate, pure white letters and ticks, yellow cardinals, red North,
  -- larger text, degrees and numbers on, and a bright green XP fill. Meant for readability over any scene.
  ["High Contrast"] = Theme({ bg = { 0, 0, 0 }, accent = { 1.00, 0.90, 0.00 },
    text = { 1, 1, 1 }, north = { 1.00, 0.30, 0.25 }, xp = { 0.20, 1.00, 0.40 } },
    { bgMode = "solid", bgSolid = { 0, 0, 0, 1 }, tickColor = { 1, 1, 1, 1 }, fadeEdges = true, fadeAmount = 0.20,
      fontSize = 16, height = 40, span = 150, markerStyle = "short", showDegrees = true, showNumbers = true,
      mk_size = 18 }),
  -- Assassins: a light plate with dark text and no text outline. The center stays crisp; only
  -- the outer 35% of each half fades.
  Assassins = Theme({ bg = { 0.95, 0.94, 0.89 }, accent = { 0.10, 0.20, 0.45 },
    text = { 0.12, 0.12, 0.16 }, north = { 0.62, 0.03, 0.05 }, xp = { 0.20, 0.45, 0.85 } },
    { bgMode = "solid", bgSolid = { 0.95, 0.94, 0.89, 0.67 }, fadeEdges = true, fadeAmount = 0.35,
      outlineWidth = 0, markerStyle = "notch",
      mk_color = { 0.769, 0.035, 0.122, 1 } }),   -- icon color #C4091F
  Alliance = Theme({ bg = { 0.04, 0.10, 0.25 }, accent = { 1.00, 0.82, 0.20 },
    text = { 0.90, 0.93, 1.00 }, north = { 1, 1, 1 }, xp = { 0.20, 0.45, 0.95 } },
    { span = 150, fadeAmount = 0.40, outlineWidth = 1, outlineColor = { 0.02, 0.05, 0.15, 1 } }),
  Horde = Theme({ bg = { 0.25, 0.04, 0.04 }, accent = { 0.96, 0.32, 0.24 },
    text = { 0.95, 0.85, 0.80 }, north = { 1.00, 0.75, 0.20 }, xp = { 0.92, 0.22, 0.16 } },
    { flipTicks = true, markerStyle = "notch", outlineWidth = 1, outlineColor = { 0.12, 0.02, 0.02, 1 } }),
  UNSC = Theme({ bg = { 0.08, 0.10, 0.07 }, accent = { 1.00, 0.72, 0.15 },
    text = { 0.78, 0.85, 0.70 }, north = { 1.00, 0.40, 0.15 }, xp = { 0.55, 0.78, 0.30 } },
    With(ARIAL, { bgMode = "solid", bgSolid = { 0.07, 0.09, 0.06, 0.88 }, fadeAmount = 0.25, height = 34,
      span = 130, markerStyle = "notch", showDegrees = true, showNumbers = true, outlineWidth = 1 })),
  Nordic = Theme({ bg = { 0.12, 0.15, 0.18 }, accent = { 0.55, 0.70, 0.78 },
    text = { 0.82, 0.87, 0.90 }, north = { 0.90, 0.52, 0.47 }, xp = { 0.45, 0.62, 0.70 } },
    With(ARIAL, { outlineWidth = 1, markerStyle = "notch", showIntercardinals = false, fadeAmount = 0.80 })),
  Azeroth = Theme({ bg = { 0.28, 0.20, 0.10 }, accent = { 1.00, 0.82, 0.00 },
    text = { 0.95, 0.88, 0.70 }, north = { 1.00, 0.45, 0.30 }, xp = { 0.90, 0.65, 0.15 } },
    With(MORPHEUS, { height = 42, fontSize = 15, span = 140, outlineWidth = 1, outlineColor = { 0.12, 0.07, 0.02, 1 }, mk_size = 18 })),
  Pink = Theme({ bg = { 0.35, 0.10, 0.25 }, accent = { 1.00, 0.50, 0.75 },
    text = { 1.00, 0.90, 0.95 }, north = { 1, 1, 1 }, xp = { 1.00, 0.40, 0.70 } },
    { span = 240, fadeAmount = 1.00, markerStyle = "notch", outlineWidth = 1, outlineColor = { 0.20, 0.03, 0.12, 1 } }),
  Tactical = Theme({ bg = { 0.04, 0.12, 0.05 }, accent = { 0.30, 1.00, 0.30 },
    text = { 0.70, 1.00, 0.70 }, north = { 1.00, 0.40, 0.35 }, xp = { 0.30, 0.90, 0.30 } },
    With(ARIAL, { bgMode = "solid", bgSolid = { 0.03, 0.10, 0.04, 0.80 }, fadeEdges = true, fadeAmount = 0.25, height = 32,
      span = 120, markerStyle = "notch", showDegrees = true, showNumbers = true, outlineWidth = 1 })),
  Frost = Theme({ bg = { 0.05, 0.12, 0.20 }, accent = { 0.45, 0.80, 1.00 },
    text = { 0.85, 0.95, 1.00 }, north = { 1, 1, 1 }, xp = { 0.30, 0.65, 1.00 } },
    { span = 360, fadeAmount = 0.90, outlineWidth = 1, outlineColor = { 0.01, 0.05, 0.12, 1 } }),
  Ember = Theme({ bg = { 0.18, 0.06, 0.02 }, accent = { 1.00, 0.55, 0.15 },
    text = { 1.00, 0.90, 0.80 }, north = { 1.00, 0.38, 0.25 }, xp = { 1.00, 0.45, 0.10 } },
    { height = 44, fontSize = 16, mk_size = 18, outlineWidth = 1, outlineColor = { 0.12, 0.02, 0.00, 1 } }),
}
BUILTIN["Tactical Minimal"] = MinimalOf(BUILTIN.Tactical, { 0.02, 0.08, 0.03, 0.45 })
BUILTIN["Frost Minimal"]    = MinimalOf(BUILTIN.Frost,    { 0.03, 0.08, 0.14, 0.45 })
BUILTIN["Ember Minimal"]    = MinimalOf(BUILTIN.Ember,    { 0.12, 0.04, 0.01, 0.45 })

-- Catppuccin Mocha and Tokyo Night: two of the most used editor palettes right now. The colors are their
-- published base, text and accent values; only the colors are borrowed.
BUILTIN.Catppuccin = Theme({ bg = { 0.118, 0.118, 0.180 }, accent = { 0.796, 0.651, 0.969 },
  text = { 0.804, 0.839, 0.957 }, north = { 0.953, 0.545, 0.659 }, xp = { 0.537, 0.706, 0.980 } },
  { bgMode = "solid", bgSolid = { 0.118, 0.118, 0.180, 0.92 }, fadeEdges = true, fadeAmount = 0.30,
    markerStyle = "notch", outlineWidth = 1, outlineColor = { 0.07, 0.07, 0.11, 1 } })
BUILTIN["Tokyo Night"] = Theme({ bg = { 0.102, 0.106, 0.149 }, accent = { 0.478, 0.635, 0.969 },
  text = { 0.753, 0.792, 0.961 }, north = { 0.969, 0.463, 0.557 }, xp = { 0.733, 0.604, 0.969 } },
  { fadeAmount = 0.50, showDegrees = true, outlineWidth = 1, outlineColor = { 0.04, 0.04, 0.08, 1 } })

-- More palettes from the editor and terminal themes people use most (Rose Pine, Gruvbox, Dracula, Kanagawa, Everforest), plus
-- an original retro-neon one. As with Catppuccin and Tokyo Night, only the published colors are borrowed. Each one also gets a
-- different layout, so switching themes changes more than the tint.
local function Hex(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 } end
local function WithAlpha(c, a) return { c[1], c[2], c[3], a } end
BUILTIN["Rose Pine"] = Theme({ bg = Hex("191724"), accent = Hex("f6c177"), text = Hex("e0def4"), north = Hex("eb6f92"), xp = Hex("9ccfd8") },
  { fadeAmount = 0.70, markerStyle = "notch", outlineWidth = 1, outlineColor = { 0.06, 0.05, 0.10, 1 } })
BUILTIN.Gruvbox = Theme({ bg = Hex("282828"), accent = Hex("fe8019"), text = Hex("ebdbb2"), north = Hex("fb4934"), xp = Hex("b8bb26") },
  { bgMode = "solid", bgSolid = WithAlpha(Hex("282828"), 0.92), fadeEdges = true, fadeAmount = 0.25, height = 36, fontSize = 15,
    showDegrees = true, showNumbers = true, outlineWidth = 1, outlineColor = { 0.10, 0.10, 0.10, 1 } })
BUILTIN.Dracula = Theme({ bg = Hex("282a36"), accent = Hex("bd93f9"), text = Hex("f8f8f2"), north = Hex("ff5555"), xp = Hex("50fa7b") },
  { bgMode = "solid", bgSolid = WithAlpha(Hex("282a36"), 0.92), fadeAmount = 0.35, markerStyle = "notch", span = 160,
    outlineWidth = 1, outlineColor = { 0.10, 0.10, 0.14, 1 } })
BUILTIN.Kanagawa = Theme({ bg = Hex("1f1f28"), accent = Hex("e6c384"), text = Hex("dcd7ba"), north = Hex("e46876"), xp = Hex("7e9cd8") },
  With(ARIAL, { span = 200, fadeAmount = 0.60, showIntercardinals = false, outlineWidth = 1, outlineColor = { 0.05, 0.05, 0.08, 1 } }))
BUILTIN.Everforest = Theme({ bg = Hex("2d353b"), accent = Hex("a7c080"), text = Hex("d3c6aa"), north = Hex("e67e80"), xp = Hex("dbbc7f") },
  { bgMode = "solid", bgSolid = WithAlpha(Hex("2d353b"), 0.88), fadeEdges = true, fadeAmount = 0.50, height = 34,
    showTicks = true, showDegrees = false, outlineWidth = 1, outlineColor = { 0.08, 0.10, 0.11, 1 } })
BUILTIN.Synthwave = Theme({ bg = Hex("140a2a"), accent = Hex("ff2e97"), marker = Hex("00e5ff"), text = Hex("c8f4ff"), north = Hex("ffe14d"),
  xp = Hex("00e5ff") },
  { height = 38, fontSize = 15, span = 200, flipTicks = true, showDegrees = true, markerStyle = "notch", mk_size = 17,
    outlineWidth = 1, outlineColor = { 0.05, 0.02, 0.12, 1 } })

-- Daylight is a toggle, not a theme: while it is on, the colors follow the game's clock in half-hour steps and the color
-- controls are locked. Turning it off puts back the colors the player had. Each keyframe is { hour, bg, accent, text,
-- north, xp }; the half-hour in between is blended from its two neighbours.
local DAY = {
  { 0.0,  { 0.03, 0.04, 0.10 }, { 0.55, 0.62, 0.95 }, { 0.80, 0.84, 0.95 }, { 0.95, 0.55, 0.60 }, { 0.35, 0.40, 0.85 } },  -- midnight
  { 5.5,  { 0.18, 0.10, 0.18 }, { 1.00, 0.62, 0.45 }, { 1.00, 0.90, 0.85 }, { 1.00, 0.85, 0.60 }, { 0.95, 0.50, 0.40 } },  -- dawn
  { 8.0,  { 0.10, 0.16, 0.24 }, { 1.00, 0.85, 0.45 }, { 0.95, 0.96, 1.00 }, { 1.00, 1.00, 0.90 }, { 0.40, 0.70, 0.95 } },  -- morning
  { 12.0, { 0.08, 0.20, 0.32 }, { 1.00, 0.92, 0.55 }, { 1.00, 1.00, 1.00 }, { 1.00, 0.95, 0.80 }, { 0.30, 0.75, 1.00 } },  -- noon
  { 17.0, { 0.24, 0.13, 0.06 }, { 1.00, 0.70, 0.25 }, { 1.00, 0.93, 0.80 }, { 1.00, 0.85, 0.50 }, { 1.00, 0.60, 0.20 } },  -- golden hour
  { 19.5, { 0.20, 0.08, 0.22 }, { 0.95, 0.50, 0.60 }, { 1.00, 0.88, 0.92 }, { 1.00, 0.75, 0.55 }, { 0.80, 0.35, 0.60 } },  -- dusk
  { 22.0, { 0.05, 0.06, 0.14 }, { 0.60, 0.65, 1.00 }, { 0.82, 0.86, 0.98 }, { 0.95, 0.55, 0.60 }, { 0.40, 0.45, 0.90 } },  -- night
  { 24.0, { 0.03, 0.04, 0.10 }, { 0.55, 0.62, 0.95 }, { 0.80, 0.84, 0.95 }, { 0.95, 0.55, 0.60 }, { 0.35, 0.40, 0.85 } },  -- midnight again
}
-- Blends two colors: f = 0 gives a, f = 1 gives b.
local function Mix(a, b, f)
  return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
end
-- The half-hour of the game's day (0-47). GetGameTime is the realm clock the in-game UI shows.
local function DayBucket()
  local h, m = 12, 0
  if GetGameTime then
    local ok, hh, mm = pcall(GetGameTime)
    if ok and type(hh) == "number" and type(mm) == "number" then h, m = hh, mm end
  end
  return h * 2 + (m >= 30 and 1 or 0)
end
-- The palette for one half-hour of the game day, blended between the day cycle's colors.
local function DaylightPalette(bucket)
  local t = bucket / 2
  local a, b = DAY[1], DAY[#DAY]
  for i = 1, #DAY - 1 do
    if t >= DAY[i][1] and t <= DAY[i + 1][1] then a, b = DAY[i], DAY[i + 1]; break end
  end
  local f = (t - a[1]) / max(b[1] - a[1], 0.001)
  return Palette({ bg = Mix(a[2], b[2], f), accent = Mix(a[3], b[3], f), text = Mix(a[4], b[4], f),
    north = Mix(a[5], b[5], f), xp = Mix(a[6], b[6], f) })
end

-- Daylight changes colors only, the marker icon color included (it takes the palette's accent, like a theme does). Turning
-- Daylight off puts back every color it replaced.
local function ApplyDaylightColors()
  local bucket = DayBucket()
  for k, v in pairs(DaylightPalette(bucket)) do ns.db[k] = v end
  ns.db.dayBucket = bucket
end

-- True when the day and night color cycle is on.
function ns.DaylightOn() return ns.db and ns.db.daylight == true end
-- Turns the day and night color cycle on or off.
function ns.SetDaylight(on)
  local db = ns.db
  if on and not db.daylight then
    local keep = {}
    for _, k in ipairs(ns.COLOR_KEYS) do keep[k] = ns.Copy(db[k]) end
    db.preDaylight, db.daylight = keep, true
    ApplyDaylightColors()
  elseif not on and db.daylight then
    for k, v in pairs(db.preDaylight or {}) do db[k] = ns.Copy(v) end
    db.preDaylight, db.daylight, db.dayBucket = nil, nil, nil
  end
  ns.Apply()
  if ns.RefreshSettings then ns.RefreshSettings() end
end

-- Deep comparison of two values.
local function Equal(a, b)
  if type(a) == "table" and type(b) == "table" then
    for k, v in pairs(a) do if not Equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
  elseif type(a) == "number" and type(b) == "number" then
    return math.abs(a - b) < 0.0005          -- slider/color-picker floats
  end
  return a == b
end

-- True for the built-in themes, which cannot be deleted.
function ns.IsBuiltin(name) return BUILTIN[name] ~= nil end

-- Full key set for a theme. Missing keys fall back to defaults, so themes saved by an older
-- version still work after new settings are added.
function ns.GetThemeData(name)
  local src = BUILTIN[name] or (ns.db.themes and ns.db.themes[name])
  if not src then return nil end
  local data = {}
  for _, k in ipairs(KEYS) do
    local v = src[k]
    if v == nil then v = ns.defaults[k] end
    data[k] = ns.Copy(v)
  end
  return data
end

-- The names of your saved themes, sorted.
function ns.UserThemeNames()
  local names = {}
  for n in pairs(ns.db.themes or {}) do names[#names + 1] = n end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

-- A copy of the current value of every theme setting.
function ns.SnapshotTheme()
  local snap = {}
  for _, k in ipairs(KEYS) do snap[k] = ns.Copy(ns.db[k]) end
  return snap
end

-- Name of the saved/built-in theme the current settings equal, or nil if they match none.
function ns.MatchTheme()
  local snap = ns.SnapshotTheme()
  for _, n in ipairs(ns.BuiltinNames) do
    if Equal(snap, ns.GetThemeData(n)) then return n end
  end
  for _, n in ipairs(ns.UserThemeNames()) do
    if Equal(snap, ns.GetThemeData(n)) then return n end
  end
  return nil
end

-- Applies a built-in or saved theme by name.
function ns.ApplyTheme(name)
  local data = ns.GetThemeData(name)
  if not data then return end
  for _, k in ipairs(KEYS) do ns.db[k] = data[k] end
  ns.db.daylight, ns.db.preDaylight, ns.db.dayBucket = nil, nil, nil   -- a theme sets every color itself, so Daylight turns off
  ns.Apply()
  if ns.RefreshSettings then ns.RefreshSettings() end
end

-- Saves the current look as a theme with this name.
function ns.SaveTheme(name)
  ns.db.themes = ns.db.themes or {}
  ns.db.themes[name] = ns.SnapshotTheme()
  if ns.OnSettingsChanged then ns.OnSettingsChanged() end
end

-- Deletes a saved theme. Built-in themes are protected.
function ns.DeleteTheme(name)
  if BUILTIN[name] then return end            -- built-ins are protected
  if ns.db.themes then ns.db.themes[name] = nil end
  if ns.OnSettingsChanged then ns.OnSettingsChanged() end
end

-- Sharing themes -----------------------------------------------------------------------------------------
-- A theme code is text: "CHUD-THEME:1:" followed by a base64 copy of the theme. It is read back with a small parser of our own
-- (nothing in a pasted code is ever run as Lua), only the known theme settings are accepted, and every value is checked
-- against the type of the setting's default.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64IDX = {}
for i = 1, #B64 do B64IDX[B64:sub(i, i)] = i - 1 end
local function B64Encode(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = floor(n / 262144) % 64, floor(n / 4096) % 64, floor(n / 64) % 64, n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1) ..
      (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end
local function B64Decode(s)
  s = s:gsub("[^%w%+/=]", "")
  local out = {}
  for i = 1, #s, 4 do
    local c1, c2, c3, c4 = s:sub(i, i), s:sub(i + 1, i + 1), s:sub(i + 2, i + 2), s:sub(i + 3, i + 3)
    local v1, v2 = B64IDX[c1], B64IDX[c2]
    if not (v1 and v2) then return nil end
    local v3, v4 = B64IDX[c3], B64IDX[c4]
    local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
    out[#out + 1] = string.char(floor(n / 65536) % 256)
    if v3 then out[#out + 1] = string.char(floor(n / 256) % 256) end
    if v4 then out[#out + 1] = string.char(n % 256) end
  end
  return table.concat(out)
end
-- Values are written as: n<number>; b1 or b0; s<length>:<text>; t<count>; followed by that many key/value pairs.
local function Ser(v, out)
  local t = type(v)
  if t == "number" then out[#out + 1] = "n" .. string.format("%.6g", v) .. ";"
  elseif t == "boolean" then out[#out + 1] = v and "b1" or "b0"
  elseif t == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
  elseif t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    out[#out + 1] = "t" .. #keys .. ";"
    for _, k in ipairs(keys) do Ser(k, out); Ser(v[k], out) end
  end
end
-- Reads one value starting at position i. Returns the value and the next position, or nil on any malformed input.
local function Des(s, i, depth)
  if depth > 4 then return nil end
  local c = s:sub(i, i)
  if c == "n" then
    local num, e = s:match("^([%-%+%d%.eE]+);()", i + 1)
    num = tonumber(num)
    if not num or num ~= num or num == math.huge or num == -math.huge then return nil end
    return num, e
  elseif c == "b" then
    local d = s:sub(i + 1, i + 1)
    if d == "1" then return true, i + 2 elseif d == "0" then return false, i + 2 end
    return nil
  elseif c == "s" then
    local len, e = s:match("^(%d+):()", i + 1)
    len = tonumber(len)
    if not len or len > 200 or e + len - 1 > #s then return nil end
    return s:sub(e, e + len - 1), e + len
  elseif c == "t" then
    local cnt, e = s:match("^(%d+);()", i + 1)
    cnt = tonumber(cnt)
    if not cnt or cnt > 200 then return nil end
    local tbl = {}
    for _ = 1, cnt do
      local k, v
      k, e = Des(s, e, depth + 1); if k == nil then return nil end
      v, e = Des(s, e, depth + 1); if v == nil then return nil end
      tbl[k] = v
    end
    return tbl, e
  end
  return nil
end
local SKIP_ON_IMPORT = { fontName = true, fontPath = true }   -- another player's fonts may not exist here
local PREFIX = "CHUD-THEME:1:"

-- The shareable text for a built-in or saved theme (by name), or for the current look when name is nil.
function ns.ExportTheme(name)
  local data = name and ns.GetThemeData(name) or ns.SnapshotTheme()
  local out = {}
  Ser({ name = name or "Custom", data = data }, out)
  return PREFIX .. B64Encode(table.concat(out))
end

-- Reads a theme code and saves it as a new theme. Returns the saved name, or nil and a message.
function ns.ImportTheme(code)
  if type(code) ~= "string" then return nil, "Paste a theme code first." end
  code = code:gsub("%s", "")
  if code:sub(1, #PREFIX) ~= PREFIX then return nil, "That is not a CHUD theme code." end
  local raw = B64Decode(code:sub(#PREFIX + 1))
  if not raw or raw == "" then return nil, "The code is damaged or cut short." end
  local payload = Des(raw, 1, 0)
  if type(payload) ~= "table" or type(payload.data) ~= "table" then return nil, "The code is damaged or cut short." end
  local clean, count = {}, 0
  for _, k in ipairs(KEYS) do
    local v, dflt = payload.data[k], ns.defaults[k]
    if v ~= nil and not SKIP_ON_IMPORT[k] and type(v) == type(dflt) then
      if type(dflt) == "table" then
        local t, good = {}, true
        for i = 1, #dflt do
          if type(v[i]) == "number" then t[i] = v[i] else good = false end
        end
        if good then clean[k] = t; count = count + 1 end
      elseif type(v) ~= "string" or #v <= 64 then
        clean[k] = v; count = count + 1
      end
    end
  end
  if count < 5 then return nil, "That code has no usable theme settings." end
  local name = type(payload.name) == "string" and payload.name:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
  if name == "" then name = "Imported" end
  name = name:sub(1, 24)
  ns.db.themes = ns.db.themes or {}
  local base, n = name, 1
  while BUILTIN[name] or ns.db.themes[name] do
    n = n + 1
    name = base:sub(1, 20) .. " (" .. n .. ")"
  end
  ns.db.themes[name] = clean
  if ns.OnSettingsChanged then ns.OnSettingsChanged() end
  return name
end
ns._ThemeCodec = { Ser = Ser, Des = Des, B64Encode = B64Encode, B64Decode = B64Decode }

-- Keeps Daylight in step with the game clock: when the half-hour has changed, the new colors are applied. The first check
-- runs right away (so login catches up), then one every 30 real seconds.
local dayAcc = 30
local dayFrame = CreateFrame("Frame")
dayFrame:SetScript("OnUpdate", function(_, elapsed)
  dayAcc = dayAcc + elapsed
  if dayAcc < 30 then return end
  local db = ns.db
  if not db then return end
  dayAcc = 0
  if db.daylight and db.dayBucket ~= DayBucket() then
    ApplyDaylightColors()
    ns.Apply()
    if ns.RefreshSettings then ns.RefreshSettings() end
  end
end)
