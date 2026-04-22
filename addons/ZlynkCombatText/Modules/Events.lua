local _, ns = ...

local Addon = ns.Addon
local Events = Addon:NewModule("Events", "AceEvent-3.0")

-- Internal state
local castQueue = {}      -- pending casts: { spellId, timestamp }
local castQueueSize = 0

-- Instance state detection
function Events:UpdateInstanceState()
  local _, instanceType = GetInstanceInfo()
  self.inGroupInstance = (instanceType == "party" or instanceType == "raid")
end

function Events:IsContentSuppressed()
  local _, instanceType = GetInstanceInfo()
  local filters = ns.db.profile.filters
  if instanceType == "arena" and filters.suppressArena then return true end
  if instanceType == "pvp" and filters.suppressBG then return true end
  return false
end

-- Cast queue management
function Events:PushCast(spellId)
  local entry = { spellId = spellId, timestamp = GetTime() }
  castQueueSize = castQueueSize + 1
  castQueue[castQueueSize] = entry
  C_Timer.After(ns.CAST_QUEUE_EXPIRY, function()
    entry.expired = true
  end)
end

function Events:ConsumeBestCast(spellId)
  for i = castQueueSize, 1, -1 do
    local entry = castQueue[i]
    if not entry.expired and not entry.consumed then
      if entry.spellId == spellId or spellId == nil then
        entry.consumed = true
        return entry
      end
    end
  end
  return nil
end

-- Like ConsumeBestCast but only consumes if the most recent candidate is
-- within `maxAge` seconds. Used by the pet/player disambiguation path —
-- walking the queue from newest to oldest, so the first candidate too old
-- implies every older candidate is too old as well.
function Events:ConsumeBestCastWithinWindow(maxAge)
  local now = GetTime()
  for i = castQueueSize, 1, -1 do
    local entry = castQueue[i]
    if not entry.expired and not entry.consumed then
      if (now - entry.timestamp) > maxAge then
        return nil
      end
      entry.consumed = true
      return entry
    end
  end
  return nil
end

-- Cleanup stale cast queue entries periodically
function Events:CleanCastQueue()
  local writeIdx = 1
  for i = 1, castQueueSize do
    local entry = castQueue[i]
    if not entry.expired and not entry.consumed then
      castQueue[writeIdx] = entry
      writeIdx = writeIdx + 1
    else
      castQueue[i] = nil
    end
  end
  castQueueSize = writeIdx - 1
end

-- Emit a combat event to the display module
function Events:Emit(eventType, rawValue, school, isCrit)
  if not ns.db.profile.enabled then return end
  if self:IsContentSuppressed() then return end

  -- Per-direction toggle check
  local profile = ns.db.profile
  if eventType == ns.EVENT_TYPE.OUTGOING_DAMAGE and not profile.outgoing.damage then return end
  if eventType == ns.EVENT_TYPE.OUTGOING_HEAL and not profile.outgoing.healing then return end
  if eventType == ns.EVENT_TYPE.INCOMING_DAMAGE and not profile.incoming.damage then return end
  if eventType == ns.EVENT_TYPE.INCOMING_HEAL and not profile.incoming.healing then return end
  if eventType == ns.EVENT_TYPE.PET_DAMAGE and not profile.outgoing.pet then return end
  if eventType == ns.EVENT_TYPE.PET_INCOMING_DAMAGE and not profile.incoming.pet then return end

  -- Threshold check
  local threshold
  if eventType == ns.EVENT_TYPE.OUTGOING_HEAL or eventType == ns.EVENT_TYPE.INCOMING_HEAL then
    threshold = ns.db.profile.filters.minHealing
  else
    threshold = ns.db.profile.filters.minDamage
  end
  if not ns.passesThreshold(rawValue, threshold) then return end

  -- Store raw value in pipe and emit
  local rawPipeId = ns.allocRawPipe(rawValue)
  Addon:SendMessage("ZCT_COMBAT_EVENT", {
    type = eventType,
    rawPipeId = rawPipeId,
    school = school or 1,
    isCrit = isCrit or false,
    timestamp = GetTime(),
  })
end

