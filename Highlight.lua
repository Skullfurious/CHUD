local ADDON, ns = ...

-- Highlight: lights up the real gathering node in the world when you reach it, and notices when it is not there.
--
-- How: the game's own "soft interact" targeting picks the one object you could interact with (unit token "softinteract")
-- and gives it a nameplate, which is a frame the game keeps on that object's position on screen. CHUD anchors a small
-- effect (brackets, a slowly turning ring, a halo) to that nameplate. This only works inside the game's soft-target range
-- (about 15 yards), which is why the compass leads you there and this takes over for the last stretch.
--
-- It needs a few game settings (the SoftTarget CVars). CHUD writes only the ones that differ, remembers the player's
-- values, and gives them back when the option is turned off or on logout. If another addon (Lueur) already set them,
-- nothing is written. Nothing is written in combat; it waits until combat ends.
--
-- Reaching a node: the Next Node counts as visited when the game targets an object of its kind (within about 15 yards), or
-- when you are within SURE_R yards, or MISS_TIME seconds after you first got within CHECK_R yards (leaving the radius does not
-- cancel that timer). If the timer ends while you are still near and facing the spot with nothing detected, the node is
-- treated as gone and the "Node Not Here" effect plays; otherwise the visit is registered quietly.

local SOFT = "softinteract"
local MEDIA = "Interface\\AddOns\\CHUD\\media\\"
local floor, max, sin, lower = math.floor, math.max, math.sin, string.lower
local CHECK_R = 12       -- yards: inside this for MISS_TIME, the visit counts whether or not the game found the object
local SURE_R = 7        -- yards: this close, the node counts as reached by distance alone, even if the game is not targeting it
local MISS_TIME = 0.5    -- seconds inside CHECK_R without a matching object before the visit is registered anyway
local RANGE = "15"       -- soft-target search range the game accepts (meters)

-- Calls fn under pcall and returns its first result, or nil.
local function Safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a = pcall(fn, ...)
  if ok then return a end
end
-- True when the game is hiding this value from addons.
local function Secret(v) return issecretvalue and issecretvalue(v) end

-- Game settings -------------------------------------------------------------------------------------

local WANT = {
  { "SoftTargetInteract", "3" }, { "SoftTargetInteractRange", RANGE }, { "SoftTargetInteractArc", "2" },
  { "SoftTargetInteractOnlyInRange", "0" }, { "SoftTargetInteractRangeIsHard", "0" },
  { "SoftTargetNameplateInteract", "1" }, { "SoftTargetIconGameObject", "1" },
}
-- Reads a game setting (CVar).
local function GetC(name) return Safe(C_CVar and C_CVar.GetCVar or GetCVar, name) end
-- Writes a game setting (CVar).
local function SetC(name, value)
  if GetC(name) == nil then return end   -- a setting this client does not have
  pcall(C_CVar and C_CVar.SetCVar or SetCVar, name, tostring(value))
end
local pending
-- True when the Highlight Node option is on.
local function Enabled() return ns.db and ns.db.mk_hl ~= false and (ns.db.mk_herbs or ns.db.mk_ore or ns.db.mk_containers or ns.db.mk_gnext ~= false) end

-- Sets the game settings the highlight needs. Only the ones that differ are written, the originals are remembered, and nothing is written in combat.
local function Apply()
  local db = ns.db
  if not db then return end
  if InCombatLockdown() then pending = "apply"; return end
  db.hlSaved = db.hlSaved or {}
  for _, w in ipairs(WANT) do
    local cur = GetC(w[1])
    if cur ~= nil and cur ~= w[2] then
      if db.hlSaved[w[1]] == nil then db.hlSaved[w[1]] = cur end
      SetC(w[1], w[2])
    end
  end
  -- game objects get a nameplate only within this distance
  local far = tonumber(GetC("nameplateGameObjectMaxDistance"))
  if far and far < 60 then
    if db.hlSaved.nameplateGameObjectMaxDistance == nil then db.hlSaved.nameplateGameObjectMaxDistance = tostring(far) end
    SetC("nameplateGameObjectMaxDistance", 60)
  end
end
-- Gives the player's original game settings back (after combat if needed).
local function Restore()
  local db = ns.db
  if not (db and db.hlSaved) then return end
  if InCombatLockdown() then pending = "restore"; return end
  for name, value in pairs(db.hlSaved) do SetC(name, value) end
  db.hlSaved = nil
end
-- True when the game's soft interact targeting is on.
local function SoftOn() return GetC("SoftTargetInteract") == "3" end
-- True while the game is actually giving CHUD an interact target to read.
local function Detecting() return Enabled() and SoftOn() end

-- What an object is ------------------------------------------------------------------------------------

