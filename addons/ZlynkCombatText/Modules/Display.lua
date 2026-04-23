local _, ns = ...

local Addon = ns.Addon
local Display = Addon:NewModule("Display", "AceEvent-3.0")

-- TODO: healing display. Currently damage-only.

-- ============================================================================
-- Frame pool + state
-- ============================================================================

local framePool = {}
local poolSize = 0

-- Active floats keyed by "<anchorGUID>|<spellId>" for spell merging.
local activeBySpell = {}

-- Count of concurrent floats per anchor GUID for the soft cap.
local activeCountByGUID = {}

-- ============================================================================
-- Color + anchor resolution
-- ============================================================================

local function GetEventColor(event)
  local colors = ns.db.profile.colors
  local t = event.type
  local isCrit = event.isCrit

  if t == ns.EVENT_TYPE.OUTGOING_DAMAGE then
    return isCrit and colors.outgoingCrit or colors.outgoingDamage
  elseif t == ns.EVENT_TYPE.INCOMING_DAMAGE then
    return isCrit and colors.incomingCrit or colors.incomingDamage
  elseif t == ns.EVENT_TYPE.PET_DAMAGE then
    return isCrit and colors.petCrit or colors.petDamage
  elseif t == ns.EVENT_TYPE.PET_INCOMING_DAMAGE then
    return colors.petIncomingDamage
  end
  return { 1, 1, 1, 1 }
end

-- The anchorUnit on the event is a live unit token ("nameplate12", "player",
-- "pet") that resolves directly. No GUID index, no rescan, no fallback chain.
-- If the plate has already hidden by the time we render, we drop the event.
local function ResolveAnchor(event)
  local unitId = event.anchorUnit
  if not unitId then return nil end

  if unitId == "player" then
    if _G.PlayerFrame and _G.PlayerFrame:IsVisible() then
      return _G.PlayerFrame
    end
    return nil
  end

  if unitId == "pet" then
    if _G.PetFrame and _G.PetFrame:IsVisible() then
      return _G.PetFrame
    end
    return nil
  end

  -- nameplateN
  if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
    local ok, np = pcall(C_NamePlate.GetNamePlateForUnit, unitId)
    if ok and np and np:IsShown() then
      return np
    end
  end
  return nil
end

-- ============================================================================
-- Frame construction
-- ============================================================================

local function CreateCombatTextFrame()
  local frame = CreateFrame("Frame", nil, UIParent)
  frame:SetSize(220, 48)
  frame:SetFrameStrata("HIGH")

  local fs = frame:CreateFontString(nil, "OVERLAY")
  fs:SetPoint("CENTER")
  fs:SetJustifyH("CENTER")
  frame.text = fs

  local ag = frame:CreateAnimationGroup()
  frame.animGroup = ag

  local translate = ag:CreateAnimation("Translation")
  translate:SetOrder(1)
  frame.translateAnim = translate

  local alpha = ag:CreateAnimation("Alpha")
  alpha:SetOrder(1)
  alpha:SetFromAlpha(1)
  alpha:SetToAlpha(0)
  frame.alphaAnim = alpha

  -- Crit "punch" — fast scale up, then scale back down to a settled size.
  local scaleUp = ag:CreateAnimation("Scale")
  scaleUp:SetOrder(1)
  scaleUp:SetDuration(0.12)
  frame.scaleUpAnim = scaleUp

  local scaleDown = ag:CreateAnimation("Scale")
  scaleDown:SetOrder(2)
  scaleDown:SetDuration(0.15)
  frame.scaleDownAnim = scaleDown

  ag:SetScript("OnFinished", function()
    frame:Hide()
    frame.inUse = false
    if frame.spellKey and activeBySpell[frame.spellKey] == frame then
      activeBySpell[frame.spellKey] = nil
    end
    if frame.anchorGUID and activeCountByGUID[frame.anchorGUID] then
      activeCountByGUID[frame.anchorGUID] =
        math.max(0, activeCountByGUID[frame.anchorGUID] - 1)
    end
    if frame.rawPipeId then
      ns.rawPipe[frame.rawPipeId] = nil
      frame.rawPipeId = nil
    end
    frame.spellKey = nil
    frame.anchorGUID = nil
  end)

  return frame