-- Track the last spell the player cast (for DoT/HoT attribution)
local lastPlayerSpellId = nil
local recentPeriodicSpells = {}  -- spellId → timestamp of last cast

-- Is the player's pet currently in combat? Gates pet-damage inference so we
-- don't attribute random leaked target damage to a non-existent pet.
local function isPetInCombat()
  if type(UnitExists) ~= "function" or type(UnitAffectingCombat) ~= "function" then
    return false
  end
  local okEx, hasPet = pcall(UnitExists, "pet")
  if not okEx or not hasPet then return false end
  local okCombat, inCombat = pcall(UnitAffectingCombat, "pet")
  return okCombat and inCombat == true
end

-- Does the target currently have a debuff matching the given spell ID? Used
-- to decide whether a magic WOUND event on target is a tick from that DoT.
-- Without this check, any recent non-periodic cast (e.g. Shadow Bolt) could
-- "stick" as the attributed spell for unrelated magic WOUND events.
local function hasTargetDebuffSpellId(spellId)
  if type(spellId) ~= "number" then return false end
  if not AuraUtil or type(AuraUtil.FindAuraBySpellId) ~= "function" then
    return false
  end
  local ok, aura = pcall(AuraUtil.FindAuraBySpellId, spellId, "target", "HARMFUL")
  return ok and aura ~= nil
end

-- Pick the most-recent recently-cast periodic spell whose debuff is still on
-- target. Returns nil when no cached periodic cast fits.
local function mostRecentActiveDotSpellId()
  local now = GetTime()
  local bestId, bestAt
  for spellId, castedAt in pairs(recentPeriodicSpells) do
    if (now - castedAt) <= ns.PERIODIC_OUTGOING_WINDOW then
      if (not bestAt) or castedAt > bestAt then
        bestAt = castedAt
        bestId = spellId
      end
    end
  end
  if bestId and hasTargetDebuffSpellId(bestId) then
    return bestId
  end
  return nil
end

-- Event handlers

-- UNIT_COMBAT — handles player (incoming), target (outgoing attribution),
-- and pet (pet-received damage).
function Events:OnUnitCombat(_, unit, event, flagText, amount, school)
  local ok, safeAmount = pcall(function() return amount end)
  if not ok then safeAmount = amount end

  local isCrit = (flagText == "CRITICAL")
  local isPhysical = ns.isSafeNumber(school) and school == 1

  if unit == "player" then
    -- Incoming damage/healing (always reliable)
    if event == "WOUND" then
      self:Emit(ns.EVENT_TYPE.INCOMING_DAMAGE, safeAmount, school, isCrit)
    elseif event == "HEAL" then
      self:Emit(ns.EVENT_TYPE.INCOMING_HEAL, safeAmount, school, isCrit)
    end
    return
  end

  if unit == "pet" then
    -- Damage taken by the pet
    if event == "WOUND" then
      self:Emit(ns.EVENT_TYPE.PET_INCOMING_DAMAGE, safeAmount, school, isCrit)
    end
    return
  end

  if unit ~= "target" then return end

  -- Skip in group instances (UNIT_COMBAT("target") leaks all damage there)
  if self.inGroupInstance then return end
  if event ~= "WOUND" and event ~= "HEAL" then return end

  -- Try to attribute to a recent player cast. Window depends on hit school:
  -- physical hits are instant; non-physical spells can travel for up to ~2.5s.
  local window = isPhysical and ns.PLAYER_CAST_WINDOW_PHYSICAL or ns.PLAYER_CAST_WINDOW_MAGIC
  local match = self:ConsumeBestCastWithinWindow(window)

  if match then
    if event == "WOUND" then
      self:Emit(ns.EVENT_TYPE.OUTGOING_DAMAGE, safeAmount, school, isCrit)
    else
      self:Emit(ns.EVENT_TYPE.OUTGOING_HEAL, safeAmount, school, isCrit)
    end
    return
  end

  -- No recent cast match. For non-physical WOUND, check whether this looks
  -- like a DoT tick from a recently-cast periodic whose debuff is live.
  if event == "WOUND" and not isPhysical and mostRecentActiveDotSpellId() then
    self:Emit(ns.EVENT_TYPE.OUTGOING_DAMAGE, safeAmount, school, isCrit)
    return
  end

  -- Fall through: if the pet is in combat, treat unattributed WOUND as pet
  -- damage. HEAL events without cast attribution are dropped — pet heals on
  -- the player's target are rare and tend to be false positives.
  if event == "WOUND" and isPetInCombat() then
    self:Emit(ns.EVENT_TYPE.PET_DAMAGE, safeAmount, school, isCrit)
  end