local nameKinds, namesAt
-- Builds the object-name to kind lookup from the imported gathering data.
local function BuildNames()
  local g = ns.db and ns.db.gdata
  local stamp = g and g.at or "-"
  if nameKinds and namesAt == stamp then return end
  nameKinds, namesAt = {}, stamp
  if g and g.kinds and g.names then
    for _, kind in ipairs({ "herb", "ore", "box" }) do
      for _, z in pairs(g.kinds[kind] or {}) do
        for i = 1, #z.n do
          local nm = g.names[z.n[i]]
          if nm then nameKinds[lower(nm)] = kind end
        end
      end
    end
  end
end
-- The kind (herb, ore, box) of an object by name, from the data or from words like "chest" and "vein".
local function KindOf(name)
  if type(name) ~= "string" or name == "" then return nil end
  BuildNames()
  local n = lower(name)
  local k = nameKinds[n]
  if k then return k end
  if n:find("chest") or n:find("lockbox") or n:find("footlocker") or n:find("strongbox") or n:find("giant clam") then return "box" end
  if n:find(" vein") or n:find("deposit") or n:find("obsidian chunk") then return "ore" end
  return nil
end

local COLORS = { ore = { 1, 0.6, 0.18 }, herb = { 0.4, 1, 0.42 }, box = { 0.45, 0.78, 1 } }

-- The object the game is targeting now: its name, kind, and nameplate.
local function Current()
  if Safe(UnitIsGameObject, SOFT) ~= true then return nil end
  local name = Safe(UnitName, SOFT)
  if Secret(name) or type(name) ~= "string" then name = nil end
  local plate = Safe(C_NamePlate and C_NamePlate.GetNamePlateForUnit, SOFT)
  return name, KindOf(name), plate
end

-- The effect ---------------------------------------------------------------------------------------------

local fx
-- The highlight frame (halo, ring, brackets, name), created on first use.
local function FX()
  if fx then return fx end
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(130, 130); f:SetFrameStrata("BACKGROUND"); f:Hide()
  f.halo = f:CreateTexture(nil, "BACKGROUND"); f.halo:SetTexture(MEDIA .. "glow.tga"); f.halo:SetAllPoints(); f.halo:SetBlendMode("ADD")
  f.ring = f:CreateTexture(nil, "ARTWORK"); f.ring:SetTexture(MEDIA .. "ring.tga"); f.ring:SetSize(86, 86)
  f.ring:SetPoint("CENTER"); f.ring:SetBlendMode("ADD")
  f.spin = f.ring:CreateAnimationGroup()
  local rot = f.spin:CreateAnimation("Rotation"); rot:SetDegrees(-360); rot:SetDuration(16)
  f.spin:SetLooping("REPEAT")
  f.br = {}
  for i = 1, 4 do
    local b = f:CreateTexture(nil, "OVERLAY"); b:SetTexture(MEDIA .. "bracket.tga"); b:SetSize(18, 18); b:SetBlendMode("ADD")
    f.br[i] = b
  end
  f.br[1]:SetPoint("TOPLEFT", f, "CENTER", -48, 48)
  f.br[2]:SetPoint("TOPRIGHT", f, "CENTER", 48, 48);      f.br[2]:SetTexCoord(1, 0, 0, 1)
  f.br[3]:SetPoint("BOTTOMLEFT", f, "CENTER", -48, -48);  f.br[3]:SetTexCoord(0, 1, 1, 0)
  f.br[4]:SetPoint("BOTTOMRIGHT", f, "CENTER", 48, -48);  f.br[4]:SetTexCoord(1, 0, 1, 0)
  f.fs = f:CreateFontString(nil, "OVERLAY"); f.fs:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
  f.fs:SetPoint("BOTTOM", f, "CENTER", 0, 54)
  f:SetScript("OnUpdate", function(self)
    local t = GetTime()
    self:SetAlpha(0.75 + 0.25 * sin(t * 3.4))
    local s = 1 + 0.04 * sin(t * 2.2)
    for i = 1, 4 do self.br[i]:SetSize(18 * s, 18 * s) end
  end)
  fx = f
  return f
end
-- Hides the highlight.
local function Hide() if fx and fx:IsShown() then fx:Hide(); fx.spin:Stop() end end

-- Shows the highlight on the object the game is targeting when it is a node kind that is switched on, else hides it.
local function Evaluate()
  local db = ns.db
  if not db or db.mk_hl == false or not SoftOn() then Hide(); return end
  local name, kind, plate = Current()
  if not (kind and plate) or db[kind == "box" and "mk_containers" or kind == "ore" and "mk_ore" or "mk_herbs"] == false then Hide(); return end
  local f = FX()
  local c = COLORS[kind]
  f.halo:SetVertexColor(c[1], c[2], c[3], 0.55)
  f.ring:SetVertexColor(c[1], c[2], c[3], 0.9)
  for i = 1, 4 do f.br[i]:SetVertexColor(c[1], c[2], c[3], 1) end
  f.fs:SetTextColor(c[1], c[2], c[3], 1); f.fs:SetText(name or "")
  f:ClearAllPoints(); f:SetPoint("CENTER", plate, "CENTER", 0, -45)
  if not f:IsShown() then f:Show(); f.spin:Play() end