end

local function AcquireFrame()
  for i = 1, poolSize do
    if not framePool[i].inUse then
      framePool[i].inUse = true
      return framePool[i]
    end
  end
  poolSize = poolSize + 1
  local frame = CreateCombatTextFrame()
  frame.inUse = true
  framePool[poolSize] = frame
  return frame
end

-- ============================================================================
-- Styling + layout
-- ============================================================================

local function ResolveFont()
  local font = ns.db.profile.font
  local path = font.name
  if LibStub and LibStub("LibSharedMedia-3.0", true) then
    local LSM = LibStub("LibSharedMedia-3.0")
    path = LSM:Fetch("font", font.name) or path
  end
  return path, font.size, font.flags
end

local function SetFrameAmount(frame, rawValue)
  if ns.isSafeNumber(rawValue) then
    frame.text:SetText(ns.formatNumber(rawValue))
  else
    local ok = pcall(function() frame.text:SetText(rawValue) end)
    if not ok then frame.text:SetText("?") end
  end
end

local function StyleFrame(frame, event)
  local color = GetEventColor(event)
  frame.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

  local fontPath, size, flags = ResolveFont()
  local scale = event.isCrit and 1.15 or 1.0
  frame.text:SetFont(fontPath, size * scale, flags)
end

local function IsIncoming(event)
  return event.type == ns.EVENT_TYPE.INCOMING_DAMAGE
    or event.type == ns.EVENT_TYPE.PET_INCOMING_DAMAGE
end

local function PlayFrame(frame, event, anchorFrame)
  local anim = ns.db.profile.animation
  local duration = anim.duration or 1.5
  local spreadX = anim.spreadX or 40

  local ox = math.random(-spreadX, spreadX)
  local oy = 30 + math.random(0, 12)
  if IsIncoming(event) then oy = -oy end

  frame:ClearAllPoints()
  frame:SetPoint("CENTER", anchorFrame, "CENTER", ox, oy)

  -- Slight angle variation on the drift so clustered hits fan out.
  local driftX = math.random(-18, 18)
  local driftY = IsIncoming(event) and -(anim.distance or 80) or (anim.distance or 80)
  frame.translateAnim:SetOffset(driftX, driftY)
  frame.translateAnim:SetDuration(duration)

  frame.alphaAnim:SetStartDelay(duration * 0.55)
  frame.alphaAnim:SetDuration(duration * 0.45)

  if event.isCrit then
    local punch = anim.critScale or 1.8
    frame.scaleUpAnim:SetScaleFrom(1, 1)
    frame.scaleUpAnim:SetScaleTo(punch, punch)
    frame.scaleDownAnim:SetScaleFrom(punch, punch)
    frame.scaleDownAnim:SetScaleTo(1.2, 1.2)
  else
    frame.scaleUpAnim:SetScaleFrom(1, 1)
    frame.scaleUpAnim:SetScaleTo(1, 1)
    frame.scaleDownAnim:SetScaleFrom(1, 1)
    frame.scaleDownAnim:SetScaleTo(1, 1)
  end

  frame:SetAlpha(1)
  frame:Show()
  frame.animGroup:Stop()
  frame.animGroup:Play()
end

-- ============================================================================
-- Merging + overflow
-- ============================================================================