end

-- UNIT_SPELLCAST_SUCCEEDED — build pending cast queue for correlation
function Events:OnSpellcastSucceeded(_, unit, _, spellId)
  if unit ~= "player" then return end
  self:PushCast(spellId)
  lastPlayerSpellId = spellId
  recentPeriodicSpells[spellId] = GetTime()
end

-- COMBAT_TEXT_UPDATE — primary outgoing damage/healing source
function Events:OnCombatTextUpdate()
  local ok, ctType, rawArg1, rawArg2 = pcall(C_CombatText.GetCurrentEventInfo)
  if not ok or not ctType then return end

  -- Determine event type from combat text type
  local eventType
  local isCrit = false

  if ctType == "DAMAGE" then
    eventType = ns.EVENT_TYPE.OUTGOING_DAMAGE
  elseif ctType == "DAMAGE_CRIT" then
    eventType = ns.EVENT_TYPE.OUTGOING_DAMAGE
    isCrit = true
  elseif ctType == "HEAL" then
    eventType = ns.EVENT_TYPE.OUTGOING_HEAL
  elseif ctType == "HEAL_CRIT" then
    eventType = ns.EVENT_TYPE.OUTGOING_HEAL
    isCrit = true
  elseif ctType == "PERIODIC_DAMAGE" then
    eventType = ns.EVENT_TYPE.OUTGOING_DAMAGE
  elseif ctType == "PERIODIC_HEAL" then
    eventType = ns.EVENT_TYPE.OUTGOING_HEAL
  else
    return
  end

  -- rawArg1 is typically the amount, rawArg2 may be spell ID
  local amount = rawArg1
  local ctSpellId = nil
  if ns.isSafeNumber(rawArg2) then
    ctSpellId = rawArg2
  end

  -- Attribution: match against cast queue or recent spells
  local attributed = false
  if ctSpellId then
    local match = self:ConsumeBestCast(ctSpellId)
    if match then
      attributed = true
    elseif lastPlayerSpellId and ctSpellId == lastPlayerSpellId then
      attributed = true
    elseif recentPeriodicSpells[ctSpellId] then
      -- DoT/HoT tick from a spell we cast within the last 30s
      local castTime = recentPeriodicSpells[ctSpellId]
      if (GetTime() - castTime) < 30 then
        attributed = true
      end
    end
  else
    -- No spell ID available, try consuming any pending cast
    local match = self:ConsumeBestCast(nil)
    if match then
      attributed = true
    end
  end

  if not attributed then return end

  -- Get the amount (may be secret)
  local safeAmount = amount
  if not safeAmount then return end

  self:Emit(eventType, safeAmount, 1, isCrit)
end

function Events:OnEnable()
  self:UpdateInstanceState()

  -- UNIT_COMBAT handles both incoming (player) and secondary outgoing (target)
  self:RegisterEvent("UNIT_COMBAT", "OnUnitCombat")

  -- Outgoing: cast queue + COMBAT_TEXT_UPDATE correlation
  self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellcastSucceeded")
  self:RegisterEvent("COMBAT_TEXT_UPDATE", "OnCombatTextUpdate")

  -- Instance state tracking
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateInstanceState")
  self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "UpdateInstanceState")

  -- Periodic cleanup (cast queue + stale periodic spell entries)
  self.cleanupTicker = C_Timer.NewTicker(5, function()
    self:CleanCastQueue()
    -- Clean stale periodic spell entries (older than 30s)
    local now = GetTime()
    for spellId, timestamp in pairs(recentPeriodicSpells) do
      if (now - timestamp) > 30 then
        recentPeriodicSpells[spellId] = nil
      end
    end
  end)
end

function Events:OnDisable()
  if self.cleanupTicker then
    self.cleanupTicker:Cancel()
    self.cleanupTicker = nil
  end
end
