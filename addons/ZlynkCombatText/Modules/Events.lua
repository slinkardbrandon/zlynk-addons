local _, ns = ...

local Addon = ns.Addon
local Events = Addon:NewModule("Events", "AceEvent-3.0")

-- TODO: healing / shields / absorbs. Damage-only for now.

-- ============================================================================
-- Diagnostic trace
-- ============================================================================
-- Records raw event fires so we can diagnose future pipeline issues.
-- Stored under db.global.traceLog = { active, startedAt, entries = {...} },
-- persisted across /reload via SavedVariables. Capped at 2000 entries.

local TRACE_CAP = 2000

local function isTraceActive()
  return ns.db and ns.db.global
    and ns.db.global.traceLog
    and ns.db.global.traceLog.active == true
end

local function trace(entry)
  if not isTraceActive() then return end
  local log = ns.db.global.traceLog
  local entries = log.entries
  if #entries >= TRACE_CAP then return end
  entry.t = GetTime() - (log.startedAt or 0)
  entries[#entries + 1] = entry
end

local function safeGUID(unit)
  if type(UnitGUID) ~= "function" then return nil end
  local ok, g = pcall(UnitGUID, unit)
  if ok and type(g) == "string" and g ~= "" then return g end
  return nil
end

local function safeName(unit)
  if type(UnitName) ~= "function" then return nil end
  local ok, n = pcall(UnitName, unit)
  if ok and type(n) == "string" and n ~= "" then return n end
  return nil
end

-- ============================================================================
-- Engagement and attribution state
-- ============================================================================
--
-- A hit renders only if BOTH gates pass:
--
--   Engagement gate — "is this a mob we're actually fighting?"
--     A GUID is engaged when one of the following happens:
--       - Player SENT on a context token (target/focus/mouseover) that matches
--         the cast's target name → that token's GUID is engaged
--       - Pet SUCCEEDED → pettarget + target GUIDs are engaged
--       - pettarget poll (200ms) → the current pettarget GUID is engaged
--     Lifetime: 30s in solo (covers DoT duration), 2.5s in group (prevents
--     ally-damage leak on shared mobs; UNIT_COMBAT has no source attribution).
--
--   Attribution gate — "on engaged mobs, which hits are actually ours?"
--     A hit is attributed when:
--       (1) A player cast succeeded inside the school-appropriate window
--       (2) A pet cast succeeded inside the magic-cast window
--       (3) One of our recent periodic spells has a debuff on the victim
--           (solo only — catches DoT ticks past the direct-cast window)
--       (4) A physical hit + pet in combat + GUID recently seen as pettarget
--           (solo only — catches pet auto-attacks, no cast event exists)
--
-- Dropping cases: anything on a non-engaged GUID (prevents stranger damage on
-- untouched mobs), and engaged hits that match none of (1)-(4) (prevents
-- stranger damage on our engaged mobs during dead-air moments).

local engaged = {}               -- guid → engageTime
local lastPlayerCastAt = 0
local lastPlayerCastSpellId = nil
local lastPlayerCastSchool = nil -- Learned from the first UNIT_COMBAT hit that
                                 -- `playerCastRecent` claims. Subsequent hits
                                 -- in the same window must match this school
                                 -- or they're treated as someone else's.
local lastPetCastAt = 0
local recentPlayerSpells = {}    -- spellId → castAt
local spellIdSchools = {}        -- spellId → school (learned over time)
local recentPetTargets = {}      -- guid → snapshot-time

local PERIODIC_DEBUFF_WINDOW = 30.0  -- Cover the longest DoT we might place
local PET_TARGET_WINDOW = 5.0        -- Pet-auto inference window

local function engagementWindow()
  if type(IsInGroup) == "function" and IsInGroup() then
    return ns.ENGAGEMENT_WINDOW_GROUP
  end
  return ns.ENGAGEMENT_WINDOW_SOLO
end

local function engageGUID(guid, now)
  if not guid then return end
  engaged[guid] = now or GetTime()
end

local function isEngaged(guid)
  if not guid then return false end
  local at = engaged[guid]
  if not at then return false end
  local age = GetTime() - at
  if age > engagementWindow() then
    engaged[guid] = nil
    return false
  end
  return true
end

local function recordPlayerCast(spellId)
  lastPlayerCastAt = GetTime()
  lastPlayerCastSpellId = spellId
  -- Clear the learned school for this cast; the first attributed hit after
  -- this cast will set it (and we'll also cache it by spellId).
  lastPlayerCastSchool = nil
  if type(spellId) == "number" then
    recentPlayerSpells[spellId] = lastPlayerCastAt
  end
end

local function recordPetCast()
  lastPetCastAt = GetTime()
  local now = lastPetCastAt
  local petTargetGuid = safeGUID("pettarget")
  local targetGuid = safeGUID("target")
  if petTargetGuid then
    recentPetTargets[petTargetGuid] = now
    engageGUID(petTargetGuid, now)
  end
  if targetGuid then
    recentPetTargets[targetGuid] = now
    engageGUID(targetGuid, now)
  end
end

local function playerCastRecent(school, now)
  if lastPlayerCastAt == 0 then return false end
  local isPhysical = ns.isSafeNumber(school) and school == 1
  local window = isPhysical
    and ns.PLAYER_CAST_WINDOW_PHYSICAL
    or ns.PLAYER_CAST_WINDOW_MAGIC
  if (now - lastPlayerCastAt) > window then return false end
  -- School must match the cast we did. First hit after a cast learns the
  -- school (we don't have a direct API for spell school); later hits in the
  -- window must match. A fresh cast with unknown school first uses cached
  -- school-by-spellId if we've seen it before.
  if lastPlayerCastSchool == nil and lastPlayerCastSpellId then
    lastPlayerCastSchool = spellIdSchools[lastPlayerCastSpellId]
  end
  if lastPlayerCastSchool == nil then
    return true  -- haven't learned yet; the first hit sets it
  end
  if not ns.isSafeNumber(school) then return false end
  return school == lastPlayerCastSchool
end

local function learnCastSchool(school)
  if not ns.isSafeNumber(school) then return end
  if lastPlayerCastSchool == nil then
    lastPlayerCastSchool = school
  end
  if lastPlayerCastSpellId then
    spellIdSchools[lastPlayerCastSpellId] = school
  end
end

local function petCastRecent(now)
  if lastPetCastAt == 0 then return false end
  return (now - lastPetCastAt) <= ns.PLAYER_CAST_WINDOW_MAGIC
end

-- Does this unit carry a debuff from one of OUR recently-cast spells, whose
-- school matches the incoming hit? Used to catch DoT ticks past the direct-
-- cast window. School-gating prevents attributing a stranger's hit on a mob
-- that happens to carry our DoT — their spell likely has a different school.
local function hasOurRecentDebuff(unitToken, hitSchool)
  if not AuraUtil or type(AuraUtil.FindAuraBySpellId) ~= "function" then
    return false
  end
  if not ns.isSafeNumber(hitSchool) then return false end
  local now = GetTime()
  for spellId, castAt in pairs(recentPlayerSpells) do
    if (now - castAt) <= PERIODIC_DEBUFF_WINDOW then
      local spellSchool = spellIdSchools[spellId]
      -- Only accept when we've learned this spell's school AND it matches.
      -- If we haven't learned the school yet (pure-DoT cast with no observed
      -- direct hit), we conservatively skip — better to miss the first tick
      -- than to attribute a stranger's hit.
      if spellSchool == hitSchool then
        local ok, aura = pcall(
          AuraUtil.FindAuraBySpellId, spellId, unitToken, "HARMFUL|PLAYER"
        )
        if ok and aura then return true end
      end
    end
  end
  return false
end

local function isPetInCombat()
  if type(UnitExists) ~= "function" or type(UnitAffectingCombat) ~= "function" then
    return false
  end
  local okEx, hasPet = pcall(UnitExists, "pet")
  if not okEx or not hasPet then return false end
  local okC, inCombat = pcall(UnitAffectingCombat, "pet")
  return okC and inCombat == true
end

local function looksLikePetAuto(guid, school, now)
  if not guid then return false end
  if not (ns.isSafeNumber(school) and school == 1) then return false end
  if not isPetInCombat() then return false end
  local seenAt = recentPetTargets[guid]
  if not seenAt then return false end
  return (now - seenAt) <= PET_TARGET_WINDOW
end

local function sweepAttributionState()
  local now = GetTime()
  for spellId, castAt in pairs(recentPlayerSpells) do
    if (now - castAt) > PERIODIC_DEBUFF_WINDOW then
      recentPlayerSpells[spellId] = nil
    end
  end
  for guid, seenAt in pairs(recentPetTargets) do
    if (now - seenAt) > PET_TARGET_WINDOW * 2 then
      recentPetTargets[guid] = nil
    end
  end
  local engWindow = engagementWindow()
  for guid, engAt in pairs(engaged) do
    if (now - engAt) > engWindow then
      engaged[guid] = nil
    end
  end
end

-- ============================================================================
-- Instance state
-- ============================================================================

function Events:UpdateInstanceState()
  local _, instanceType = GetInstanceInfo()
  self.instanceType = instanceType
end

function Events:IsContentSuppressed()
  local filters = ns.db.profile.filters
  if self.instanceType == "arena" and filters.suppressArena then return true end
  if self.instanceType == "pvp" and filters.suppressBG then return true end
  return false
end

local function isGroupContent()
  return type(IsInGroup) == "function" and IsInGroup()
end

-- ============================================================================
-- Emit
-- ============================================================================

function Events:Emit(eventType, anchorUnit, anchorGUID, rawValue, school, isCrit, spellId)
  if not ns.db.profile.enabled then return end
  if self:IsContentSuppressed() then return end

  local profile = ns.db.profile
  if eventType == ns.EVENT_TYPE.OUTGOING_DAMAGE and not profile.outgoing.damage then return end
  if eventType == ns.EVENT_TYPE.INCOMING_DAMAGE and not profile.incoming.damage then return end
  if eventType == ns.EVENT_TYPE.PET_DAMAGE and not profile.outgoing.pet then return end
  if eventType == ns.EVENT_TYPE.PET_INCOMING_DAMAGE and not profile.incoming.pet then return end

  if not ns.passesThreshold(rawValue, ns.db.profile.filters.minDamage) then return end

  local rawPipeId = ns.allocRawPipe(rawValue)
  Addon:SendMessage("ZCT_COMBAT_EVENT", {
    type = eventType,
    rawPipeId = rawPipeId,
    school = school or 1,
    isCrit = isCrit or false,
    timestamp = GetTime(),
    anchorUnit = anchorUnit,
    anchorGUID = anchorGUID,
    spellId = spellId,
  })
end

-- ============================================================================
-- UNIT_COMBAT dispatch
-- ============================================================================

local function isNameplateToken(unit)
  if type(unit) ~= "string" then return false end
  return unit:match("^nameplate%d+$") ~= nil
end

-- Attribution decision. Returns an event type enum or nil (drop).
local function attribute(unitToken, guid, school, now, groupMode)
  if playerCastRecent(school, now) then
    learnCastSchool(school)
    return ns.EVENT_TYPE.OUTGOING_DAMAGE
  end
  if petCastRecent(now) then
    return ns.EVENT_TYPE.PET_DAMAGE
  end

  -- Group mode stops here. Longer windows would attribute ally damage to us,
  -- since UNIT_COMBAT doesn't carry source info.
  if groupMode then return nil end

  if hasOurRecentDebuff(unitToken, school) then
    return ns.EVENT_TYPE.OUTGOING_DAMAGE
  end
  if looksLikePetAuto(guid, school, now) then
    return ns.EVENT_TYPE.PET_DAMAGE
  end
  return nil
end

function Events:OnUnitCombat(_, unit, event, flagText, amount, school)
  if isTraceActive() then
    trace({
      e = "UNIT_COMBAT",
      unit = unit,
      guid = safeGUID(unit),
      name = safeName(unit),
      event = event,
      flag = flagText,
      amount = ns.isSafeNumber(amount) and amount or "<secret>",
      school = school,
    })
  end

  if event ~= "WOUND" then return end  -- damage-only for now

  local isCrit = (flagText == "CRITICAL")

  local ok, safeAmount = pcall(function() return amount end)
  if not ok then safeAmount = amount end

  if unit == "player" then
    self:Emit(ns.EVENT_TYPE.INCOMING_DAMAGE, "player", safeGUID("player"),
      safeAmount, school, isCrit, nil)
    return
  end
  if unit == "pet" then
    self:Emit(ns.EVENT_TYPE.PET_INCOMING_DAMAGE, "pet", safeGUID("pet"),
      safeAmount, school, isCrit, nil)
    return
  end

  if not isNameplateToken(unit) then return end

  local guid = safeGUID(unit)
  if not guid then return end

  -- Engagement gate: only hits on mobs we've attacked are eligible. Without
  -- this, any cast window would temporarily attribute every nearby mob's
  -- damage (from other players) to us.
  if not isEngaged(guid) then return end

  local now = GetTime()
  local eventType = attribute(unit, guid, school, now, isGroupContent())
  if not eventType then return end

  -- Re-engage on attributed hit to keep the mob hot through long fights.
  engageGUID(guid, now)

  self:Emit(eventType, unit, guid, safeAmount, school, isCrit, nil)
end

-- ============================================================================
-- Cast signals
-- ============================================================================

function Events:OnSpellcastSent(_, unit, targetName, castGUID, spellId)
  if isTraceActive() then
    local context = {}
    for _, tok in ipairs({ "target", "focus", "mouseover", "pettarget" }) do
      local n = safeName(tok)
      if n then
        context[tok] = { name = n, guid = safeGUID(tok), matches = (n == targetName) }
      end
    end
    trace({
      e = "UNIT_SPELLCAST_SENT",
      unit = unit,
      targetName = targetName,
      castGUID = castGUID,
      spellId = spellId,
      context = context,
    })
  end

  if unit ~= "player" then return end

  local now = GetTime()

  -- Record the spell for the DoT-debuff check.
  if type(spellId) == "number" then
    recentPlayerSpells[spellId] = now
  end

  -- Engage whichever context token actually matches the cast's target name.
  -- Handles focus macros, mouseover casts, and cases where the same name is
  -- on multiple nearby mobs (we trust the TOKEN's GUID, not the name).
  if type(targetName) == "string" and targetName ~= "" then
    for _, tok in ipairs({ "target", "focus", "mouseover" }) do
      if safeName(tok) == targetName then
        engageGUID(safeGUID(tok), now)
      end
    end
  end
end

function Events:OnSpellcastSucceeded(_, unit, castGUID, spellId)
  if isTraceActive() then
    trace({
      e = "UNIT_SPELLCAST_SUCCEEDED",
      unit = unit,
      castGUID = castGUID,
      spellId = spellId,
    })
  end

  if unit == "player" then
    recordPlayerCast(spellId)
  elseif unit == "pet" then
    recordPetCast()
  end
end

function Events:OnTargetChanged()
  if isTraceActive() then
    trace({
      e = "PLAYER_TARGET_CHANGED",
      guid = safeGUID("target"),
      name = safeName("target"),
    })
  end
end

function Events:OnNameplateUnitAdded(_, unitToken)
  if isTraceActive() then
    trace({
      e = "NAMEPLATE_UNIT_ADDED",
      unit = unitToken,
      guid = safeGUID(unitToken),
      name = safeName(unitToken),
    })
  end
end

function Events:OnNameplateUnitRemoved(_, unitToken)
  if isTraceActive() then
    trace({
      e = "NAMEPLATE_UNIT_REMOVED",
      unit = unitToken,
      guid = safeGUID(unitToken),
      name = safeName(unitToken),
    })
  end
end

function Events:PollPetTarget()
  local guid = safeGUID("pettarget")
  if guid then
    local now = GetTime()
    recentPetTargets[guid] = now
    engageGUID(guid, now)
  end
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function Events:OnEnable()
  self:UpdateInstanceState()

  self:RegisterEvent("UNIT_COMBAT", "OnUnitCombat")
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
  self:RegisterEvent("UNIT_SPELLCAST_SENT", "OnSpellcastSent")
  self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")
  self:RegisterEvent("NAMEPLATE_UNIT_ADDED", "OnNameplateUnitAdded")
  self:RegisterEvent("NAMEPLATE_UNIT_REMOVED", "OnNameplateUnitRemoved")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateInstanceState")
  self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "UpdateInstanceState")

  self.sweepTicker = C_Timer.NewTicker(5, sweepAttributionState)
  self.petTargetTicker = C_Timer.NewTicker(0.2, function() self:PollPetTarget() end)
end

function Events:OnDisable()
  if self.sweepTicker then
    self.sweepTicker:Cancel()
    self.sweepTicker = nil
  end
  if self.petTargetTicker then
    self.petTargetTicker:Cancel()
    self.petTargetTicker = nil
  end
  recentPlayerSpells = {}
  spellIdSchools = {}
  recentPetTargets = {}
  engaged = {}
  lastPlayerCastSpellId = nil
  lastPlayerCastSchool = nil
end