local function TryMerge(event)
  local cfg = ns.db.profile.merging
  if not cfg or not cfg.enabled then return false end
  if not event.spellId or not event.anchorGUID then return false end

  local key = event.anchorGUID .. "|" .. tostring(event.spellId)
  local existing = activeBySpell[key]
  if not existing or not existing.inUse then return false end

  local now = GetTime()
  if (now - (existing.spawnedAt or 0)) > (cfg.window or 0.3) then return false end

  local existingRaw = ns.rawPipe[existing.rawPipeId]
  local incomingRaw = ns.rawPipe[event.rawPipeId]
  if not ns.isSafeNumber(existingRaw) or not ns.isSafeNumber(incomingRaw) then
    return false  -- can't merge secret values
  end

  local combined = existingRaw + incomingRaw
  ns.rawPipe[existing.rawPipeId] = combined
  existing.text:SetText(ns.formatNumber(combined))

  existing.text:SetTextScale(1.05)
  C_Timer.After(0.06, function()
    if existing.inUse then existing.text:SetTextScale(1.0) end
  end)

  ns.rawPipe[event.rawPipeId] = nil
  return true
end

local function OverflowHandle(event)
  local cfg = ns.db.profile.merging
  if not cfg or not cfg.enabled then return false end
  local cap = cfg.maxPerAnchor or 5
  if (activeCountByGUID[event.anchorGUID] or 0) < cap then return false end

  local newest, newestTime
  for i = 1, poolSize do
    local f = framePool[i]
    if f.inUse and f.anchorGUID == event.anchorGUID then
      if not newestTime or (f.spawnedAt or 0) > newestTime then
        newest = f
        newestTime = f.spawnedAt or 0
      end
    end
  end
  if not newest then return false end

  local existingRaw = ns.rawPipe[newest.rawPipeId]
  local incomingRaw = ns.rawPipe[event.rawPipeId]
  if ns.isSafeNumber(existingRaw) and ns.isSafeNumber(incomingRaw) then
    local combined = existingRaw + incomingRaw
    ns.rawPipe[newest.rawPipeId] = combined
    newest.text:SetText(ns.formatNumber(combined))
  end
  ns.rawPipe[event.rawPipeId] = nil
  return true
end

-- ============================================================================
-- Pipeline entry
-- ============================================================================

function Display:ShowCombatText(event)
  if TryMerge(event) then return end
  if OverflowHandle(event) then return end

  local anchorFrame = ResolveAnchor(event)
  if not anchorFrame then
    -- Nameplate gone between emit and render, or unit frame hidden. Drop.
    ns.rawPipe[event.rawPipeId] = nil
    return
  end

  local frame = AcquireFrame()

  frame.anchorGUID = event.anchorGUID
  frame.spawnedAt = GetTime()
  frame.rawPipeId = event.rawPipeId

  if event.spellId and event.anchorGUID then
    frame.spellKey = event.anchorGUID .. "|" .. tostring(event.spellId)
    activeBySpell[frame.spellKey] = frame
  else
    frame.spellKey = nil
  end

  if event.anchorGUID then
    activeCountByGUID[event.anchorGUID] =
      (activeCountByGUID[event.anchorGUID] or 0) + 1
  end

  StyleFrame(frame, event)
  SetFrameAmount(frame, ns.rawPipe[event.rawPipeId])
  PlayFrame(frame, event, anchorFrame)
end

function Display:OnCombatEvent(_, event)
  if ns.displayDebug then
    Addon:Print(("debug: type=%s unit=%s guid=%s school=%s crit=%s"):format(
      tostring(event.type),
      tostring(event.anchorUnit),
      tostring(event.anchorGUID and event.anchorGUID:sub(-8) or "?"),
      tostring(event.school),
      tostring(event.isCrit)
    ))
  end
  self:ShowCombatText(event)
end

function Display:OnEnable()
  for _ = 1, 24 do
    poolSize = poolSize + 1
    framePool[poolSize] = CreateCombatTextFrame()
  end
  self:RegisterMessage("ZCT_COMBAT_EVENT", "OnCombatEvent")
end

function Display:OnDisable()
  self:UnregisterMessage("ZCT_COMBAT_EVENT")
  for _, frame in ipairs(framePool) do
    frame:Hide()
    frame.inUse = false
  end
  activeBySpell = {}
  activeCountByGUID = {}
end
