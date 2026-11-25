local ADDON, ns = ...

-- Markers: icons on the compass that point toward quests, rares/treasures and gathering spots.
--
-- Data sources (all queried with pcall; a missing or changed API just means no markers of that kind):
--   tracked   super-tracked quest waypoint, or the map waypoint you are tracking
--   objective quests in your log that have a POI on the current map (turn-ins use the same option)
--   giver     quests you could pick up here
--   (When Questie is installed its map icons replace the game's own quest POIs for objective / turn-in / giver.)
--   rare / treasure   "vignettes": the game's own rare/treasure/event markers
--   herb / ore / box  node positions from GatherLite or GatherMate2 (+ GatherMate2_Data), imported into CHUD's own saved
--                     copy, plus the spots you recorded yourself by gathering. There is no API for live nodes, so these
--                     are where nodes usually are, not nodes known to exist right now. The nearest few of each kind show.
--   gnext     the Next Node pointer: the nearest unvisited node, drawn large. Reaching it (or Highlight.lua deciding it is gone)
--             moves it on; visited nodes return after 10 minutes (chests 20).
--   rare      rare NPC spawn points and patrol paths from CHUD's own RareData.lua (RareScanner and Questie data).
--   corpse / party   your corpse while a ghost, and party members (smoothed between the game's position updates).
--
-- How a bearing is found: the player's and the target's position on one map, scaled by that map's
-- size in yards, gives a vector. bearing = atan2(east, north). Targets on another map are moved
-- onto the player's map through world coordinates, so no world-axis conventions are needed.

-- If the game ever drops one of these API tables, an empty stand-in keeps every call below harmless
-- (Try() skips a missing function) instead of raising an error.
local C_Map, C_QuestLog, C_VignetteInfo = C_Map or {}, C_QuestLog or {}, C_VignetteInfo or {}

local floor, abs, min, max, sqrt = math.floor, math.abs, math.min, math.max, math.sqrt
local deg = math.deg
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local MAX_ICONS = 24
local FOCUS_SCALE = 1.3   -- the focused (primary) icon is this much larger than a normal one, but never taller than the bar
local FADE_SHRINK = 0.30  -- a quest giver or objective at its fade distance is this much smaller than normal ...
local FADE_ALPHA = 0.50    -- ... and this much more transparent (both ease in with distance)
-- Which setting holds the fade distance for each kind, and its default (yards).
local FADE_RANGE = { giver = { "mk_giverRange", 300 }, objective = { "mk_objRange", 300 } }
local FAR_SCALE = 0.6     -- an icon at its maximum range is this fraction of normal size (when Smaller When Far is on)
local TICK = 0.25       -- seconds between bearing updates
local REFRESH = 4.0     -- seconds between full re-queries (events and the Questie callback also trigger one)
local MIN_REBUILD = 1.0 -- seconds between re-queries caused by quest-log, vignette and Questie updates, which arrive in bursts
local RESCAN = 5        -- yards the player must move before every target is scanned again; in between, only the icons on the bar are updated
local MAX_NODES = 500   -- recorded spots kept per kind per map
local DEDUPE = 15       -- yards: a new gather within this of a recorded spot is the same spot

-- Which setting turns each kind on.
local OPTION = {
  tracked = "mk_tracked", objective = "mk_objectives", turnin = "mk_objectives", giver = "mk_givers",
  rare = "mk_rares", treasure = "mk_treasures", corpse = "mk_corpse", party = "mk_party", herb = "mk_herbs", ore = "mk_ore", box = "mk_containers",
}

-- Icons: atlases are tried in order, then the fallback file. Vignettes bring their own atlas.
local ICON = {
  tracked   = { atlases = { "Waypoint-MapPin-Tracked", "Waypoint-MapPin-ChatIcon" }, file = "Interface\\Icons\\INV_Misc_Map_01", crop = true },
  objective = { atlases = { "QuestObjective", "QuestNormal" }, file = "Interface\\GossipFrame\\AvailableQuestIcon" },
  turnin    = { atlases = { "QuestTurnin" }, file = "Interface\\GossipFrame\\ActiveQuestIcon" },
  giver     = { atlases = { "QuestNormal" }, file = "Interface\\GossipFrame\\AvailableQuestIcon" },
  rare      = { atlases = { "VignetteKill" }, file = "Interface\\Icons\\INV_Misc_Bone_Skull_01", crop = true },
  treasure  = { atlases = { "VignetteLoot" }, file = "Interface\\Icons\\INV_Misc_Bag_10", crop = true },
  herb      = { file = "Interface\\Icons\\Trade_Herbalism", crop = true },
  ore       = { file = "Interface\\Icons\\Trade_Mining", crop = true },
  box       = { file = "Interface\\Icons\\INV_Box_01", crop = true },
  gnext     = { atlases = { "Waypoint-MapPin-Untracked", "Waypoint-MapPin-ChatIcon" }, file = "Interface\\Icons\\INV_Misc_Map_01", crop = true },
  corpse    = { atlases = { "poi-graveyard-neutral" }, file = "Interface\\Icons\\Spell_Shadow_AnimateDead", crop = true },
  party     = { file = "Interface\\Icons\\INV_Misc_QuestionMark", crop = true },   -- real icon is chosen per member (role, else class)
}

local partyT = {}    -- the party-member targets (their positions are refreshed every Tick, since members move while you stand still)
local targets = {}   -- every candidate: { kind, mapID, x, y, label, atlas?, primary? }
local active = {}    -- candidates in range this tick, primary first then nearest first
local icons = {}     -- frame pool
local needRebuild = true   -- targets are out of date; honoured at most once per MIN_REBUILD seconds (events come in bursts)
local forceRebuild = true  -- same, but honoured at the next tick (option changes, focus changes, a new map)
local tickDirty = true   -- something other than the player's position changed (targets rebuilt, options): Tick must run
local tickPm, tickPX, tickPY   -- map and position at the last full Tick; while all three are unchanged and nothing is dirty, Tick has nothing new

-- Calls fn under pcall and returns its results, or nothing if it is missing or errors (the game may drop or change an API).
local function Try(fn, ...)
  if type(fn) ~= "function" then return end
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
end
-- True for a real, readable number (not a secret value the game hides in combat).
local function Num(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end
-- True when the menu option for this marker kind is ticked.
local function On(kind) local db = ns.db; return db and db[OPTION[kind]] end
-- True when at least one marker kind is switched on (nothing is gathered otherwise).
local function AnyOn()
  local db = ns.db
  if not db then return false end
  for _, key in pairs(OPTION) do if db[key] then return true end end
  return false
end
-- Reads x, y from a map position vector; nil when it is missing or unreadable.
local function XY(vec)
  if not vec then return end
  local ok, x, y = pcall(vec.GetXY, vec)
  if ok and Num(x) and Num(y) then return x, y end
end

-- Questie ------------------------------------------------------------------------------------
-- When Questie is installed, its map icons are the source for quest objectives, turn-ins and quest
-- givers. Questie's public API (Questie.API) only offers readiness and quest-change callbacks, so
-- icon positions come from its map frame registry (QuestieMap.questIdFrames). That table is internal
-- to Questie: every access is guarded, so if it changes, Questie support quietly turns itself off
-- and the game's own quest data is used instead.
-- CHUD only READS Questie's data. The one thing it hands Questie is a callback through Questie's own
-- RegisterForQuestUpdates, which is how Questie asks other addons to listen.
local Q = { map = nil, kinds = nil, hooked = false }
local qcache = setmetatable({}, { __mode = "k" })   -- Questie icon frame -> its reusable target table
local questieActive = false

local function QuestieReady()
  local Qe = _G.Questie
  if not (type(Qe) == "table" and type(Qe.API) == "table" and Qe.API.isReady) then return end
  if not Q.map then
    local L = _G.QuestieLoader
    if type(L) == "table" and L.ImportModule then
      Q.map = Try(L.ImportModule, L, "QuestieMap")
    end
    if type(Q.map) ~= "table" then Q.map = nil; return end
  end
  if not Q.kinds then
    -- Questie icon type number -> the marker kind CHUD uses. Types not listed (glows, nodes, chests...) are ignored.
    local k = {}
    local function set(names, kind)
      for _, n in ipairs(names) do
        local v = Qe[n]
        if type(v) == "number" then k[v] = kind end
      end
    end
    set({ "ICON_TYPE_AVAILABLE", "ICON_TYPE_AVAILABLE_GRAY", "ICON_TYPE_REPEATABLE", "ICON_TYPE_EVENTQUEST",
      "ICON_TYPE_PVPQUEST" }, "giver")
    set({ "ICON_TYPE_COMPLETE", "ICON_TYPE_REPEATABLE_COMPLETE", "ICON_TYPE_EVENTQUEST_COMPLETE",
      "ICON_TYPE_PVPQUEST_COMPLETE" }, "turnin")
    set({ "ICON_TYPE_SLAY", "ICON_TYPE_LOOT", "ICON_TYPE_EVENT", "ICON_TYPE_OBJECT", "ICON_TYPE_TALK",
      "ICON_TYPE_INTERACT" }, "objective")
    Q.kinds = k
  end
  if not Q.hooked then
    Q.hooked = true
    -- Questie tells us when a quest is accepted, updated, turned in or abandoned.
    Try(Qe.API.RegisterForQuestUpdates, function()
      needRebuild = true
      -- Questie draws its icons a moment after the event, so look again shortly after.
      if C_Timer and C_Timer.After then C_Timer.After(1, function() needRebuild = true end) end
    end)
  end
  return Qe
end

local function UseQuestie() return ns.db and ns.db.mk_questie ~= false and QuestieReady() end

-- The quest the player has focused. The game's super-tracked quest is the single source of truth: Questie
-- follows it, and so does CHUD, so the two can never disagree. Questie's own focus (read only) is used just
-- when the client has no super-tracking at all.
local function FocusedQuest()
  local ST = C_SuperTrack
  if ST and type(ST.GetSuperTrackedQuestID) == "function" then
    local sq = Try(ST.GetSuperTrackedQuestID)
    if Num(sq) and sq > 0 then return sq end
    return nil
  end
  local Qe = _G.Questie
  local f = type(Qe) == "table" and type(Qe.db) == "table" and type(Qe.db.char) == "table" and Qe.db.char.TrackerFocus
  if Num(f) and f > 0 then return f end
end

-- Does the client tell us whether the player is inside a quest's area (the blue blob on the map)?
-- C_Minimap.IsInsideQuestBlob is how retail reports it; if this client lacks it, the glow just never shows.
local function AreaApi()
  return C_Minimap and type(C_Minimap.IsInsideQuestBlob) == "function"
end
ns.QuestAreaSupported = AreaApi

-- Target collection (runs on events and every REFRESH seconds) ----------------------------------

-- The player's map, plus up to two parent zone maps, so quests shown on the zone map are found
-- while standing in a sub-area. Stops before continent level.
local function MapChain(mapID)
  local list, cur = { mapID }, mapID
  for _ = 1, 2 do
    local info = Try(C_Map.GetMapInfo, cur)
    if not info or not info.parentMapID or info.parentMapID == 0 then break end
    local pinfo = Try(C_Map.GetMapInfo, info.parentMapID)
    if not pinfo or (pinfo.mapType and pinfo.mapType <= 2) then break end   -- 2 = continent
    cur = info.parentMapID
    list[#list + 1] = cur
  end
  return list
end

-- The game's waypoint for a quest on a map: mapID, x, y, or nothing.
local function QuestWaypoint(qid, pm)
  local a, b, c = Try(C_QuestLog and C_QuestLog.GetNextWaypoint, qid)
  if Num(a) and Num(b) and Num(c) then return a, b, c end
  local x, y = Try(C_QuestLog and C_QuestLog.GetNextWaypointForMap, qid, pm)
  if Num(x) and Num(y) then return pm, x, y end
  local list = Try(C_QuestLog and C_QuestLog.GetQuestsOnMap, pm)
  if type(list) == "table" then
    for _, q in ipairs(list) do
      if q.questID == qid and Num(q.x) and Num(q.y) then return pm, q.x, q.y end
    end
  end
end

local trackedQuest
-- Adds the tracked quest or map waypoint as the primary marker.
local function AddTracked(pm)
  trackedQuest = nil
  local ST = C_SuperTrack
  if not ST then return end
  if Try(ST.IsSuperTrackingUserWaypoint) then
    local pt = Try(C_Map.GetUserWaypoint)
    if pt and pt.uiMapID and pt.position then
      local x, y = XY(pt.position)
      if x then
        targets[#targets + 1] = { kind = "tracked", mapID = pt.uiMapID, x = x, y = y, label = "Waypoint", primary = true }
        return
      end
    end
  end
  local qid = Try(ST.GetSuperTrackedQuestID)
  if Num(qid) and qid > 0 then
    local mapID, x, y = QuestWaypoint(qid, pm)
    if mapID then
      trackedQuest = qid
      targets[#targets + 1] = { kind = "tracked", mapID = mapID, x = x, y = y, primary = true, questID = qid,
        label = Try(C_QuestLog.GetTitleForQuestID, qid) or "Tracked Quest" }
    end
  end
end

-- Adds quest objectives, turn-ins and quest givers from the game's own quest POIs.
local function AddQuests(chain)
  local seen = {}
  for _, mapID in ipairs(chain) do
    local list = Try(C_QuestLog and C_QuestLog.GetQuestsOnMap, mapID)
    if type(list) == "table" then
      for _, q in ipairs(list) do
        local qid = q.questID
        if Num(qid) and not seen[qid] and qid ~= trackedQuest and Num(q.x) and Num(q.y) then
          seen[qid] = true
          local kind
          if Try(C_QuestLog.IsOnQuest, qid) then
            kind = Try(C_QuestLog.IsComplete, qid) and "turnin" or "objective"
          elseif q.isQuestStart then
            kind = "giver"
          end
          if kind and On(kind) then
            targets[#targets + 1] = { kind = kind, mapID = mapID, x = q.x, y = q.y, questID = qid,
              label = Try(C_QuestLog.GetTitleForQuestID, qid) }
          end
        end
      end
    end
  end
end

-- Questie's icons for the player's map. Questie draws one icon per spawn (on both the world map and the
-- minimap, and an icon can be hidden on one but not the other), so each quest and icon type is grouped here and
-- Tick keeps only the nearest of each group, which keeps the bar readable.
-- The focused quest keeps all of its icons like any other quest. When the game gave no waypoint for it, its
-- nearest icon is also promoted to the large primary marker (Tick does that, since "nearest" changes as you move).
local function AddQuestie(chain, focus)
  local Qe = _G.Questie
  local frames = Q.map.questIdFrames
  if type(frames) ~= "table" then return end
  local onMap = {}
  for _, m in ipairs(chain) do onMap[m] = true end
  local focusOnly = ns.db.mk_qFocusOnly
  local trackedOn = On("tracked")
  for qid, names in pairs(frames) do
    if Num(qid) and (qid == focus or not focusOnly) and type(names) == "table" then
      local promote = trackedOn and qid == focus and qid ~= trackedQuest   -- no game waypoint for it: Questie provides the primary
      local title   -- looked up once per quest, not once per icon
      for _, name in pairs(names) do
        local fr = _G[name]
        local d = type(fr) == "table" and fr.data
        if d and not fr.hidden and onMap[fr.UiMapID] and Num(fr.x) and Num(fr.y) then
          local kind = Q.kinds[d.Icon]
          local shows = kind and On(kind)
          if kind and (shows or promote) then
            local t = qcache[fr]
            if not t then t = {}; qcache[fr] = t end
            t.kind, t.baseKind, t.shows = kind, kind, shows
            t.mapID, t.x, t.y, t.questID, t.src = fr.UiMapID, fr.x / 100, fr.y / 100, qid, "questie"
            t.focus, t.primary = promote or nil, nil
            t.file = type(Qe.usedIcons) == "table" and Qe.usedIcons[d.Icon] or nil   -- Questie's art for this objective type (bag, sword...)
            if t.gq ~= qid or t.gi ~= d.Icon then   -- the group key is a string, so build it only when it changes
              t.gq, t.gi = qid, d.Icon
              t.group = "q" .. qid .. ":" .. tostring(d.Icon)
            end
            if title == nil then
              local qd = d.QuestData
              title = Try(C_QuestLog.GetTitleForQuestID, qid) or (type(qd) == "table" and type(qd.name) == "string" and qd.name) or false
            end
            t.label = title or nil
            targets[#targets + 1] = t
          end
        end
      end
    end
  end
end

-- Adds rare and treasure markers from the game's vignettes on this map.
local function AddVignettes(pm)
  local V = C_VignetteInfo
  if not V then return end
  local guids = Try(V.GetVignettes)
  if type(guids) ~= "table" then return end
  for _, guid in ipairs(guids) do
    local info = Try(V.GetVignetteInfo, guid)
    if info and not info.isDead and type(info.atlasName) == "string" and not (issecretvalue and issecretvalue(info.atlasName)) then
      local a = info.atlasName:lower()
      local kind
      if a:find("kill") or a:find("elite") or a:find("rare") then kind = "rare"
      elseif a:find("loot") or a:find("chest") or a:find("treasure") then kind = "treasure" end
      if kind and On(kind) then
        local x, y = XY(Try(V.GetVignettePosition, guid, pm))
        if x then
          targets[#targets + 1] = { kind = kind, mapID = pm, x = x, y = y, label = info.name, atlas = info.atlasName }
        end
      end
    end
  end
end

-- Gathering nodes ------------------------------------------------------------------------------------------------
-- Herbs, ore and chests. CHUD keeps its own copy of the node data (db.gdata), filled by the Import button from whatever is
-- installed: GatherMate2 (+ its GatherMate2_Data addon) and GatherLite. Once imported, the other addons are no longer needed.
-- Until then the installed addons are read directly. Of all the nodes, only the nearest of each kind shows on the bar, plus
-- one "Next Node" pointer that walks you from node to node (nodes you reach or skip are left out for a while).
local KINDS = { "herb", "ore", "box" }
local GM_TYPES = { ["Herb Gathering"] = "herb", Mining = "ore", Treasure = "box" }
local GM_RAW = { ["Herb Gathering"] = "GatherMateData2HerbDB", Mining = "GatherMateData2MineDB" }
local GL_KINDS = { herbalism = "herb", mining = "ore", containers = "box" }
local GM_REFRESH = 30     -- seconds between re-reading the sources for the current map
local VISIT_R = 12        -- yards: a node this close counts as reached
local BOX_HOLD = 1200     -- chests and containers: a longer wait before they return (20 min, a guess, no published figure)
local VISIT_HOLD = 600    -- seconds a reached or skipped node stays off the bar, then it comes back on its own (respawn time is not published; observed times vary roughly 5 to 20+ minutes)
local GLOW_R = 40         -- yards: the Next Node pointer glows this close, so you know to look around
local gmCache = { pm = nil, sig = nil, t = -999, list = {} }
local visited = {}        -- key -> GetTime() it was reached
local gnextT              -- the single Next Node target

-- True when the named addon is loaded.
local function Loaded(name) return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) or false end
-- The GatherMate2 addon object when it is loaded and usable, else nil.
local function GM2()
  if not Loaded("GatherMate2") then return nil end
  local AA = LibStub and LibStub("AceAddon-3.0", true)
  local gm = AA and AA:GetAddon("GatherMate2", true)
  return (gm and gm.gmdbs and gm.GetNodesForZone) and gm or nil
end
-- True when GatherMate2_Data is loaded or can be loaded on demand.
local function DataAddonUsable()
  if Loaded("GatherMate2_Data") then return true end
  if not (C_AddOns and C_AddOns.GetAddOnInfo) then return false end
  local ok, name = pcall(C_AddOns.GetAddOnInfo, "GatherMate2_Data")
  if not (ok and name) then return false end
  if C_AddOns.GetAddOnEnableState then
    local ok2, st = pcall(C_AddOns.GetAddOnEnableState, "GatherMate2_Data", UnitName("player"))
    if ok2 and type(st) == "number" then return st > 0 end
  end
  return true
end
-- The GatherLite addon object when it is loaded and usable, else nil.
local function GL()
  local g = _G.GatherLite
  return (Loaded("GatherLite") and type(g) == "table" and g.GetNodesForMap) and g or nil
end
-- Which sources exist right now, and what CHUD's own copy holds (the marker menu shows both).
function ns.GatherSources()
  local g = ns.db and ns.db.gdata
  return { gm2 = GM2() ~= nil, data = DataAddonUsable(), gl = GL() ~= nil, own = g, }
end

-- A string of the settings and data version that decide which gathering nodes exist, so a rebuild can tell when it must re-read them.
local function Sig(db)
  local g = db.gdata
  return table.concat({ tostring(db.mk_gm2 ~= false), tostring(db.mk_gm2data ~= false), tostring(db.mk_gl ~= false),
    tostring(db.mk_gmFilter ~= false), tostring(On("herb") and true), tostring(On("ore") and true), tostring(On("box") and true),
    g and tostring(g.at) or "-" }, ":")
end

-- Packs a map position into one integer key (4 decimals each), used to identify a node.
local function Encode(x, y)
  if x > 0.9999 then x = 0.9999 end
  if y > 0.9999 then y = 0.9999 end
  return floor(x * 10000 + 0.5) * 1000000 + floor(y * 10000 + 0.5) * 100
end
-- Unpacks a key made by Encode back into x, y.
local function Decode(c) return floor(c / 1000000) / 10000, floor(c % 1000000 / 100) / 10000 end

-- Turns an internal name like "silver_vein" into "Silver Vein".
local function Pretty(key)
  if type(key) ~= "string" then return nil end
  return (key:gsub("_", " "):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- Re-reads the nodes for map pm. Entries are kept between Rebuilds (the Tick writes distance fields into them).
local function GatherList(pm)
  local db = ns.db
  local sig = Sig(db)
  local now = GetTime()
  if gmCache.pm == pm and gmCache.sig == sig and now - gmCache.t < GM_REFRESH then return gmCache.list end
  local old = {}
  for _, t in ipairs(gmCache.list) do old[t.key] = t end
  local list, seen = {}, {}
  local function add(kind, coord, x, y, label, src)
    local key = kind .. ":" .. pm .. ":" .. coord
    if seen[key] then return end
    seen[key] = true
    local t = old[key] or { kind = kind, mapID = pm, key = key }
    t.x, t.y, t.label, t.sub, t.group, t.gather = x, y, label, src, "gm:" .. kind, true
    list[#list + 1] = t
  end
  local own = db.gdata
  if own and own.kinds then
    -- CHUD's own copy, made by the Import button
    for _, kind in ipairs(KINDS) do
      local z = On(kind) and own.kinds[kind] and own.kinds[kind][pm]
      if z then
        for i = 1, #z.c do
          local x, y = Decode(z.c[i])
          add(kind, z.c[i], x, y, own.names[z.n[i]], "CHUD data")
        end
      end
    end
  else
    -- Not imported yet: read the installed addons directly
    local useFilter = db.mk_gmFilter ~= false
    local gm = GM2()
    if gm then
      local function pull(typeName, kind, tbl, src)
        if not tbl then return end
        local f = useFilter and gm.db and gm.db.profile and gm.db.profile.filter and gm.db.profile.filter[typeName]
        for coord, id in pairs(tbl) do
          if not f or f[id] then
            local x, y = gm:DecodeLoc(coord)
            add(kind, coord, x, y, gm:GetNameForNode(typeName, id), src)
          end
        end
      end
      for typeName, kind in pairs(GM_TYPES) do
        if On(kind) then
          if db.mk_gm2 ~= false then pull(typeName, kind, gm.gmdbs[typeName][pm], "GatherMate2") end
          if GM_RAW[typeName] and db.mk_gm2data ~= false and DataAddonUsable() then
            if not Loaded("GatherMate2_Data") and not gmCache.triedData then
              gmCache.triedData = true
              pcall(C_AddOns.LoadAddOn, "GatherMate2_Data")   -- load on demand; its tables are only read
            end
            local raw = _G[GM_RAW[typeName]]
            pull(typeName, kind, type(raw) == "table" and raw[pm] or nil, "GatherMate2 data")
          end
        end
      end
    end
    local gl = GL()
    if gl and db.mk_gl ~= false then
      for typeName, kind in pairs(GL_KINDS) do
        if On(kind) then
          local nodes = Try(gl.GetNodesForMap, gl, typeName, pm)
          if type(nodes) == "table" then
            for i = 1, #nodes do
              local n = nodes[i]
              if type(n) == "table" and Num(n.posX) and Num(n.posY) then
                local obj = n.object and Try(gl.GetNodeObject, gl, n.object)
                local name = type(obj) == "table" and Pretty(obj.name) or nil
                add(kind, Encode(n.posX, n.posY), n.posX, n.posY, name, "GatherLite")
              end
            end
          end
        end
      end
    end
  end
  gmCache.pm, gmCache.sig, gmCache.t, gmCache.list = pm, sig, now, list
  return list
end

-- The import ------------------------------------------------------------------------------------------------------
-- Copies every herb, ore and chest node from the installed addons into CHUD's own saved data. Nodes of different sources
-- that sit within about 8 yards of each other count as one (the first source wins, GatherMate2 before GatherLite).
-- Returns a one-line summary per source, and stores the result in db.gdata.
function ns.ImportGatherData()
  local db = ns.db
  if not db then return { "CHUD is not ready." } end
  local data = { v = 1, at = date("%Y-%m-%d %H:%M"), names = {}, kinds = { herb = {}, ore = {}, box = {} }, counts = { herb = 0, ore = 0, box = 0 }, src = {} }
  local nameIdx, grid = {}, {}
  local CELL = 0.003
  local function nid(name)
    name = (type(name) == "string" and name ~= "") and name or "Node"
    local i = nameIdx[name]
    if not i then i = #data.names + 1; data.names[i] = name; nameIdx[name] = i end
    return i
  end
  -- Herbs and ore are never found inside a capital city, but some source data places them there. Those points are skipped.
  local CITY_MAPS = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true, [1947] = true, [1954] = true }
  local cityCache, skippedCity = {}, 0
  local function IsCity(pm)
    local c = cityCache[pm]
    if c == nil then
      local info = C_Map and C_Map.GetMapInfo and Try(C_Map.GetMapInfo, pm)
      local cityType = Enum and Enum.UIMapType and Enum.UIMapType.City or 5
      c = CITY_MAPS[pm] == true or (type(info) == "table" and info.mapType == cityType)
      cityCache[pm] = c
    end
    return c
  end
  local function add(kind, pm, x, y, name)
    if not (Num(pm) and Num(x) and Num(y)) or x <= 0 or y <= 0 or x >= 1 or y >= 1 then return false end
    if kind ~= "box" and IsCity(pm) then skippedCity = skippedCity + 1; return false end
    local gk = kind .. pm
    local g = grid[gk]; if not g then g = {}; grid[gk] = g end
    local cx, cy = floor(x / CELL), floor(y / CELL)
    for dx = -1, 1 do
      for dy = -1, 1 do
        local cell = g[(cx + dx) * 4096 + (cy + dy)]
        if cell then
          for i = 1, #cell, 2 do
            local ex, ey = cell[i], cell[i + 1]
            if (ex - x) ^ 2 + (ey - y) ^ 2 < 0.0025 ^ 2 then return false end
          end
        end
      end
    end
    local ck = cx * 4096 + cy
    local cell = g[ck]; if not cell then cell = {}; g[ck] = cell end
    cell[#cell + 1], cell[#cell + 2] = x, y
    local zs = data.kinds[kind]
    local z = zs[pm]; if not z then z = { c = {}, n = {} }; zs[pm] = z end
    z.c[#z.c + 1] = Encode(x, y); z.n[#z.n + 1] = nid(name)
    data.counts[kind] = data.counts[kind] + 1
    return true
  end
  local report = {}
  -- A refresh only ever adds: everything CHUD already holds is carried over first, so a source that returns nothing right now
  -- (an addon turned off, a tracking type switched off in GatherLite) can never wipe out what an earlier import found.
  local old = db.gdata
  if type(old) == "table" and type(old.kinds) == "table" and type(old.names) == "table" then
    local kept = 0
    for kind, zones in pairs(old.kinds) do
      if data.kinds[kind] then
        for pm, z in pairs(zones) do
          if type(z) == "table" and type(z.c) == "table" and type(z.n) == "table" then
            for i = 1, #z.c do
              local x, y = Decode(z.c[i])
              if add(kind, pm, x, y, old.names[z.n[i]]) then kept = kept + 1 end
            end
          end
        end
      end
    end
    if kept > 0 then report[#report + 1] = format("Kept the %d nodes CHUD already had.", kept) end
  end
  local gm = GM2()
  if gm then
    if DataAddonUsable() and not Loaded("GatherMate2_Data") then pcall(C_AddOns.LoadAddOn, "GatherMate2_Data") end
    local fromData = 0
    for typeName, rawName in pairs(GM_RAW) do
      local raw = _G[rawName]
      if type(raw) == "table" then
        for pm, nodes in pairs(raw) do
          for coord, id in pairs(nodes) do
            local x, y = gm:DecodeLoc(coord)
            if add(GM_TYPES[typeName], pm, x, y, gm:GetNameForNode(typeName, id)) then fromData = fromData + 1 end
          end
        end
      end
    end
    local fromLive = 0
    for typeName, kind in pairs(GM_TYPES) do
      local meta = gm.gmdbs[typeName]
      local base = meta and meta.__gm2_base_storage
      if type(base) == "table" then
        for pm, nodes in pairs(base) do
          for coord, id in pairs(nodes) do
            local x, y = gm:DecodeLoc(coord)
            if add(kind, pm, x, y, gm:GetNameForNode(typeName, id)) then fromLive = fromLive + 1 end
          end
        end
      end
    end
    report[#report + 1] = format("GatherMate2: %d nodes from GatherMate2_Data%s, %d from your own GatherMate2 database", fromData,
      (fromData == 0 and not DataAddonUsable()) and " (addon not found)" or "", fromLive)
    data.src[#data.src + 1] = "GatherMate2"
  else
    report[#report + 1] = "GatherMate2: not detected (folder name GatherMate2)"
  end
  local gl = GL()
  if gl then
    local counts = { herb = 0, ore = 0, box = 0 }
    -- GatherLite only loads a node type while that type is tracked for the current character on its minimap or world map.
    -- A type that is off is switched on for the length of this import so its nodes load, then put back exactly as it was.
    local function Tracked(t)
      -- The HUD is left out: GatherLite reports it as tracked by default even while the HUD is off and loads nothing for it.
      for _, where in ipairs({ "minimap", "worldmap" }) do
        if Try(gl.GetNodeTracking, gl, where, t) then return true end
      end
      return false
    end
    local char = gl.db and gl.db.char
    local manualBefore = char and char.professionTrackingManual   -- SetNodeTracking flags this; it is put back below
    local flipped = {}
    if gl.SetNodeTracking and gl.GetNodeTracking then
      for typeName in pairs(GL_KINDS) do
        if not Tracked(typeName) then
          flipped[#flipped + 1] = typeName
          Try(gl.SetNodeTracking, gl, "worldmap", typeName, true)
        end
      end
    end
    local raw = {}
    for typeName, kind in pairs(GL_KINDS) do
      local nodes = Try(gl.GetNodesForMap, gl, typeName)
      raw[#raw + 1] = typeName .. " " .. (type(nodes) == "table" and #nodes or "none")
      if type(nodes) == "table" then
        for i = 1, #nodes do
          local n = nodes[i]
          if type(n) == "table" then
            local obj = n.object and Try(gl.GetNodeObject, gl, n.object)
            local name = type(obj) == "table" and Pretty(obj.name) or nil
            if add(kind, n.mapID, n.posX, n.posY, name) then counts[kind] = counts[kind] + 1 end
          end
        end
      end
    end
    local usePre = gl.db and gl.db.global and gl.db.global.usePredefined
    report[#report + 1] = "GatherLite holds: " .. table.concat(raw, ", ") .. " (built-in node data " .. (usePre == false and "OFF" or "on") .. ")"
    for _, t in ipairs(flipped) do Try(gl.SetNodeTracking, gl, "worldmap", t, false) end
    if char then char.professionTrackingManual = manualBefore end
    if #flipped > 0 then
      report[#report + 1] = "GatherLite had " .. table.concat(flipped, ", ") .. " tracking off for this character. CHUD switched it on only long enough to read the nodes, then put it back."
    end
    report[#report + 1] = format("GatherLite: %d new herbs, %d new ore, %d new chests", counts.herb, counts.ore, counts.box)
    if counts.herb == 0 and counts.ore == 0 then report[#report + 1] = "GatherLite gave no new herbs or ore. Your existing nodes were kept." end
    data.src[#data.src + 1] = "GatherLite"
  else
    report[#report + 1] = "GatherLite: not detected (folder name GatherLite)"
  end
  if skippedCity > 0 then report[#report + 1] = format("Skipped %d herb and ore points that were placed inside cities.", skippedCity) end
  local total = data.counts.herb + data.counts.ore + data.counts.box
  if total == 0 then
    report[#report + 1] = "Nothing was imported. Your existing CHUD data was left as it was."
    return report
  end
  db.gdata = data
  gmCache.sig = nil
  needRebuild, forceRebuild = true, true
  report[#report + 1] = format("CHUD now holds %d herbs, %d ore and %d chests.", data.counts.herb, data.counts.ore, data.counts.box)
  data.report = table.concat(report, "\n")
  return report
end
-- Runs the import and never fails silently: a Lua error becomes a line of text in the report instead of nothing happening.
function ns.ImportGatherDataSafe()
  local ok, res = pcall(ns.ImportGatherData)
  if ok and type(res) == "table" then return res end
  return { "Import failed: " .. tostring(res) }
end
-- Deletes CHUD's imported copy of the herb, ore and chest data (the other addons' own data is never touched) and clears the bar.
-- Nothing imports by itself: the setup tour (/chud install) and the Refresh Gathering Data button are the only ways in.
function ns.ClearGatherData()
  if not ns.db then return end
  ns.db.gdata = nil
  gmCache.sig = nil
  needRebuild, forceRebuild = true, true
end

local function MarkVisited(key) if key then visited[key] = GetTime() end end
local function IsVisited(key)
  local v = visited[key]
  return v ~= nil and GetTime() - v < (key:sub(1, 4) == "box:" and BOX_HOLD or VISIT_HOLD)
end

-- The Next Node pointer: the nearest node not reached recently (of the chosen kind, or any). The current one is kept unless
-- another is clearly closer, so it does not flip between two nodes at a similar distance.
local function NextNode(pm, list, prev)
  local db = ns.db
  if db.mk_gnext == false or #list == 0 then gnextT = nil; return end
  local px, py = XY(Try(C_Map.GetPlayerMapPosition, pm, "player"))
  local w, h = Try(C_Map.GetMapWorldSize, pm)
  if not (px and Num(w) and Num(h) and w > 0) then gnextT = nil; return end
  local only = db.mk_gnextKind
  if only ~= "herb" and only ~= "ore" and only ~= "box" then only = nil end
  local best, bestD, cur, curD
  for i = 1, #list do
    local t = list[i]
    if (not only or t.kind == only) and not IsVisited(t.key) then
      local e, n = (t.x - px) * w, (t.y - py) * h
      local d = e * e + n * n
      if not best or d < bestD then best, bestD = t, d end
      if prev and t.key == prev.key then cur, curD = t, d end
    end
  end
  if not best then gnextT = nil; return end
  -- The current node is kept unless another one is clearly nearer (1.5x the distance), so the pointer does not flip between nodes that are almost equally far.
  if cur and curD <= bestD * 2.25 then best = cur end
  gnextT = prev or { kind = "gnext", primary = true, label = "Next Node" }
  gnextT.mapID, gnextT.x, gnextT.y, gnextT.key = pm, best.x, best.y, best.key
  gnextT.nodeName = best.label or "Node"
  gnextT.nodeKind = best.kind
  gnextT.sub = (best.label or "Node") .. (best.sub and (" - " .. best.sub) or "")
  targets[#targets + 1] = gnextT
end

-- Rare NPCs ------------------------------------------------------------------------------------
-- Spawn points and patrol paths come from CHUD's own RareData.lua (merged from RareScanner and Questie data, with permission;
-- see the credits in README.md). Nothing is read from another addon's files. When RareScanner is enabled, rares it has recorded
-- as killed are hidden until their respawn time. CHUD also records kills itself (your target dying, loot windows and kill XP messages).
local function RSInstalled()
  if not (C_AddOns and C_AddOns.GetAddOnInfo) then return false end
  local ok, name = pcall(C_AddOns.GetAddOnInfo, "RareScanner")
  if not (ok and name) then return false end
  if C_AddOns.GetAddOnEnableState then
    local ok2, st = pcall(C_AddOns.GetAddOnEnableState, "RareScanner", UnitName("player"))
    if ok2 and type(st) == "number" then return st > 0 end
  end
  return true
end
local rsCount
-- installed (RareScanner kill tracking available), data present, number of rares in CHUD's own table
function ns.RareStatus()
  local info = ns.RareData
  if info and not rsCount then
    rsCount = 0
    for _, m in pairs(info) do for _ in pairs(m) do rsCount = rsCount + 1 end end
  end
  return RSInstalled(), info ~= nil, rsCount or 0
end
local rsIndex = {}
-- CHUD's own kill record: { [npcID] = time it comes back }. The respawn time is a guess (no published figure).
local RARE_RESPAWN = 1800
local rareIds
-- Records a rare as killed, by NPC id or by name (looked up on the map you are on). Unknown NPCs are ignored.
function ns.NoteRareKill(id, name)
  local db, data = ns.db, ns.RareData
  if not (db and data) then return end
  if not id and type(name) == "string" and name ~= "" then
    local pm = C_Map and C_Map.GetBestMapForUnit and Try(C_Map.GetBestMapForUnit, "player")
    local m = pm and data[pm]
    if m then for nid, n in pairs(m) do if n[2] == name then id = nid; break end end end
  end
  if not id then return end
  if not rareIds then
    rareIds = {}
    for _, m in pairs(data) do for nid in pairs(m) do rareIds[nid] = true end end
  end
  if not rareIds[id] then return end
  db.rareKilled = db.rareKilled or {}
  db.rareKilled[id] = time() + RARE_RESPAWN
  needRebuild = true
end
-- True while this rare is recorded as killed (by CHUD, or by RareScanner when it is installed) and has not yet respawned.
local function RSKilled(id)
  local own = ns.db and ns.db.rareKilled and ns.db.rareKilled[id]
  if own then
    if own > time() then return true end
    ns.db.rareKilled[id] = nil
  end
  local AA = LibStub and LibStub("AceAddon-3.0", true)
  local rs = AA and AA:GetAddon("RareScanner", true)
  local k = rs and rs.db and rs.db.char and rs.db.char.rares_killed
  local v = type(k) == "table" and k[id] or nil
  if v == nil then return false end
  if type(v) == "number" and v > 0 and v < time() then return false end   -- its respawn time has passed
  return true
end
-- The rare NPCs on a map, indexed once per map and cached. Each rare keeps all its points (a patrol path can have a dozen) and is
-- drawn as one marker at the point nearest to you.
local function RSList(pm)
  local list = rsIndex[pm]
  if list then return list end
  local map = ns.RareData and ns.RareData[pm]
  if not map then return nil end
  list = {}
  for id, n in pairs(map) do
    local pts = n[3]
    if #pts >= 2 then
      list[#list + 1] = { kind = "rare", mapID = pm, x = pts[1] / 10000, y = pts[2] / 10000, key = "rs:" .. id, group = "rs:" .. id,
        npcID = id, level = n[1] > 0 and n[1] or nil, label = n[2] ~= "" and n[2] or "Rare NPC", pts = pts }
    end
  end
  rsIndex[pm] = list
  return list
end
-- Adds one marker per known rare NPC on this map (at the patrol point nearest you), skipping rares you have killed.
local function AddRares(pm)
  local db = ns.db
  if not (db and On("rare") and db.mk_rsData ~= false) then return end
  local list = RSList(pm)
  if not list then return end
  local px, py = XY(Try(C_Map.GetPlayerMapPosition, pm, "player"))
  for i = 1, #list do
    local t = list[i]
    if not RSKilled(t.npcID) then
      local pts = t.pts
      if px and #pts > 2 then
        local best, bi = nil, 1
        for k = 1, #pts - 1, 2 do
          local dx, dy = pts[k] / 10000 - px, pts[k + 1] / 10000 - py
          local d = dx * dx + dy * dy
          if not best or d < best then best, bi = d, k end
        end
        t.x, t.y = pts[bi] / 10000, pts[bi + 1] / 10000
      end
      t.sub = t.level and ("Level " .. t.level .. " rare") or "Rare"
      targets[#targets + 1] = t
    end
  end
end

-- Optional: the Next Node is also set as the game's own map waypoint, which draws a pin (with distance) in the 3D world.
-- It replaces any waypoint of yours while on, and is cleared when the node is reached, skipped or the option is turned off.
local wayKey
local function SyncWaypoint()
  local db = ns.db
  if db and db.mk_world == true and gnextT and gnextT.key then
    if wayKey ~= gnextT.key then
      wayKey = gnextT.key
      pcall(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(gnextT.mapID, gnextT.x, gnextT.y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
      end)
    end
  elseif wayKey then
    wayKey = nil
    pcall(C_Map.ClearUserWaypoint)
  end
end

-- Adds herb, ore and chest nodes (imported data plus your recorded spots) and picks the Next Node pointer from them.
local function AddNodes(pm)
  -- Spots you recorded yourself (herb, ore and Opening casts) behave like imported nodes: grouped, skippable, and part of the pointer.
  local rec = {}
  local nodes = ns.db and ns.db.nodes
  if nodes then
    for _, kind in ipairs({ "herb", "ore", "box" }) do
      local perMap = nodes[kind] and nodes[kind][pm]
      if perMap and On(kind) then
        for i = 1, #perMap do
          local n = perMap[i]
          rec[#rec + 1] = { kind = kind, mapID = pm, x = n.x, y = n.y, label = n.name or (kind == "box" and "Chest" or kind == "herb" and "Herb" or "Ore"), sub = "Your spot", group = "gm:" .. kind,
            gather = true, key = format("%s:%d:r%d_%d", kind, pm, floor(n.x * 10000), floor(n.y * 10000)) }
        end
      end
    end
  end
  local prevT = gnextT   -- the pointer from the last rebuild, so NextNode can keep it
  gnextT = nil
  if On("herb") or On("ore") or On("box") then
    local list = {}
    for _, t in ipairs(GatherList(pm)) do list[#list + 1] = t end
    for _, t in ipairs(rec) do list[#list + 1] = t end
    for i = 1, #list do if not IsVisited(list[i].key) then targets[#targets + 1] = list[i] end end   -- reached nodes leave the bar
    NextNode(pm, list, prevT)
  end
  SyncWaypoint()
end

-- Corpse and party ----------------------------------------------------------------------------
-- Corpse: while you are a ghost, C_DeathInfo knows where the body is. It is asked on the current map and its parents,
-- because the corpse may be on a different map than the one you are on now.
local function AddCorpse(pm)
  if not (C_DeathInfo and UnitIsGhost and UnitIsGhost("player")) then return end
  local list, cur = { pm }, pm
  for _ = 1, 6 do
    local info = Try(C_Map.GetMapInfo, cur)
    if not info or not info.parentMapID or info.parentMapID == 0 then break end
    cur = info.parentMapID
    list[#list + 1] = cur
  end
  for _, m in ipairs(list) do
    local x, y = XY(Try(C_DeathInfo.GetCorpseMapPosition, m))
    if x and (x ~= 0 or y ~= 0) then
      targets[#targets + 1] = { kind = "corpse", mapID = m, x = x, y = y, label = "Your Corpse", primary = true }
      return
    end
  end
end

-- Party: one icon per member, chosen by role (tank / healer / damage) when the game reports roles, otherwise by class.
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local ROLE_NAME = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }
local CLASS_FILE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
-- Party members' positions arrive in jumps (the game refreshes them only now and then). Each member keeps the position that
-- is drawn (t.x, t.y) separate from the latest one the game gave (t.rx, t.ry) and glides from one to the other. The drawn
-- position survives a re-query in partyDrawn, so the glide does not restart every few seconds.
local partyDrawn = {}
local lastPm, lastW, lastH   -- the player's map and its size in yards, as of the last full Tick (FastTick reuses them)
-- Adds one marker per online party member (not in raids).
local function AddParty(pm)
  if not GetNumSubgroupMembers or (IsInRaid and IsInRaid()) then return end   -- raids would flood the bar
  for i = 1, GetNumSubgroupMembers() do
    local unit = "party" .. i
    -- An offline member's position is stale or meaningless, so they get no marker until they are back online.
    local x, y
    if Try(UnitIsConnected, unit) ~= false then x, y = XY(Try(C_Map.GetPlayerMapPosition, pm, unit)) end
    if x and (x ~= 0 or y ~= 0) then
      local name = Try(UnitName, unit)
      if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then name = nil end
      local role = Try(UnitGroupRolesAssigned, unit)
      if type(role) ~= "string" or (issecretvalue and issecretvalue(role)) then role = nil end
      local _, classFile = Try(UnitClass, unit)
      if type(classFile) ~= "string" or (issecretvalue and issecretvalue(classFile)) then classFile = nil end
      local t = { kind = "party", mapID = pm, x = x, y = y, rx = x, ry = y, label = name, unit = unit, always = not (ns.db and ns.db.mk_partyLimit) }
      local d = partyDrawn[unit]
      if d and d.map == pm and ns.db and ns.db.mk_partySmooth ~= false then t.x, t.y = d.x, d.y end
      local roleName = role and ROLE_NAME[role]
      if roleName then t.atlas = ROLE_ATLAS[role]
      elseif classFile then t.atlas = "classicon-" .. classFile:lower() end
      local coords = classFile and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[classFile]
      if coords then t.fbFile, t.fbCoords = CLASS_FILE, coords end
      local cname = classFile and (_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[classFile]) or nil
      t.sub = roleName and (cname and (roleName .. " - " .. cname) or roleName) or cname
      targets[#targets + 1] = t
      partyT[#partyT + 1] = t
    end
  end
end

-- Members move while you stand still, so their positions are re-read every Tick. True when any of them moved.
local function RefreshParty()
  local moved = false
  local smooth = ns.db and ns.db.mk_partySmooth ~= false
  for i = 1, #partyT do
    local t = partyT[i]
    local x, y = XY(Try(C_Map.GetPlayerMapPosition, t.mapID, t.unit))
    if x and (x ~= 0 or y ~= 0) and (x ~= t.rx or y ~= t.ry) then
      t.rx, t.ry = x, y
      moved = true
      -- a big jump (a teleport, a loading screen) is shown at once instead of gliding across the map
      if not smooth or not lastW or ((x - t.x) * lastW) ^ 2 + ((y - t.y) * (lastH or lastW)) ^ 2 > 80 * 80 then t.x, t.y = x, y end
    end
    if t.x ~= t.rx or t.y ~= t.ry then moved = true end   -- still gliding
    partyDrawn[t.unit] = partyDrawn[t.unit] or {}
    local d = partyDrawn[t.unit]; d.map, d.x, d.y = t.mapID, t.x, t.y
  end
  return moved
end
-- Move each member's drawn position toward the latest one. True if anything visibly moved.
local function SmoothParty(dt)
  if #partyT == 0 or not (ns.db and ns.db.mk_partySmooth ~= false) then return false end
  local k = 1 - math.exp(-dt / 0.45)
  local moved = false
  for i = 1, #partyT do
    local t = partyT[i]
    local dx, dy = t.rx - t.x, t.ry - t.y
    if dx ~= 0 or dy ~= 0 then
      if (dx * dx + dy * dy) < 1e-12 then t.x, t.y = t.rx, t.ry   -- close enough: land exactly
      else t.x, t.y = t.x + dx * k, t.y + dy * k; moved = true end
      local d = partyDrawn[t.unit]
      if d then d.x, d.y = t.x, t.y end
    end
  end
  return moved
end

local Rebuild
-- Re-reads every data source and rebuilds the list of targets. Tick then picks which ones to show.
function Rebuild()
  needRebuild, forceRebuild = false, false
  tickDirty = true
  wipe(targets); wipe(partyT)
  if not ns.db or not AnyOn() then return end
  local pm = Try(C_Map.GetBestMapForUnit, "player")
  if not Num(pm) then return end
  if On("tracked") then AddTracked(pm) else trackedQuest = nil end
  questieActive = UseQuestie() and true or false
  if questieActive then
    if On("objective") or On("giver") or On("tracked") then AddQuestie(MapChain(pm), FocusedQuest()) end
  elseif On("objective") or On("giver") then
    AddQuests(MapChain(pm))
  end
  if On("rare") or On("treasure") then AddVignettes(pm) end
  AddRares(pm)
  AddNodes(pm)
  if On("corpse") then AddCorpse(pm) end
  if On("party") then AddParty(pm) end
end

-- Bearing update (every TICK seconds) --------------------------------------------------------

-- A target's position on the player's map: its own when it is on that map, else moved through world
-- coordinates (cached per player map).
local function TargetXY(t, pm)
  if t.mapID == pm then return t.x, t.y end
  if t.cmap ~= pm or t.cfrom ~= t.mapID then
    t.cmap, t.cfrom, t.cx, t.cy = pm, t.mapID, nil, nil
    local cont, wp = Try(C_Map.GetWorldPosFromMapPos, t.mapID, CreateVector2D(t.x, t.y))
    if cont and wp then
      t.cx, t.cy = XY(Try(C_Map.GetMapPosFromWorldPos, cont, wp, pm))
    end
  end
  return t.cx, t.cy
end

-- Distance (yards) from the player to a point on the same map, plus the east/north offsets the bearing is made from.
-- Every target needs its distance each tick, but the bearing (atan2) is only worked out for the few that are kept.
local function Dist(tx, ty, px, py, w, h)
  local east, north = (tx - px) * w, -(ty - py) * h   -- map y grows southward
  return sqrt(east * east + north * north), east, north
end
-- Compass bearing in degrees (0 = north, clockwise) of an east/north offset.
local function Bearing(east, north) return (deg(atan2(east, north))) % 360 end

-- Orders icons: primary ones first, then nearest first.
local function SortFn(a, b)
  if a.primary ~= b.primary then return a.primary end
  return a.dist < b.dist
end

local lastCount, tickNo = 0, 0
-- Reaching or skipping a node also clears every other node within 15 yards of it, so duplicate spots (the same chest listed
-- by two sources, or twice) do not each trigger their own "reached" in a row.
local function MarkAround(ref, extra)
  if not (ref and ref.x and ref.mapID and lastW and lastH) then return end
  for i = 1, #targets do
    local g = targets[i]
    if g.gather and g.mapID == ref.mapID and g.key then
      local dx, dy = (g.x - ref.x) * lastW, (g.y - ref.y) * lastH
      if dx * dx + dy * dy < 225 then visited[g.key] = GetTime() + (extra or 0) end
    end
  end
end
-- Has the pointer's node been reached? Checked at every Tick and every FastTick (so about every frame while moving), and the
-- next pointer is picked at once, not at the next scheduled re-query.
local acc   -- (defined with the timers below; declared here so a reach can ask for an immediate re-query)
-- Counts the pointer's node as visited when it is close enough (and the highlight gate agrees); true if it moved on.
local function CheckReach(t)
  if not (t and t.dist and t.key) or IsVisited(t.key) then return false end
  if not (t.dist < VISIT_R or (t.dist < 15 and ns.SoftMatched and ns.SoftMatched())) then return false end
  if ns.ReachGate and not ns.ReachGate(t) then return false end
  if ns.NodeReached then ns.NodeReached() end
  MarkVisited(t.key); MarkAround(t); forceRebuild = true
  acc = TICK   -- re-query on the next frame
  return true
end
-- Registers a node as visited without the game's confirmation (you were within range long enough), wherever you are now.
-- It is silent on purpose: it can run a moment after you have already walked past, and "Node Reached" then would appear with
-- nothing around. The pointer moving on is the only feedback.
function ns.ForceVisit(key)
  if not key or IsVisited(key) then return end
  local g
  for i = 1, #targets do if targets[i].key == key and targets[i].gather then g = targets[i]; break end end
  MarkVisited(key)
  if g then MarkAround(g) end
  forceRebuild = true
  acc = TICK
end
-- Called by Highlight.lua when the game starts targeting a matching object.
function ns.CheckPointerReach() if gnextT then CheckReach(gnextT) end end   -- called when the game starts targeting a matching object while you stand still
-- (lastPm, lastW, lastH are declared above AddParty)   -- the player's map and its size in yards, as of the last full Tick (FastTick reuses them)
local lastPX, lastPY   -- the player's map position at the last full Tick or FastTick (FastTick skips when it is unchanged)
local best = {}   -- nearest candidate per group, rebuilt every tick
-- Herb, ore and chest nodes are not reduced to one per kind: the nearest few of each kind all show (nearer ones larger).
local GATHER_N = 8
local gl = { herb = {}, ore = {}, box = {} }
local scanPX, scanPY   -- the player's position at the last full scan of every target
-- The main update: finds the player, chooses which targets to show (nearest few per group), and redraws the bar when something changed.
local function Tick()
  local pm = Try(C_Map.GetBestMapForUnit, "player")
  local px, py = XY(pm and Try(C_Map.GetPlayerMapPosition, pm, "player"))
  if pm and not px and InCombatLockdown() then return end   -- position unreadable in combat: keep what is drawn instead of emptying the bar
  if pm ~= tickPm then forceRebuild = true end   -- a new map without a zone event: collect its targets at the next tick
  local partyMoved = #partyT > 0 and RefreshParty()
  -- Standing still with the same targets: distances and bearings cannot have changed, so keep the last result.
  -- (tickNo and the active list are left alone, so the next real Tick still sees these icons as already drawn.)
  if not tickDirty and not partyMoved and px and pm == tickPm and px == tickPX and py == tickPY then return end
  -- Moved only a little since every target was last scanned: which icons are on the bar cannot meaningfully have changed,
  -- so only those icons are re-aimed. Every target is scanned again after RESCAN yards, or when anything else changed.
  local light = false
  if not tickDirty and px and pm == tickPm and scanPX and lastPm == pm then
    local mx, my = (px - scanPX) * lastW, (py - scanPY) * lastH
    light = mx * mx + my * my < RESCAN * RESCAN
  end
  tickDirty = false
  tickPm, tickPX, tickPY = pm, px, py
  local changed = false   -- did anything visible move since the last redraw?
  local db = ns.db
  if light then
    lastPX, lastPY = px, py
    for i = 1, #active do
      local t = active[i]
      local tx, ty = TargetXY(t, pm)
      if tx then t.dist, t.east, t.north = Dist(tx, ty, px, py, lastW, lastH) end
    end
  else
    tickNo = tickNo + 1
    wipe(active)
    scanPX, scanPY = nil, nil
    if db and #targets > 0 then
      local w, h = Try(C_Map.GetMapWorldSize, pm)
      if px and Num(w) and Num(h) and w > 0 and h > 0 then
        lastPX, lastPY = px, py
        lastPm, lastW, lastH = pm, w, h
        scanPX, scanPY = px, py
        local range, qRange = db.mk_range or 500, db.mk_qRange or 600
        wipe(best)
        -- With the Next Node pointer on, its node is drawn as the large pointer instead of as a second, smaller icon.
        local nextOn = db.mk_gnext ~= false
        local nextOnly = nextOn and db.mk_gnextOnly == true   -- gathering nodes other than the pointer's are not drawn at all
        local gN = db.mk_gatherN or GATHER_N
        for _, arr in pairs(gl) do wipe(arr) end
        local fNear   -- nearest icon of the focused quest (when Questie supplies its primary marker)
        for i = 1, #targets do
          local t = targets[i]
          local tx, ty
          if t.mapID == pm then tx, ty = t.x, t.y else tx, ty = TargetXY(t, pm) end   -- the common case without a call
          if tx then
            local east, north = (tx - px) * w, -(ty - py) * h   -- map y grows southward (same math as Dist)
            local dist = sqrt(east * east + north * north)
            -- The pointer's node counts as reached inside VISIT_R, or inside the game's own interact range once the game is
            -- really targeting an object of that kind (the highlight is showing), since the data's coordinates are only so exact.
            local isPtr = gnextT and t.key == gnextT.key
            local near = dist < VISIT_R or (isPtr and dist < 15 and ns.SoftMatched and ns.SoftMatched())
            local gated = t.gather and near and isPtr and ns.ReachGate and not ns.ReachGate(gnextT)
            if t.gather and near and not gated then
              if gnextT and t.key == gnextT.key and not IsVisited(t.key) and ns.NodeReached then ns.NodeReached() end
              MarkVisited(t.key); MarkAround(t); forceRebuild = true   -- walked up to it: it leaves the bar
            end
            local limit = (t.src == "questie") and qRange or range
            if t.focus then
              -- An icon of the focused quest: it shows like any other (nearest per type, within range), and the
              -- nearest one overall, however far, becomes the primary marker below.
              t.dist, t.limit, t.east, t.north = dist, limit, east, north
              t.primary, t.kind = nil, t.baseKind
              if not fNear or dist < fNear.dist then fNear = t end
              if t.shows and dist <= limit then
                local cur = best[t.group]
                if not cur or dist < cur.dist then best[t.group] = t end
              end
            elseif (t.primary or t.always or dist <= limit) and not (t.gather and nextOn and gnextT and t.key == gnextT.key) and not (t.gather and nextOnly) then
              local g = t.group
              local arr = t.gather and gl[t.kind]
              if arr then
                -- keep the nearest gN of this kind, in order of distance
                local n = #arr
                if n < gN or dist < arr[n].dist then
                  t.dist, t.limit, t.east, t.north = dist, limit, east, north
                  if n >= gN then arr[n] = nil; n = n - 1 end
                  local pos = n + 1
                  while pos > 1 and arr[pos - 1].dist > dist do arr[pos] = arr[pos - 1]; pos = pos - 1 end
                  arr[pos] = t
                end
              -- Only a target that is kept needs its fields written; most Questie icons lose to a nearer one of their group.
              elseif g then
                local cur = best[g]
                if not cur or dist < cur.dist then
                  t.dist, t.limit, t.east, t.north = dist, limit, east, north
                  best[g] = t
                end
              else
                t.dist, t.limit, t.east, t.north = dist, limit, east, north
                active[#active + 1] = t
              end
            end
          end
        end
        if fNear then
          fNear.primary, fNear.kind = true, "tracked"
          best[fNear.group] = fNear
        end
        for _, t in pairs(best) do active[#active + 1] = t end
        for _, arr in pairs(gl) do for i = 1, #arr do active[#active + 1] = arr[i] end end
        table.sort(active, SortFn)
        for i = #active, MAX_ICONS + 1, -1 do active[i] = nil end
      end
    end
  end
  for i = 1, #active do
    local t = active[i]
    t.bearing = Bearing(t.east, t.north)
    -- Only worth a redraw if the icon is new to the bar, moved at least 0.15 degrees, or its 5-yard distance label changed.
    local d5 = floor(t.dist / 5)
    if (not light and t.seen ~= tickNo - 1) or not t.drawn or abs(t.bearing - t.drawn) > 0.15 or d5 ~= t.drawnD then
      t.drawn, t.drawnD, changed = t.bearing, d5, true
    end
    t.seen = tickNo
    -- The pointer is checked every Tick (a full scan only runs every few yards, too coarse for a 5 yard radius).
    if t.kind == "gnext" then CheckReach(t) end
    -- Quest-area glow: only the focused quest's marker, and only where the client can tell us.
    local inside
    if t.kind == "gnext" then
      inside = (t.dist <= GLOW_R) or nil   -- the pointer glows once you are close
    elseif t.primary and t.questID and db.mk_areaGlow ~= false and AreaApi() then
      inside = Try(C_Minimap.IsInsideQuestBlob, t.questID) and true or false
    end
    if inside ~= t.inArea then t.inArea = inside; changed = true end
  end
  -- Redraw only when an icon actually moved or the set of icons changed, so standing still costs nothing.
  if (changed or #active ~= lastCount) and ns.Redraw then ns.Redraw() end
  lastCount = #active
end

Rebuild = ns.Perf("Rebuild", Rebuild)
Tick = ns.Perf("Tick", Tick)

-- Drawing (called from the compass layout, only when the compass redraws) --------------------

local KIND_LABEL = {
  tracked = "Tracked Quest", objective = "Quest Objective", turnin = "Quest Turn-In", giver = "Quest Giver",
  rare = "Rare Elite", treasure = "Treasure", herb = "Herb", ore = "Ore", gnext = "Next Node",
  box = "Chest / Container", corpse = "Corpse", party = "Party Member",
}

-- Clicking a quest icon focuses that quest by setting the game's super-tracked quest. Questie follows that
-- on its own (when its "follow super tracking" option is on); CHUD never writes to Questie.
local function Focusable(t)
  return t and t.questID and not t.primary and (t.kind == "objective" or t.kind == "turnin")
end
-- Makes this quest the super-tracked one (Questie follows that on its own).
local function FocusQuest(qid)
  local ST = C_SuperTrack
  if ST and ST.SetSuperTrackedQuestID then pcall(ST.SetSuperTrackedQuestID, qid) end
  forceRebuild = true
end

-- Hover tooltip for a marker: what it is, the quest's objectives, and how far away it is.
local function ShowTip(ic)
  local t = ic.t
  if not t then return end
  GameTooltip:SetOwner(ic, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(t.label or KIND_LABEL[t.kind] or "Marker", 1, 0.82, 0)
  local kind = KIND_LABEL[t.kind] or ""
  if t.kind == "tracked" and not t.questID then kind = "Waypoint" end
  GameTooltip:AddLine(kind, 0.7, 0.7, 0.7)
  if t.sub then GameTooltip:AddLine(t.sub, 0.7, 0.7, 0.7) end
  if t.questID then
    if t.kind == "turnin" or Try(C_QuestLog.IsComplete, t.questID) then
      GameTooltip:AddLine("Ready to turn in", 0.3, 1, 0.3)
    end
    local objs = Try(C_QuestLog.GetQuestObjectives, t.questID)
    if type(objs) == "table" then
      for _, o in ipairs(objs) do
        local text = o and o.text
        if type(text) == "string" and text ~= "" and not (issecretvalue and issecretvalue(text)) then
          if o.finished then GameTooltip:AddLine("- " .. text, 0.3, 1, 0.3, true)
          else GameTooltip:AddLine("- " .. text, 1, 1, 1, true) end
        end
      end
    end
  end
  if t.dist then GameTooltip:AddLine(format("%d yd away", t.dist), 0.7, 0.7, 0.7) end
  if Focusable(t) then GameTooltip:AddLine("Click to focus this quest", 0.5, 0.8, 1) end
  if t.kind == "gnext" or t.gather then GameTooltip:AddLine("Right-click to skip this node (back in " .. ((t.nodeKind or t.kind) == "box" and 20 or 10) .. " min)", 1, 0.7, 0.3) end
  GameTooltip:Show()
end

local styleVer = 1   -- bumped whenever an icon style setting changes, so icons restyle once

-- Style settings (size, color, shadow) changed, or a theme was applied.
function ns.MarkersStyle()
  styleVer = styleVer + 1
  if ns.Redraw then ns.Redraw() end
end

local dragged = false   -- set while the bar is being dragged by an icon, so letting go is not a click
-- The pooled icon frame for slot i, created on first use.
local function GetIcon(i)
  local ic = icons[i]
  if not ic then
    ic = CreateFrame("Frame", nil, ns.contentTop)
    ic:EnableMouse(true)
    ic:RegisterForDrag("LeftButton")
    ic:SetScript("OnEnter", ShowTip)
    ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- The icon is on top of the compass, so pass clicks and drags through to it, except a plain
    -- left click on a quest icon, which focuses that quest.
    ic:SetScript("OnMouseDown", function() dragged = false end)
    ic:SetScript("OnMouseUp", function(self, button)
      if button == "LeftButton" and not dragged and Focusable(self.t) then FocusQuest(self.t.questID); return end
      if button == "RightButton" and self.t and (self.t.kind == "gnext" or self.t.gather) and ns.SkipNode then ns.SkipNode(self.t); return end
      ns.root:GetScript("OnMouseUp")(ns.root, button)
    end)
    ic:SetScript("OnDragStart", function() dragged = true; ns.root:GetScript("OnDragStart")(ns.root) end)
    ic:SetScript("OnDragStop", function() ns.root:GetScript("OnDragStop")(ns.root) end)
    -- Drawn bottom to top: quest-area glow, drop shadow, then the icon itself.
    ic.glow = ic:CreateTexture(nil, "BACKGROUND", nil, -1)
    ic.glow:SetTexture("Interface\\Cooldown\\star4"); ic.glow:SetBlendMode("ADD")
    ic.glow:SetPoint("CENTER"); ic.glow:SetAlpha(0.7); ic.glow:Hide()
    -- A slow pulse run by the game's animation system (no per-frame addon code). Without it the glow is static.
    local ok, ag = pcall(function()
      local g = ic.glow:CreateAnimationGroup(); g:SetLooping("BOUNCE")
      local a = g:CreateAnimation("Alpha")
      a:SetFromAlpha(0.25); a:SetToAlpha(0.9); a:SetDuration(0.8); a:SetSmoothing("IN_OUT")
      return g
    end)
    ic.glowAnim = ok and ag or nil
    ic.shadow = ic:CreateTexture(nil, "BACKGROUND", nil, 0)
    ic.tex = ic:CreateTexture(nil, "ARTWORK"); ic.tex:SetAllPoints()
    ic.dist = ic:CreateFontString(nil, "OVERLAY")
    ic.dist:SetFont(STANDARD_TEXT_FONT, 9, "")
    ic.dist:SetPoint("TOP", ic, "BOTTOM", 0, 1)
    icons[i] = ic
  end
  return ic
end

-- Sets an icon's texture and tint for its target.
local function SetIcon(tex, t)
  if t.file then tex:SetTexture(t.file); tex:SetTexCoord(0, 1, 0, 1); return end   -- Questie's own icon art
  local spec = ICON[t.kind] or {}
  local list = t.atlas and { t.atlas } or spec.atlases
  if list and C_Texture and C_Texture.GetAtlasInfo then
    for _, a in ipairs(list) do
      if C_Texture.GetAtlasInfo(a) then tex:SetAtlas(a, false); tex:SetTexCoord(0, 1, 0, 1); return end
    end
  end
  if t.fbFile and t.fbCoords then tex:SetTexture(t.fbFile); tex:SetTexCoord(unpack(t.fbCoords)); return end   -- party member: class icon sheet
  tex:SetTexture(spec.file or "Interface\\Icons\\INV_Misc_QuestionMark")
  if spec.crop then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else tex:SetTexCoord(0, 1, 0, 1) end
end

-- Paints one texture as a flat-colored silhouette of the icon (desaturate, then tint).
local function Tinted(tex, t, r, g, b, a)
  SetIcon(tex, t)
  tex:SetDesaturated(true)
  tex:SetVertexColor(r, g, b, 1)
  tex:SetAlpha(a)
end

-- Applies color and shadow to one icon (its size is set per draw in LayoutMarkers). Runs when settings or the icon's target change.
local function Restyle(ic, t)
  local db = ns.db
  local c, native = db.mk_color, db.mk_native
  SetIcon(ic.tex, t)
  if native then
    ic.tex:SetDesaturated(false); ic.tex:SetVertexColor(1, 1, 1, 1); ic.tex:SetAlpha(1)   -- the game's own colors
  else
    ic.tex:SetDesaturated(true); ic.tex:SetVertexColor(c[1], c[2], c[3], 1); ic.tex:SetAlpha(c[4])
  end
  local base = native and 1 or c[4]
  if native then ic.glow:SetVertexColor(1, 0.82, 0, 1) else ic.glow:SetVertexColor(c[1], c[2], c[3], 1) end

  local sa = db.mk_shadowAlpha or 0
  if sa > 0 then
    local off = db.mk_shadowDist or 1.5
    Tinted(ic.shadow, t, 0, 0, 0, sa * base)
    ic.shadow:ClearAllPoints()   -- anchored to both corners, so it follows the icon's size
    ic.shadow:SetPoint("TOPLEFT", ic, "TOPLEFT", off, -off)
    ic.shadow:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", off, -off)
    ic.shadow:Show()
  else
    ic.shadow:Hide()
  end

  local tc = db.textColor
  -- The distance text only gets the game's black outline on themes that outline their text.
  -- Light themes (dark text, no outline) would otherwise be unreadable.
  local flag = ((db.outlineWidth or 0) > 0) and "OUTLINE" or ""
  local path = (db.fontPath and db.fontPath ~= "") and db.fontPath or STANDARD_TEXT_FONT
  if not ic.dist:SetFont(path, 9, flag) then ic.dist:SetFont(STANDARD_TEXT_FONT, 9, flag) end
  ic.dist:SetTextColor(tc[1], tc[2], tc[3], 1)
  ic.dist:SetAlpha(tc[4])
end

-- Which way "outside the bar" is: below it when the bar is in the upper half of the screen (the usual
-- place), above it when it is in the lower half, so the icons are never pushed off the screen.
local function OutsideDir()
  local _, cy = ns.root:GetCenter()
  if type(cy) == "number" and UIParent and cy < UIParent:GetHeight() / 2 then return 1 end
  return -1
end

-- Off-bar hint --------------------------------------------------------------------------------------------------
-- A floating text beside the bar, not attached to it and clear of the icons. It only flashes "Node Reached" (or "Skipped")
-- when you arrive. An off-bar Next Node is shown by its icon pinned to the bar's edge, not by text.
local hint
local TOAST = 1.6
-- The floating text frame, created on first use.
local function HintFrame()
  if hint then return hint end
  hint = CreateFrame("Frame", nil, UIParent)
  hint:SetFrameStrata("HIGH"); hint:SetSize(2, 2); hint:Hide()
  hint:SetAlpha(ns.barAlpha or 1)   -- it is a separate frame from the bar, so it follows the bar's fading itself (Fade.lua)
  hint.fs = hint:CreateFontString(nil, "OVERLAY")
  hint.fs:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
  return hint
end
-- Fade.lua calls this with the bar's current opacity so the toast fades with it.
function ns.SetHintAlpha(a) if hint then hint:SetAlpha(a) end end
local function HintPlace(side)
  local h = HintFrame()
  if h.side == side then return end
  h.side = side
  h.fs:ClearAllPoints()
  if side == "L" then h.fs:SetPoint("RIGHT", ns.root, "LEFT", -12, 0); h.fs:SetJustifyH("RIGHT")
  else h.fs:SetPoint("LEFT", ns.root, "RIGHT", 12, 0); h.fs:SetJustifyH("LEFT") end
end
local function HintStyle()
  local db = ns.db
  local h = HintFrame()
  local path = (db.fontPath and db.fontPath ~= "") and db.fontPath or STANDARD_TEXT_FONT
  local size = (db.fontSize or 14) + 1
  if h.fontKey ~= path .. size then
    h.fontKey = path .. size
    if h.fs:SetFont(path, size, "OUTLINE") == false then h.fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE") end
  end
end
-- Shows or hides the toast. The arguments are unused now that no arrow is drawn; the call stays so Redraw has one place to say
-- "the toast may need updating".
function ns.UpdateNodeHint()
  local db = ns.db
  local h = HintFrame()
  local toast = h.toastUntil and GetTime() < h.toastUntil
  if not db or db.mk_gnext == false or not toast then
    if h:IsShown() and not toast then h:Hide() end
    return
  end
  HintStyle()
  HintPlace(h.side or "R")
  local tc = h.toastColor or { 0.4, 1, 0.4 }
  h.fs:SetText(h.toastText or "Node Reached"); h.fs:SetTextColor(tc[1], tc[2], tc[3], 1)
  h:SetAlpha(1)
  h:Show()
end
-- Called when you walk up to the node the pointer was on.
local function NodeReached(text, color)
  local h = HintFrame()
  h.toastText, h.toastColor = text, color
  h.toastUntil = GetTime() + TOAST
  h:Show()
  h:SetScript("OnUpdate", function(self)
    local left = self.toastUntil - GetTime()
    if left <= 0 then
      self:SetScript("OnUpdate", nil); self.toastUntil = nil
      if ns.Redraw then ns.Redraw() end   -- back to the arrow, or gone if the next node is on the bar
      return
    end
    self:SetAlpha(min(1, left / 0.5))
  end)
  ns.UpdateNodeHint()
end
ns.NodeReached = NodeReached

-- Right-click on a node icon: skip it (some nodes need a climb). It comes back after the same delay as a reached node,
-- and the pointer moves on at once.
local SKIP_EXTRA = 0
function ns.SkipNode(t, text, color)
  if not t then return end
  local key = t.key
  if t.kind == "gnext" then key = gnextT and gnextT.key end
  if not key then return end
  visited[key] = GetTime() + SKIP_EXTRA
  MarkAround(t.kind == "gnext" and gnextT or t, SKIP_EXTRA)
  forceRebuild = true
  if text == false then
    if ns.Redraw then ns.Redraw() end
  else
    NodeReached(text or "Node Skipped", color or { 1, 0.7, 0.3 })
  end
end

-- The Next Node pointer's target (read by Highlight.lua), and "the node is not there": it is skipped like a reached node, so it comes back after the respawn wait.
function ns.PointerInfo() return gnextT end
function ns.NodeMissing()
  if not gnextT then return end
  local name = gnextT.nodeName
  ns.SkipNode(gnextT, false)   -- the big effect in Highlight.lua replaces the small toast
  if ns.NotHereFX then ns.NotHereFX(name) end
end

local lastLayoutAt = -1   -- GetTime() of the last LayoutMarkers, so FastTick does not repeat a layout done this frame
local lastB, lastPpd, lastHalf, lastFade, lastZone   -- the compass's latest layout, so icons can be re-placed alone
-- Screen marker --------------------------------------------------------------------------------
-- The Next Node is set as the game's map waypoint (SyncWaypoint). The game keeps a navigation frame (C_Navigation.GetFrame)
-- at that waypoint's real position on screen, terrain height and camera included, so the beam and ring are drawn on it.
-- If the client has no such frame, a rough estimate from compass direction is used instead (horizontal only; height is a
-- guess). Drawn behind all other UI.
local WM_MEDIA = "Interface\\AddOns\\CHUD\\media\\"
local WM_SLICES = 12
local wm
local WorldColor
local function NavPos()
  local nf = C_Navigation and C_Navigation.GetFrame and Try(C_Navigation.GetFrame)
  if not (type(nf) == "table" and nf.IsShown and nf:IsShown()) then return nil end
  local x, y = nf:GetCenter()
  if not (Num(x) and Num(y)) then return nil end
  local sc = nf:GetEffectiveScale() / UIParent:GetEffectiveScale()
  return x * sc, y * sc
end
local function WorldPlace(f)
  local t = f.t
  if not t then return end
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local xp, base, edge
  local nx, ny = NavPos()
  if nx then
    xp, base = nx, ny
    local m = 18
    edge = xp < m or xp > W - m or base < 0 or base > H
    if xp < m then xp = 14 elseif xp > W - m then xp = W - 14 end
    if base < 0 then base = 0 elseif base > H * 0.85 then base = H * 0.85 end
  else
    xp, base, edge = f.axp, f.abase, f.aedge
  end
  if not xp then return end
  local dist, scale = f.dist, H / 1080
  local bw = edge and 12 or max(8, min(46, (2600 / max(dist, 12)) * scale))
  f.beam:SetSize(bw, f.bh)
  f.beam:ClearAllPoints(); f.beam:SetPoint("BOTTOM", f, "BOTTOMLEFT", xp, base)
  if edge then
    f.ringOn = false
    f.ring:Hide(); f.pin:Hide(); f.fs:Hide()
    if f.cA ~= f.edgeA then WorldColor(f, f.tr, f.tg, f.tb, f.edgeA) end
  else
    if f.cA ~= f.A then WorldColor(f, f.tr, f.tg, f.tb, f.A) end
    local rw = max(24, min(170, (6200 / max(dist, 12)) * scale))
    f.ring:SetSize(rw, rw * 0.42)
    f.ring:ClearAllPoints(); f.ring:SetPoint("CENTER", f, "BOTTOMLEFT", xp, base)
    f.ringA, f.ringOn = 0.55 + 0.4 * f.prox, true
    f.ring:Show()
    f.pin:ClearAllPoints(); f.pin:SetPoint("BOTTOM", f, "BOTTOMLEFT", xp, base + rw * 0.21)
    f.pin:Show()
    f.fs:ClearAllPoints(); f.fs:SetPoint("TOP", f, "BOTTOMLEFT", xp, base - rw * 0.21 - 2)
    f.fs:Show()
  end
end
WorldColor = function(f, r, g, b, A)
  A = floor(A * 20 + 0.5) / 20
  if f.cr == r and f.cg == g and f.cb == b and f.cA == A then return end
  f.cr, f.cg, f.cb, f.cA = r, g, b, A
  for i = 1, WM_SLICES do
    local a = A * (1 - (i - 1) / WM_SLICES) ^ 1.6
    local sl = f.slices[i]
    sl.L:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, a))
    sl.R:SetGradient("HORIZONTAL", CreateColor(r, g, b, a), CreateColor(r, g, b, 0))
  end
  f.ring:SetVertexColor(r, g, b)
  f.fs:SetTextColor(r, g, b, 1)
end
local function WorldMarker()
  if wm then return wm end
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetFrameStrata("BACKGROUND"); f:SetAllPoints(UIParent); f:Hide()
  local beam = CreateFrame("Frame", nil, f)
  beam:SetSize(20, 100)
  f.beam, f.slices = beam, {}
  for i = 1, WM_SLICES do
    local L, R = beam:CreateTexture(nil, "ARTWORK"), beam:CreateTexture(nil, "ARTWORK")
    L:SetTexture("Interface\\Buttons\\WHITE8X8"); R:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.slices[i] = { L = L, R = R }
  end
  f.ring = f:CreateTexture(nil, "ARTWORK"); f.ring:SetTexture(WM_MEDIA .. "ring.tga")
  f.pin = f:CreateTexture(nil, "OVERLAY"); f.pin:SetSize(22, 22)
  local ok = pcall(f.pin.SetAtlas, f.pin, "Waypoint-MapPin-Untracked")
  if not ok or not f.pin:GetAtlas() then f.pin:SetTexture("Interface\\Icons\\INV_Misc_Map_01") end
  f.fs = f:CreateFontString(nil, "OVERLAY"); f.fs:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
  f:SetScript("OnUpdate", function(self)
    if not (ns.root and ns.root:IsVisible()) then self:Hide(); return end
    WorldPlace(self)   -- every frame: turning the camera moves the marker even when the compass does not change
    if self.ringOn then self.ring:SetAlpha(self.ringA * (0.65 + 0.35 * math.sin(GetTime() * 3.2))) end
  end)
  wm = f
  return f
end
-- t = the Next Node target (or nil), b = the compass heading in degrees.
function ns.UpdateWorldMarker(t, b)
  local db = ns.db
  if not (t and t.bearing and t.dist and db and db.mk_world == true and db.mk_gnext ~= false) then
    if wm and wm:IsShown() then wm:Hide(); wm.t = nil end
    return
  end
  local f = WorldMarker()
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  if not (W and H and H > 0) then return end
  local c = db.cardinalColor or { 1, 0.82, 0, 1 }
  local dist = t.dist
  f.t, f.dist = t, dist
  f.prox = max(0, min(1, (200 - dist) / 200))
  f.A = 0.35 + 0.30 * f.prox
  f.edgeA = f.A * 0.6
  f.tr, f.tg, f.tb = c[1], c[2], c[3]
  f.bh = H * 0.30
  if f.sliceH ~= f.bh then
    f.sliceH = f.bh
    local sh = f.bh / WM_SLICES
    for i = 1, WM_SLICES do
      local y, sl, beam = (i - 1) * sh, f.slices[i], f.beam
      sl.L:ClearAllPoints(); sl.R:ClearAllPoints()
      sl.L:SetPoint("BOTTOMLEFT", beam, "BOTTOMLEFT", 0, y); sl.L:SetPoint("TOPRIGHT", beam, "BOTTOM", 0, y + sh)
      sl.R:SetPoint("BOTTOMLEFT", beam, "BOTTOM", 0, y); sl.R:SetPoint("TOPRIGHT", beam, "BOTTOMRIGHT", 0, y + sh)
    end
  end
  f.fs:SetText(format("%s  %d yd", t.nodeName or "Node", floor(dist / 5 + 0.5) * 5))
  -- Fallback estimate, used only when the client has no navigation frame: a pinhole camera 90 degrees wide at 4:3.
  local rel = ((t.bearing - b + 540) % 360) - 180
  local edge = abs(rel) >= 85
  local xp
  if not edge then
    xp = W / 2 + (math.tan(math.rad(rel)) / (0.75 * (W / H))) * (W / 2)
    if xp < 24 or xp > W - 24 then edge = true end
  end
  if edge then xp = (rel > 0) and (W - 14) or 14 end
  f.axp, f.abase, f.aedge = xp, H * (0.25 + 0.15 * max(0, min(1, (dist - 10) / 110))), edge
  if not f:IsShown() then f:Show() end
  WorldPlace(f)
end

-- Demo markers for the setup tour: twelve fake icons, one every 30 degrees all the way around, so some are on the bar whichever
-- way you face. Used in place of the real ones only while the tour is open (ns.SetDemoMarkers), and never saved or acted on.
local DEMO_KINDS = { "gnext", "herb", "ore", "box", "giver", "herb", "rare", "ore", "tracked", "box", "objective", "herb" }
local DEMO_DIST = { 70, 40, 95, 120, 150, 25, 200, 60, 300, 80, 180, 110 }
local demo, demoNextOnly, demoOn = {}, {}, false
for i, kind in ipairs(DEMO_KINDS) do
  demo[i] = { kind = kind, bearing = (i - 1) * 30, dist = DEMO_DIST[i], gather = (kind == "herb" or kind == "ore" or kind == "box") or nil,
    primary = (kind == "gnext") or nil }
end
for _, t in ipairs(demo) do if not t.gather then demoNextOnly[#demoNextOnly + 1] = t end end   -- the same set without herbs, ore and chests
-- Turns the demo markers on or off and redraws.
function ns.SetDemoMarkers(on)
  on = on and true or false
  if demoOn == on then return end
  demoOn = on
  for _, ic in ipairs(icons) do ic.t = nil end   -- every icon is restyled for whatever it shows next
  if ns.Redraw then ns.Redraw() end
end

function ns.LayoutMarkers(b, ppd, half, fade, fadeZone)
  lastB, lastPpd, lastHalf, lastFade, lastZone = b, ppd, half, fade, fadeZone
  -- The setup tour shows the demo set instead of the real icons, without the other herbs, ore and chests when Only Show Next Node is on.
  local ndb = ns.db
  local active = demoOn and ((ndb.mk_gnext ~= false and ndb.mk_gnextOnly == true) and demoNextOnly or demo) or active
  lastLayoutAt = GetTime()
  local db = ns.db
  local base = db.mk_size or 16
  local maxSize = max(base, db.height - 2)   -- the focused icon never makes the bar taller
  local depth = db.mk_depth ~= false
  local outside = db.mk_outside
  local dir = outside and OutsideDir() or 0   -- +1 above the bar, -1 below it
  local shown = 0
  local hintT
  for i = 1, #active do
    local t = active[i]
    local x = (((t.bearing - b + 540) % 360) - 180) * ppd
    if t.kind == "gnext" then hintT = t end
    -- An icon past the end of the bar is never drawn (only the primary one is pinned to the edge), so skip all its work.
    if t.primary or abs(x) <= half then
    local ic = GetIcon(shown + 1)
    local size, dim = base, 1
    if t.primary and t.kind ~= "corpse" and t.kind ~= "gnext" then   -- the corpse is pinned like a primary but sized like a normal icon, and shrinks with distance
      size = min(base * FOCUS_SCALE, maxSize)
    elseif t.kind == "gnext" then
      size = min(52, base * (db.mk_gnextScale or 1.6))   -- the Next Node is meant to be seen first, so it is larger than other icons
    elseif FADE_RANGE[t.kind] then
      -- Quest givers and objectives shrink and fade the farther away they are; each has its own distance.
      local spec = FADE_RANGE[t.kind]
      local f = min(t.dist / max(db[spec[1]] or spec[2], 1), 1)
      size, dim = base * (1 - FADE_SHRINK * f), 1 - FADE_ALPHA * f
    elseif t.gather then
      -- Nodes are small and faint far away and grow as you close in, over the last 150 yards.
      local f = min(t.dist / 150, 1)
      size, dim = base * (1.15 - 0.55 * f), 1 - 0.3 * f
    elseif depth and t.limit and t.limit > 0 then
      -- Farther icons are smaller, down to FAR_SCALE of normal at the edge of their range.
      size = max(6, base * (1 - (1 - FAR_SCALE) * min(t.dist / t.limit, 1)))
    end
    size = floor(size * 2 + 0.5) / 2   -- half-pixel steps, so the size is not re-set for tiny changes
    if ic.sz ~= size then ic.sz = size; ic:SetSize(size, size) end
    local y
    if outside then
      y = (db.height / 2 + size / 2 + 1) * dir   -- just beyond the bar's edge
    else
      -- Icons sit along the edge opposite the ticks, inside the bar.
      y = db.height / 2 - size / 2 - 1
      if db.flipTicks then y = -y end
    end
    local isParty = t.kind == "party"
    -- A party member shows its name, and only when the icons are outside the bar (inside there is no room for it).
    local showDist = isParty and (outside and t.label ~= nil) or (t.primary and db.mk_distance)
    local reach = size
    if showDist then
      -- Measure the text first: when pinned to the edge, the text must stay inside the bar too.
      if isParty then
        if ic.dt ~= t or ic.d5 ~= -1 then ic.dt = t; ic.d5 = -1; ic.dist:SetText(t.label) end
      else
        local d5 = floor(t.dist / 5 + 0.5) * 5
        if ic.dt ~= t or ic.d5 ~= d5 then ic.dt = t; ic.d5 = d5; ic.dist:SetText(d5 .. " yd") end
      end
      reach = max(size, ic.dist:GetStringWidth())
    end
    local lim = half - reach / 2 - 2
    local show = true
    if abs(x) > lim then
      if t.primary then x = (x > 0) and lim or -lim      -- pinned to the edge: turn this way
      else show = false end
    end
    if show then
      -- One fade rule for every position, including when pinned, so an icon is exactly as faded at
      -- the edge as it will be the moment it slides back in.
      local alpha = 1
      if fade then alpha = max(0, min(1, (half - abs(x)) / fadeZone)) end
      -- The Next Node is the one thing you are heading for, so pinned at the edge it stays fairly solid instead of vanishing.
      if t.kind == "gnext" then alpha = max(alpha, 0.65) end
      shown = shown + 1
      if ic.ver ~= styleVer or ic.t ~= t then ic.ver = styleVer; ic.t = t; Restyle(ic, t) end
      -- Distance text goes on the inner side of the icon (toward the bar's middle) inside the bar, and on the
      -- outer side when the icons are outside it.
      local flip                      -- true = distance text above the icon, false = below it
      if outside then flip = (dir == 1) else flip = db.flipTicks and true or false end
      if ic.flip ~= flip then
        ic.flip = flip
        ic.dist:ClearAllPoints()
        if flip then ic.dist:SetPoint("BOTTOM", ic, "TOP", 0, -1) else ic.dist:SetPoint("TOP", ic, "BOTTOM", 0, 1) end
      end
      -- Each of these is a call into the game, so they only happen when the value actually changed.
      if t.inArea then
        local gs = min(size * 2, db.height)   -- never spills outside the bar
        if ic.glowSz ~= gs then ic.glowSz = gs; ic.glow:SetSize(gs, gs) end
        if ic.glowOn ~= true then ic.glowOn = true; ic.glow:Show() end
        if ic.glowAnim and not ic.glowAnim:IsPlaying() then ic.glowAnim:Play() end
      elseif ic.glowOn ~= false then
        ic.glowOn = false
        ic.glow:Hide()
        if ic.glowAnim then ic.glowAnim:Stop() end
      end
      ic:SetPoint("CENTER", ns.strip, "CENTER", x, y)   -- setting an anchor point that already exists replaces it, so no ClearAllPoints
      local a = floor(alpha * dim * 100 + 0.5) / 100
      if ic.al ~= a then ic.al = a; ic:SetAlpha(a) end
      if not ic.on then ic.on = true; ic:Show() end
      local sd = showDist and true or false
      if ic.sd ~= sd then ic.sd = sd; ic.dist:SetShown(sd) end
    end
    end   -- of: on the bar, or primary
  end
  ns.UpdateNodeHint()
  ns.UpdateWorldMarker(not demoOn and hintT or nil, b)   -- no screen marker for a fake node
  for i = shown + 1, #icons do   -- hiding the icon hides its glow too
    local ic = icons[i]
    if ic.on then ic.on = false; ic:Hide() end
    ic.t = nil
  end
end

ns.LayoutMarkers = ns.Perf("LayoutMarkers", ns.LayoutMarkers)

-- Smooth movement for close-up icons ---------------------------------------------------------------
-- The full Tick (every TICK seconds) re-scans every target. A nearby icon swings quickly as you move, so
-- at that rate it jumps. While you move and any shown icon is within NEAR yards, only the icons on the bar
-- are re-aimed, at the rate the player chose (mk_rate), and only the icons are re-placed, not the whole
-- compass. Standing still costs nothing: the player's position is unchanged, so it returns at once.
local NEAR = 150
-- Between full ticks: updates distance and bearing of nearby icons every frame while you move or a party icon glides.
local function FastTick(gliding)
  if not lastB or #active == 0 or not lastPm then return end
  local near = false
  for i = 1, #active do
    if active[i].dist < NEAR then near = true; break end
  end
  if not near then return end
  local px, py = XY(Try(C_Map.GetPlayerMapPosition, lastPm, "player"))
  if not px or (px == lastPX and py == lastPY and not gliding) then return end
  lastPX, lastPY = px, py
  for i = 1, #active do
    local t = active[i]
    local tx, ty = TargetXY(t, lastPm)
    if tx then
      local dist, east, north = Dist(tx, ty, px, py, lastW, lastH)
      t.dist, t.bearing = dist, Bearing(east, north)
      t.drawn, t.drawnD = t.bearing, floor(dist / 5)   -- keep Tick's change detection in step
    end
  end
  for i = 1, #active do
    if active[i].kind == "gnext" and CheckReach(active[i]) then return end
  end
  if lastLayoutAt == GetTime() then return end   -- the compass already redrew the icons this frame, with these positions
  ns.LayoutMarkers(lastB, lastPpd, lastHalf, lastFade, lastZone)
end
FastTick = ns.Perf("FastTick", FastTick)

-- Gather recording ------------------------------------------------------------------------------
-- The cast that starts a gather is matched by spell NAME (works across expansions and locales
-- because the base spells' names are looked up from the game). When the cast succeeds, the
-- player's position is saved as a spot.

local gatherKind = {}
-- A spell's name by id, whichever spell API this client has.
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return Try(C_Spell.GetSpellName, id) end
  return Try(GetSpellInfo, id)
end
-- Maps gathering cast names (Herb Gathering, Mining, Opening) to the node kind they record.
local function BuildGatherNames()
  wipe(gatherKind)
  gatherKind[SpellName(2366) or "Herb Gathering"] = "herb"
  gatherKind[SpellName(2575) or "Mining"] = "ore"
  gatherKind[SpellName(3365) or "Opening"] = "box"
end

local pending
-- Saves your position as a node of the right kind after a successful gathering cast.
local function Record(p)
  local db = ns.db
  if not db then return end
  local pm = Try(C_Map.GetBestMapForUnit, "player")
  local x, y = XY(pm and Try(C_Map.GetPlayerMapPosition, pm, "player"))
  local w, h = Try(C_Map.GetMapWorldSize, pm)
  if not (x and Num(w) and Num(h) and w > 0) then return end
  -- A node of another addon within reach of this gather counts as reached, so the Next Node pointer moves on.
  for i = 1, #gmCache.list do
    local t = gmCache.list[i]
    if t.kind == p.kind and t.mapID == pm then
      local dx, dy = (t.x - x) * w, (t.y - y) * h
      if dx * dx + dy * dy <= 20 * 20 then MarkVisited(t.key); needRebuild = true end
    end
  end
  db.nodes = db.nodes or {}
  local byKind = db.nodes[p.kind]; if not byKind then byKind = {}; db.nodes[p.kind] = byKind end
  local list = byKind[pm]; if not list then list = {}; byKind[pm] = list end
  for i = 1, #list do
    local n = list[i]
    local dx, dy = (n.x - x) * w, (n.y - y) * h
    if dx * dx + dy * dy <= DEDUPE * DEDUPE then n.name = p.name or n.name; return end
  end
  if #list >= MAX_NODES then table.remove(list, 1) end   -- drop the oldest
  list[#list + 1] = { x = floor(x * 1e5 + 0.5) / 1e5, y = floor(y * 1e5 + 0.5) / 1e5, name = p.name }
  needRebuild = true
end

-- Events and timing ---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
  "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "SUPER_TRACKING_CHANGED", "USER_WAYPOINT_UPDATED",
  "VIGNETTES_UPDATED", "VIGNETTE_MINIMAP_UPDATED", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
  "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE" }) do
  pcall(ev.RegisterEvent, ev, e)   -- an event this client does not have is simply skipped
end
pcall(ev.RegisterEvent, ev, "LOOT_OPENED")   -- rare kills: the corpse you loot (the combat log is closed to addons on this client)
pcall(ev.RegisterUnitEvent, ev, "UNIT_HEALTH", "target")   -- rare kills: your target dying
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SENT", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_INTERRUPTED", "player")
pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_FAILED", "player")

ev:SetScript("OnEvent", function(_, event, ...)
  if event == "UNIT_HEALTH" then
    pcall(function()   -- the game may hide these values from addons; a refusal here is simply skipped
      if UnitIsDead and UnitIsDead("target") then
        local g = UnitGUID("target")
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) then
          local id = tonumber((select(6, strsplit("-", g))))
          if id then ns.NoteRareKill(id) end
        end
      end
    end)
    return
  end
  if event == "LOOT_OPENED" then
    for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
      local g = GetLootSourceInfo and GetLootSourceInfo(slot)
      if type(g) == "string" and not (issecretvalue and issecretvalue(g)) then
        local id = tonumber((select(6, strsplit("-", g))))
        if id then ns.NoteRareKill(id) end
      end
    end
    return
  end
  if event == "UNIT_SPELLCAST_SENT" then
    local _, target, _, spellID = ...
    local name = Num(spellID) and SpellName(spellID) or nil
    local tname = (type(target) == "string" and not (issecretvalue and issecretvalue(target))) and target or nil
    ns.lastCast = { id = spellID, name = name, target = tname }
    local kind = name and gatherKind[name]
    pending = kind and { kind = kind, spell = spellID, name = tname } or nil
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local _, _, spellID = ...
    if pending and pending.spell == spellID then Record(pending); pending = nil end
  elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
    pending = nil
  elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_POI_UPDATE" or event == "VIGNETTES_UPDATED"
    or event == "VIGNETTE_MINIMAP_UPDATED" then
    needRebuild = true    -- these fire in bursts (looting, combat): at most one re-query per MIN_REBUILD seconds
  else
    forceRebuild = true   -- zone, focus and waypoint changes show at the next tick
  end
end)

local accRefresh, accFast = 0, 0
acc = 0
ev:SetScript("OnUpdate", ns.Perf("Markers", function(_, elapsed)
  if not ns.db then return end
  if not next(gatherKind) then BuildGatherNames() end
  acc = acc + elapsed; accRefresh = accRefresh + elapsed; accFast = accFast + elapsed
  local gliding = SmoothParty(elapsed)
  if acc < TICK then
    -- Between full ticks: keep close-up icons smooth, at the chosen rate.
    if accFast >= 1 / max(ns.db.mk_rate or 24, 1) then accFast = 0; FastTick(gliding) end
    return
  end
  acc, accFast = 0, 0
  if forceRebuild or (needRebuild and accRefresh >= MIN_REBUILD) or accRefresh >= REFRESH then accRefresh = 0; Rebuild() end
  Tick()
end))

-- Called by the menu whenever an option changes.
function ns.MarkersChanged()
  forceRebuild = true
  acc = TICK   -- run at the next frame
end

function ns.MarkerDebug()
  local db = ns.db
  local pm = Try(C_Map.GetBestMapForUnit, "player")
  local x, y = XY(pm and Try(C_Map.GetPlayerMapPosition, pm, "player"))
  print("CHUD markers: map", tostring(pm), "| position", x and format("%.3f, %.3f", x, y) or "unavailable",
    "| targets", #targets, "| on compass", #active)
  local counts = {}
  for _, t in ipairs(targets) do counts[t.kind] = (counts[t.kind] or 0) + 1 end
  for k, n in pairs(counts) do print("  ", k, n) end
  local rec = {}
  for _, kind in ipairs({ "herb", "ore", "box" }) do
    local n = 0
    for _, list in pairs((db.nodes and db.nodes[kind]) or {}) do n = n + #list end
    rec[#rec + 1] = kind .. "=" .. n
  end
  print("  recorded spots:", table.concat(rec, "  "))
  local lc = ns.lastCast
  print("  last cast:", lc and (tostring(lc.id) .. " " .. tostring(lc.name) .. " -> " .. tostring(lc.target)) or "none yet")
  local fnames = { "C_QuestLog.GetQuestsOnMap", "C_QuestLog.GetNextWaypoint", "C_SuperTrack.GetSuperTrackedQuestID",
    "C_VignetteInfo.GetVignettes", "C_Map.GetPlayerMapPosition", "C_Map.GetMapWorldSize", "C_Map.GetWorldPosFromMapPos",
    "C_Map.GetMapPosFromWorldPos", "C_Map.GetUserWaypoint" }
  local missing = {}
  for _, n in ipairs(fnames) do
    local t, key = n:match("^(.-)%.(.+)$")
    if not (_G[t] and _G[t][key]) then missing[#missing + 1] = n end
  end
  print("  missing APIs:", #missing == 0 and "none" or table.concat(missing, ", "))
  local qstate = "not installed"
  if _G.Questie then
    if not QuestieReady() then qstate = "installed, not ready yet"
    elseif db.mk_questie == false then qstate = "installed, turned off in the menu"
    else qstate = "in use" end
  end
  print("  questie:", qstate)
  if _G.Questie and Q.map and type(Q.map.questIdFrames) == "table" then
    local n = { total = 0, hidden = 0, mini = 0, other = 0 }
    local byKind = {}
    for _, names in pairs(Q.map.questIdFrames) do
      if type(names) == "table" then
        for _, name in pairs(names) do
          local fr = _G[name]
          local d = type(fr) == "table" and fr.data
          if d then
            n.total = n.total + 1
            if fr.hidden then n.hidden = n.hidden + 1 end
            if fr.miniMapIcon then n.mini = n.mini + 1 end
            local k = Q.kinds and Q.kinds[d.Icon]
            if k and not fr.hidden then byKind[k] = (byKind[k] or 0) + 1 else n.other = n.other + 1 end
          end
        end
      end
    end
    print("  questie icons:", "total", n.total, "| hidden by Questie", n.hidden, "| minimap copies", n.mini,
      "| usable: objective", byKind.objective or 0, "giver", byKind.giver or 0, "turnin", byKind.turnin or 0, "| skipped", n.other)
  end
  -- Quest givers: where do they drop out? (read only; counts every step for the player's current map)
  if _G.Questie and Q.map and Q.kinds and type(Q.map.questIdFrames) == "table" then
    local chain = {}
    for _, m in ipairs(pm and MapChain(pm) or {}) do chain[m] = true end
    local w, h = Try(C_Map.GetMapWorldSize, pm)
    local g = { all = 0, shown = 0, hiddenWorld = 0, hiddenMini = 0, onMap = 0, near = 0 }
    local byMap, nearest, nearestQuest = {}, nil, nil
    for qid, names in pairs(Q.map.questIdFrames) do
      if type(names) == "table" then
        for _, name in pairs(names) do
          local fr = _G[name]
          local d = type(fr) == "table" and fr.data
          if d and Q.kinds[d.Icon] == "giver" then
            g.all = g.all + 1
            if fr.hidden then
              if fr.miniMapIcon then g.hiddenMini = g.hiddenMini + 1 else g.hiddenWorld = g.hiddenWorld + 1 end
            else
              g.shown = g.shown + 1
              byMap[fr.UiMapID or 0] = (byMap[fr.UiMapID or 0] or 0) + 1
              if chain[fr.UiMapID] and Num(fr.x) and Num(fr.y) then
                g.onMap = g.onMap + 1
                if x and Num(w) and Num(h) and fr.UiMapID == pm then
                  local dx, dy = (fr.x / 100 - x) * w, (fr.y / 100 - y) * h
                  local dist = sqrt(dx * dx + dy * dy)
                  if not nearest or dist < nearest then nearest, nearestQuest = dist, qid end
                  if dist <= (db.mk_qRange or 600) then g.near = g.near + 1 end
                end
              end
            end
          end
        end
      end
    end
    print("  questie givers:", "total", g.all, "| hidden (world map copy)", g.hiddenWorld, "(minimap copy)", g.hiddenMini,
      "| shown", g.shown, "| on this map", g.onMap, "| within", db.mk_qRange or 600, "yd", g.near,
      "| nearest", nearest and format("%d yd (quest %s)", floor(nearest), tostring(nearestQuest)) or "none on this map")
    local list = {}
    for m, n in pairs(byMap) do list[#list + 1] = { m = m, n = n } end
    table.sort(list, function(a, b) return a.n > b.n end)
    local parts = {}
    for i = 1, math.min(#list, 8) do parts[i] = list[i].m .. "=" .. list[i].n end
    print("  shown giver icons by map id:", #parts > 0 and table.concat(parts, " ") or "none",
      "| this map and parents:", pm and table.concat(MapChain(pm), ",") or "?",
      "| Quest Givers option:", db.mk_givers and "on" or "OFF", "| Use Questie:", db.mk_questie ~= false and "on" or "off")
    local qp = type(_G.Questie.db) == "table" and _G.Questie.db.profile
    if type(qp) == "table" then
      print("  Questie settings (read only): enableMapIcons", tostring(qp.enableMapIcons), "| enableMiniMapIcons", tostring(qp.enableMiniMapIcons),
        "| showAvailableQuests", tostring(qp.showAvailableQuests), "| enableAvailable", tostring(qp.enableAvailable),
        "| hideUnexploredMapIcons", tostring(qp.hideUnexploredMapIcons))
    end
  end
  print("  quest area glow:", AreaApi() and "supported" or "not supported by this client")
end

-- /chud debug probe: read-only report of which APIs and companion addons this client actually offers -------------
-- Prints values only; changes nothing. Meant for deciding what CHUD can safely build (corpse, party, gathering data...).
function ns.Probe()
  local function show(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if type(v) == "number" then return string.format("%.4f", v) end
    if type(v) == "table" then   -- position vectors: show the coordinates instead of the table address
      local ok, x, y = pcall(function()
        if type(v.GetXY) == "function" then return v:GetXY() end
        return v.x, v.y
      end)
      if ok and type(x) == "number" and type(y) == "number" then return string.format("(%.4f, %.4f)", x, y) end
    end
    return tostring(v)
  end
  local function call(label, fn, ...)
    if type(fn) ~= "function" then print("  " .. label .. ": MISSING"); return end
    local r = { pcall(fn, ...) }
    if not r[1] then print("  " .. label .. ": ERROR " .. tostring(r[2])); return end
    local out = {}
    for i = 2, math.max(#r, 2) do out[#out + 1] = show(r[i]) end
    print("  " .. label .. ": " .. table.concat(out, ", "))
    return r[2], r[3]
  end
  local pm = Try(C_Map.GetBestMapForUnit, "player")
  print("CHUD probe | map", tostring(pm), "| ghost", tostring(UnitIsGhost("player")), "| dead", tostring(UnitIsDead("player")),
    "| instance", tostring(IsInInstance and select(1, IsInInstance())), "| faction", tostring(UnitFactionGroup("player")))
  print("Secret values: issecretvalue", type(issecretvalue), "| C_Secrets", type(C_Secrets))

  print("-- Corpse / graveyards")
  local D = C_DeathInfo
  print("  C_DeathInfo:", D and "present" or "MISSING")
  if D and pm then
    call("GetCorpseMapPosition(map)", D.GetCorpseMapPosition, pm)
    call("GetDeathReleasePosition(map)", D.GetDeathReleasePosition, pm)
    local g = Try(D.GetGraveyardsForMap, pm)
    print("  GetGraveyardsForMap(map): " .. (type(g) == "table" and (#g .. " entries") or show(g)))
    if type(g) == "table" and g[1] then
      for k, v in pairs(g[1]) do print("    first entry field", k, show(v)) end
    end
  end
  call("HasCorpse?", _G.UnitIsGhost, "player")

  print("-- Party positions")
  local n = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
  print("  party members:", n, "| raid:", tostring(IsInRaid and IsInRaid()))
  for i = 1, math.min(n, 4) do
    local u = "party" .. i
    print("  " .. u, show(UnitName(u)), "connected", show(UnitIsConnected(u)), "visible", show(UnitIsVisible(u)))
    call("  C_Map.GetPlayerMapPosition(map," .. u .. ")", C_Map.GetPlayerMapPosition, pm, u)
    call("  UnitPosition(" .. u .. ")", UnitPosition, u)
    call("  UnitInRange(" .. u .. ")", UnitInRange, u)
  end
  if n == 0 then print("  (join a party and run /chud debug probe again to test the position calls)") end
  call("player GetPlayerMapPosition", C_Map.GetPlayerMapPosition, pm, "player")
  call("player UnitPosition", UnitPosition, "player")

  print("-- Vignettes (rare / treasure detection)")
  local V = C_VignetteInfo
  print("  C_VignetteInfo:", V and "present" or "MISSING")
  if V then
    local guids = Try(V.GetVignettes)
    print("  GetVignettes: " .. (type(guids) == "table" and (#guids .. " entries") or show(guids)))
    if type(guids) == "table" then
      for i = 1, math.min(#guids, 5) do
        local info = Try(V.GetVignetteInfo, guids[i])
        print("    ", info and show(info.name) or "?", info and show(info.atlasName) or "?")
      end
    end
  end

  print("-- Nameplates")
  print("  nameplateMaxDistance", tostring(GetCVar and GetCVar("nameplateMaxDistance")), "| nameplateShowEnemies", tostring(GetCVar and GetCVar("nameplateShowEnemies")),
    "| nameplateShowAll", tostring(GetCVar and GetCVar("nameplateShowAll")))
  local plates = Try(C_NamePlate and C_NamePlate.GetNamePlates)
  if type(plates) == "table" then
    local c = { total = #plates, players = 0, enemyPlayers = 0, rareElite = 0, targetingMe = 0, secretName = 0 }
    for _, p in ipairs(plates) do
      local u = p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit)
      if u then
        if UnitIsPlayer(u) then c.players = c.players + 1 end
        if UnitIsPlayer(u) and UnitIsEnemy("player", u) then c.enemyPlayers = c.enemyPlayers + 1 end
        local cl = UnitClassification and UnitClassification(u)
        if cl == "rare" or cl == "rareelite" or cl == "worldboss" then c.rareElite = c.rareElite + 1 end
        local ok, tgt = pcall(UnitIsUnit, u .. "target", "player")
        if ok and tgt == true then c.targetingMe = c.targetingMe + 1 end
        if issecretvalue and issecretvalue(UnitName(u)) then c.secretName = c.secretName + 1 end
      end
    end
    for k, v in pairs(c) do print("  plates." .. k, v) end
  else
    print("  C_NamePlate.GetNamePlates: unavailable")
  end

  print("-- Other addons (read only)")
  local function loaded(name) return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) or false end
  for _, name in ipairs({ "Questie", "GatherLite", "GatherMate2", "GatherMate2_Data", "RareScanner", "HereBeDragons-1.0" }) do
    print("  " .. name, loaded(name) and "loaded" or "not loaded")
  end
  local GL = _G.GatherLite
  if type(GL) == "table" then
    local nodes = Try(GL.GetNodes, GL)
    local total, kinds = 0, {}
    if type(nodes) == "table" then
      for k, list in pairs(nodes) do
        local cnt = 0
        if type(list) == "table" then for _ in pairs(list) do cnt = cnt + 1 end end
        kinds[#kinds + 1] = tostring(k) .. "=" .. cnt; total = total + cnt
      end
    end
    print("  GatherLite:GetNodes() ->", type(nodes), "| top-level groups", #kinds > 0 and table.concat(kinds, " ") or "none")
    call("GatherLite:GetNodeObject(324)", function() local o = GL:GetNodeObject(324); return o and (o.name or o.type) end)
  end
  print("CHUD probe done. Copy the output and paste it back.")
end

-- GatherMate2 investigation (/chud debug gm) -----------------------------------------------------------------------------
-- Read only. Reports whether GatherMate2 and its data addon are usable from CHUD: the API, how many nodes the live
-- database holds, whether the data addon's Forever data has been imported, and the nearest nodes to the player.
function ns.GMProbe()
  local function loaded(name) return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) or false end
  local function count(t) local n = 0; if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end return n end
  print("-- GatherMate2 probe")
  for _, name in ipairs({ "GatherMate2", "GatherMate2_Data", "GatherMate2Storage_Dragonflight", "GatherMate2Storage_TheWarWithin",
    "GatherMate2Storage_Midnight", "GatherLite", "HereBeDragons-1.0" }) do
    local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(name, "Version")
    print("  " .. name, loaded(name) and "loaded" or "not loaded", v or "")
  end
  local AA = LibStub and LibStub("AceAddon-3.0", true)
  local GM = AA and AA:GetAddon("GatherMate2", true)
  if not GM then print("  GatherMate2 addon object: NOT FOUND (AceAddon GetAddon). Nothing more to check."); return end
  print("  GatherMate2 addon object: found | db_types:", table.concat(GM.db_types or {}, ", "))
  for _, fn in ipairs({ "GetNodesForZone", "FindNearbyNode", "DecodeLoc", "GetNameForNode", "GetIDForNode" }) do
    print("  GM:" .. fn, type(GM[fn]))
  end
  print("  HBD:", GM.HBD and "present" or "absent", "| GM.db.profile.filter:", GM.db and GM.db.profile and type(GM.db.profile.filter) or "n/a")

  -- the data addon (load on demand): has its Forever data been loaded, and has it been imported into the live database?
  local raw = { ["Herb Gathering"] = "GatherMateData2HerbDB", Mining = "GatherMateData2MineDB", ["Extract Gas"] = "GatherMateData2GasDB",
    Fishing = "GatherMateData2FishDB", Treasure = "GatherMateData2TreasureDB" }
  if not loaded("GatherMate2_Data") and C_AddOns and C_AddOns.LoadAddOn then
    print("  GatherMate2_Data is load-on-demand: LoadAddOn ->", Try(C_AddOns.LoadAddOn, "GatherMate2_Data"))
  end
  for _, t in ipairs(GM.db_types or {}) do
    local live, liveZones, filtOn, filtOff = 0, 0, 0, 0
    local db = GM.gmdbs and GM.gmdbs[t]
    local base = db and db.__gm2_base_storage
    if type(base) == "table" then
      for _, nodes in pairs(base) do liveZones = liveZones + 1; live = live + count(nodes) end
    end
    local f = GM.db and GM.db.profile and GM.db.profile.filter and GM.db.profile.filter[t]
    if type(f) == "table" then for _, on in pairs(f) do if on then filtOn = filtOn + 1 else filtOff = filtOff + 1 end end end
    local r = raw[t] and _G[raw[t]]
    local rawN, rawZ = 0, 0
    if type(r) == "table" then for _, nodes in pairs(r) do rawZ = rawZ + 1; rawN = rawN + count(nodes) end end
    print(format("  %-15s live DB: %d nodes in %d zones | data addon: %d nodes in %d zones | filter on/off: %d/%d",
      t, live, liveZones, rawN, rawZ, filtOn, filtOff))
  end

  -- where the player is, and the nearest nodes of each type in this zone
  local pm = Try(C_Map.GetBestMapForUnit, "player")
  if not Num(pm) then print("  no player map (instance?)"); return end
  local pos = Try(C_Map.GetPlayerMapPosition, pm, "player")
  local px, py = XY(pos)
  local w, h = Try(C_Map.GetMapWorldSize, pm)
  print("  player map", pm, "pos", px and format("%.4f, %.4f", px, py) or "nil", "map size yd", w and format("%d x %d", w, h) or "nil")
  if not (px and Num(w) and Num(h)) then return end
  local t0 = debugprofilestop()
  local found = {}
  for _, t in ipairs(GM.db_types or {}) do
    local nearest, total, shown = nil, 0, 0
    for coord, nodeID in GM:GetNodesForZone(pm, t, true) do
      total = total + 1
      local nx, ny = GM:DecodeLoc(coord)
      local d, east, north = Dist(nx, ny, px, py, w, h)
      found[#found + 1] = { type = t, id = nodeID, d = d, east = east, north = north }
    end
    for _ in GM:GetNodesForZone(pm, t, false) do shown = shown + 1 end
    print(format("  zone %d %-15s live DB nodes: %d (%d pass the GatherMate2 filter)", pm, t, total, shown))
    -- the data addon's own tables, read directly: usable even when nothing has been imported
    local r = raw[t] and _G[raw[t]]
    local rz = type(r) == "table" and r[pm]
    if type(rz) == "table" then
      local rn, pass = 0, 0
      for coord, nodeID in pairs(rz) do
        rn = rn + 1
        local f = GM.db and GM.db.profile and GM.db.profile.filter and GM.db.profile.filter[t]
        if not f or f[nodeID] then pass = pass + 1 end
        local nx, ny = GM:DecodeLoc(coord)
        local d, east, north = Dist(nx, ny, px, py, w, h)
        found[#found + 1] = { type = t, id = nodeID, d = d, east = east, north = north, src = "data", ok = (not f) or f[nodeID] and true or false }
      end
      print(format("  zone %d %-15s data addon nodes: %d (%d pass the GatherMate2 filter)", pm, t, rn, pass))
    end
  end
  table.sort(found, function(a, b) return a.d < b.d end)
  print(format("  scanned %d nodes in %.2f ms", #found, debugprofilestop() - t0))
  do
    local imp = GM.db and GM.db.profile and GM.db.profile.importers and GM.db.profile.importers["GatherMate2_Data"]
    if imp then
      local dbs = {}
      for k, v in pairs(imp.Databases or {}) do dbs[#dbs + 1] = tostring(k) .. "=" .. tostring(v) end
      print("  import settings: style", tostring(imp.Style), "| databases", #dbs > 0 and table.concat(dbs, " ") or "none ticked", "| lastImport", tostring(imp.lastImport))
    end
  end
  for i = 1, math.min(8, #found) do
    local n = found[i]
    print(format("  #%d %-15s id %s %-22s %5d yd  bearing %3d  %s%s", i, n.type, tostring(n.id),
      tostring(GM:GetNameForNode(n.type, n.id)), n.d, Bearing(n.east, n.north), n.src or "live", n.ok == false and " (filtered out)" or ""))
  end
  if #found == 0 then
    print("  no nodes in the live database for this zone. If the data addon shows nodes above, open GatherMate2 options > Import Data and import.")
  end
end