end

-- Reached / not there ------------------------------------------------------------------------------------

local missSince
local matched = false
-- Called by the pointer before it counts a node as reached.
function ns.ReachGate(t)
  if InCombatLockdown() or not (t and t.nodeKind) or not Detecting() then return true end   -- in combat the game's targeting is not reliable: distance alone decides
  return matched or (t.dist ~= nil and t.dist < SURE_R)   -- the game only targets what you face; up close, distance decides
end
-- True while the game is targeting an object of the pointer's kind (and the highlight is therefore showing).
function ns.SoftMatched() return matched and not InCombatLockdown() end
local pend   -- { key, at }: the pointer's node was entered (inside CHECK_R) at `at` and has not been confirmed yet
-- Decides whether the pointer's node has been reached or is gone: see the explanation at the top of this file.
local function Check()
  matched = false
  if not Detecting() then missSince = nil; pend = nil; return end
  local _, kind = Current()
  local t = ns.PointerInfo and ns.PointerInfo()
  if not (t and t.dist and t.nodeKind) then missSince = nil; return end
  if kind == t.nodeKind then
    matched, pend = true, nil
    if ns.CheckPointerReach then ns.CheckPointerReach() end
    return
  end
  local now = GetTime()
  -- Getting inside CHECK_R starts a short timer for that node. Walking out again does not cancel it: when it runs out the
  -- node counts as visited either way, so a fast pass or a few yards of drift still clears it.
  if t.dist <= CHECK_R and not InCombatLockdown() and not UnitIsDeadOrGhost("player") and not (pend and pend.key == t.key) then
    pend = { key = t.key, at = now }
  end
  if pend and now - pend.at >= MISS_TIME then
    local p = pend
    pend = nil
    -- Still near and facing the spot with nothing there: the node is gone (big effect). Otherwise the game may simply not be
    -- looking at it (it targets what you face, and height matters), so the visit is registered quietly.
    local facing
    if p.key == t.key and t.dist <= CHECK_R then
      local ok, f = pcall(GetPlayerFacing)
      if ok and type(f) == "number" and not Secret(f) and t.bearing then
        local heading = (360 - math.deg(f)) % 360
        facing = math.abs(((t.bearing - heading + 540) % 360) - 180) <= 50
      end
    end
    if facing and ns.NodeMissing then ns.NodeMissing() elseif ns.ForceVisit then ns.ForceVisit(p.key) end
  end
end


-- "Not here" ---------------------------------------------------------------------------------------------
-- An obvious but short effect, because a missing node otherwise looks like nothing happened: a title that drops in with a small
-- shake, two rings that spread out, and a soft click.
local nh
-- The "Node Not Here" effect frame, created on first use.
local function NotHere()
  if nh then return nh end
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(300, 90); f:SetFrameStrata("HIGH"); f:SetPoint("TOP", UIParent, "TOP", 0, -190); f:Hide()
  f.rings = {}
  for i = 1, 2 do
    local r = f:CreateTexture(nil, "BACKGROUND"); r:SetTexture(MEDIA .. "ring.tga"); r:SetBlendMode("ADD")
    r:SetPoint("CENTER", f, "CENTER", 0, 10); f.rings[i] = r
  end
  f.glow = f:CreateTexture(nil, "BACKGROUND"); f.glow:SetTexture(MEDIA .. "glow.tga"); f.glow:SetBlendMode("ADD")
  f.glow:SetPoint("CENTER", f, "CENTER", 0, 10); f.glow:SetSize(250, 100); f.glow:SetVertexColor(1, 0.3, 0.2, 0.5)
  f.title = f:CreateFontString(nil, "OVERLAY"); f.title:SetFont(STANDARD_TEXT_FONT, 20, "OUTLINE")
  f.title:SetPoint("CENTER", f, "CENTER", 0, 20); f.title:SetText("Node Not Here"); f.title:SetTextColor(1, 0.35, 0.2, 1)
  f.sub = f:CreateFontString(nil, "OVERLAY"); f.sub:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
  f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -6); f.sub:SetTextColor(1, 0.8, 0.6, 1)
  f:SetScript("OnUpdate", function(self)
    local age = GetTime() - self.t0
    if age > 1.8 then self:Hide(); return end
    local shake = age < 0.3 and sin(age * 70) * 3 * (1 - age / 0.3) or 0
    self.title:ClearAllPoints(); self.title:SetPoint("CENTER", self, "CENTER", shake, 20)
    local pop = age < 0.2 and (1.25 - 1.25 * age) or 1   -- lands from 1.25x down to 1x
    self.title:SetTextColor(1, 0.35 + 0.15 * sin(age * 14), 0.2, 1)
    self.title:SetScale(pop)
    self.glow:SetAlpha(max(0, 0.7 - age * 0.45))
    for i, r in ipairs(self.rings) do
      local a = age - (i - 1) * 0.25
      if a > 0 and a < 0.9 then
        local k = a / 0.9
        r:SetSize(40 + 160 * k, 40 + 160 * k); r:SetVertexColor(1, 0.3, 0.2, (1 - k) * 0.6); r:Show()
      else r:Hide() end
    end
    self:SetAlpha(age > 1.3 and (1.8 - age) / 0.5 or 1)
  end)
  nh = f
  return f
