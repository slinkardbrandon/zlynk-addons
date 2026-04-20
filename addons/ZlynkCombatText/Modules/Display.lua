local _, ns = ...

local Addon = ns.Addon
local Display = Addon:NewModule("Display", "AceEvent-3.0")

-- Frame pool
local framePool = {}
local poolSize = 0

-- Vertical offset tracking to avoid overlap
local lastSpawnY = 0
local lastSpawnTime = 0
local SPAWN_OFFSET = 18  -- pixels between concurrent texts

-- Get color for an event
local function GetEventColor(event)
  local colors = ns.db.profile.colors
  local eventType = event.type
  local isCrit = event.isCrit

  if eventType == ns.EVENT_TYPE.OUTGOING_DAMAGE then
    return isCrit and colors.outgoingCrit or colors.outgoingDamage
  elseif eventType == ns.EVENT_TYPE.OUTGOING_HEAL then
    return isCrit and colors.outgoingHealCrit or colors.outgoingHealing
  elseif eventType == ns.EVENT_TYPE.INCOMING_DAMAGE then
    return isCrit and colors.incomingCrit or colors.incomingDamage
  elseif eventType == ns.EVENT_TYPE.INCOMING_HEAL then
    return isCrit and colors.incomingHealCrit or colors.incomingHealing
  end

  return { 1, 1, 1, 1 }
end

-- Create a new combat text frame
local function CreateCombatTextFrame()
  local frame = CreateFrame("Frame", nil, UIParent)
  frame:SetSize(200, 40)
  frame:SetFrameStrata("HIGH")

  local fs = frame:CreateFontString(nil, "OVERLAY")
  fs:SetPoint("CENTER")
  fs:SetJustifyH("CENTER")
  frame.text = fs

  -- Animation group
  local ag = frame:CreateAnimationGroup()
  frame.animGroup = ag

  -- Translation (float upward)
  local translate = ag:CreateAnimation("Translation")
  translate:SetOrder(1)
  frame.translateAnim = translate

  -- Alpha (fade out)
  local alpha = ag:CreateAnimation("Alpha")
  alpha:SetOrder(1)
  alpha:SetFromAlpha(1)
  alpha:SetToAlpha(0)
  frame.alphaAnim = alpha

  -- Scale for crits
  local scaleUp = ag:CreateAnimation("Scale")
  scaleUp:SetOrder(1)
  scaleUp:SetDuration(0.1)
  scaleUp:SetScaleFrom(1, 1)
  frame.scaleAnim = scaleUp

  local scaleDown = ag:CreateAnimation("Scale")
  scaleDown:SetOrder(2)
  scaleDown:SetDuration(0.1)
  scaleDown:SetScaleFrom(1, 1)
  scaleDown:SetScaleTo(1, 1)
  frame.scaleDownAnim = scaleDown

  ag:SetScript("OnFinished", function()
    frame:Hide()
    frame.inUse = false
    -- Clean up raw pipe slot
    if frame.rawPipeId then
      ns.rawPipe[frame.rawPipeId] = nil
      frame.rawPipeId = nil
    end
  end)

  return frame
end

-- Acquire a frame from the pool
local function AcquireFrame()
  -- Look for a free frame
  for i = 1, poolSize do
    if not framePool[i].inUse then
      framePool[i].inUse = true
      return framePool[i]
    end
  end

  -- Pool exhausted, create a new one
  poolSize = poolSize + 1
  local frame = CreateCombatTextFrame()
  frame.inUse = true
  framePool[poolSize] = frame
  return frame
end

-- Calculate spawn position with Y offset to avoid overlap
local function GetSpawnPosition(event)
  local now = GetTime()
  local baseX, baseY

  -- Anchor relative to screen center (near character)
  -- Outgoing: right side, Incoming: left side
  if event.type == ns.EVENT_TYPE.OUTGOING_DAMAGE or event.type == ns.EVENT_TYPE.OUTGOING_HEAL then
    baseX = 80 + math.random(-15, 15)
  else
    baseX = -80 + math.random(-15, 15)
  end
  baseY = 50

  -- Offset if spawning rapidly to avoid overlap
  if (now - lastSpawnTime) < 0.15 then
    lastSpawnY = lastSpawnY + SPAWN_OFFSET
  else
    lastSpawnY = 0
  end
  lastSpawnTime = now

  return baseX, baseY + lastSpawnY
end

-- Display a combat event
function Display:ShowCombatText(event)
  local frame = AcquireFrame()
  local profile = ns.db.profile
  local font = profile.font
  local anim = profile.animation

  -- Set font
  local fontPath = font.name
  -- If using LSM, resolve the font path
  if LibStub and LibStub("LibSharedMedia-3.0", true) then
    local LSM = LibStub("LibSharedMedia-3.0")
    fontPath = LSM:Fetch("font", font.name) or font.name
  end
  frame.text:SetFont(fontPath, font.size, font.flags)

  -- Set text from raw pipe
  local raw = ns.rawPipe[event.rawPipeId]
  frame.rawPipeId = event.rawPipeId
  if ns.isSafeNumber(raw) then
    frame.text:SetText(ns.formatNumber(raw))
  else
    -- Secret value passthrough or pcall-wrapped SetText
    local ok = pcall(function() frame.text:SetText(raw) end)
    if not ok then
      frame.text:SetText("?")
    end
  end

  -- Set color
  local color = GetEventColor(event)
  frame.text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

  -- Position
  local x, y = GetSpawnPosition(event)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", x, y)

  -- Configure animations
  local duration = anim.duration
  frame.translateAnim:SetOffset(0, anim.distance)
  frame.translateAnim:SetDuration(duration)
  frame.alphaAnim:SetStartDelay(duration * 0.5)
  frame.alphaAnim:SetDuration(duration * 0.5)

  -- Crit scale punch
  if event.isCrit then
    local scale = anim.critScale
    frame.scaleAnim:SetScaleTo(scale, scale)
    frame.scaleAnim:SetDuration(0.1)
    frame.scaleDownAnim:SetScaleFrom(scale, scale)
    frame.scaleDownAnim:SetDuration(0.15)
    frame.text:SetFont(fontPath, font.size * 1.2, font.flags)
  else
    frame.scaleAnim:SetScaleTo(1, 1)
    frame.scaleDownAnim:SetScaleFrom(1, 1)
  end

  -- Show and play
  frame:SetAlpha(1)
  frame:Show()
  frame.animGroup:Stop()
  frame.animGroup:Play()
end

function Display:OnCombatEvent(_, event)
  self:ShowCombatText(event)
end

function Display:OnEnable()
  -- Pre-create frame pool
  for _ = 1, 20 do
    poolSize = poolSize + 1
    framePool[poolSize] = CreateCombatTextFrame()
  end

  -- Listen for combat events from the Events module
  self:RegisterMessage("ZCT_COMBAT_EVENT", "OnCombatEvent")
end

function Display:OnDisable()
  self:UnregisterMessage("ZCT_COMBAT_EVENT")
  -- Hide all active frames
  for _, frame in ipairs(framePool) do
    frame:Hide()
    frame.inUse = false
  end
end