end
-- Plays the "Node Not Here" effect with the node's name.
function ns.NotHereFX(name)
  local f = NotHere()
  f.sub:SetText((name and name ~= "") and (name .. " is gone, moving to the next one") or "Moving to the next one")
  f.t0 = GetTime()
  f:SetAlpha(1); f:Show()
  pcall(PlaySound, 856)   -- a soft click, not the raid warning
end

-- Events -------------------------------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
  "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGOUT" then Restore(); return end
  if event == "PLAYER_REGEN_ENABLED" then
    local p = pending; pending = nil
    if p == "restore" then Restore() elseif Enabled() then Apply() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- the client can reset some of these right after loading, so apply twice
    C_Timer.After(1.5, function() if Enabled() then Apply() end; Evaluate() end)
    C_Timer.After(5, function() if Enabled() then Apply() end; Evaluate() end)
    return
  end
  Evaluate()
  if Enabled() then Check() end   -- the game just changed its target: update "matched" now, not at the next tick
end)
C_Timer.NewTicker(0.1, function()
  if Enabled() then Check() else matched = false; missSince = nil end
  Evaluate()
end)

-- The marker menu calls this when the option changes.
-- The warning shown when Highlight Node is turned on, and on the setup tour's data page.
ns.HL_WARN = "Highlight Node uses the game's soft interact targeting, which also puts a nameplate on nearby NPCs you can interact with. Turn it off to stop that; your own game settings are put back."
-- Tells the player about the NPC nameplate side effect in chat and on screen.
function ns.HighlightWarn()
  print("|cffd9bf4dCHUD:|r |cffffb347" .. ns.HL_WARN .. "|r")
  if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage("CHUD: Highlight Node also shows nameplates on nearby NPCs.", 1, 0.7, 0.3) end
end
function ns.HighlightChanged()
  if Enabled() then Apply() else Restore(); Hide() end
  Evaluate()
end

-- What the game is targeting and what CHUD made of it (/chud debug soft).
function ns.SoftProbe()
  local out = {}
  local function add(s) out[#out + 1] = s end
  add("Highlight option: " .. tostring(ns.db and ns.db.mk_hl ~= false) .. " | soft target on: " .. tostring(SoftOn()) .. " | detecting: " .. tostring(Detecting()))
  for _, w in ipairs(WANT) do add(format("  %s = %s (wanted %s)", w[1], tostring(GetC(w[1])), w[2])) end
  local isObj = Safe(UnitIsGameObject, SOFT)
  local exists = Safe(UnitExists, SOFT)
  local name, kind, plate = Current()
  add(format("softinteract: exists=%s gameObject=%s name=%s kind=%s plate=%s", tostring(exists), tostring(isObj), tostring(name), tostring(kind), tostring(plate ~= nil)))
  local pm = Safe(C_Map.GetBestMapForUnit, "player")
  local vec = pm and Safe(C_Map.GetPlayerMapPosition, pm, "player")
  local ok, px, py = false, nil, nil
  if vec then ok, px, py = pcall(vec.GetXY, vec) end
  add(format("combat=%s | map=%s | position readable=%s x=%s secret=%s", tostring(InCombatLockdown()), tostring(pm), tostring(ok and type(px) == "number" and not Secret(px)), tostring(not Secret(px) and px or "?"), tostring(Secret(px) and true or false)))
  local t = ns.PointerInfo and ns.PointerInfo()
  if t then add(format("pointer: %s kind=%s dist=%s | matched=%s enteredFor=%s", tostring(t.nodeName), tostring(t.nodeKind), tostring(t.dist and floor(t.dist)), tostring(matched), pend and format("%.1fs", GetTime() - pend.at) or "-")) else add("pointer: none") end
  for _, line in ipairs(out) do print(line) end
end
