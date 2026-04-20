local _, ns = ...

-- Event type enum
ns.EVENT_TYPE = {
  OUTGOING_DAMAGE = 1,
  OUTGOING_HEAL = 2,
  INCOMING_DAMAGE = 3,
  INCOMING_HEAL = 4,
}

-- Damage school colors (schoolMask bit → RGBA)
ns.SCHOOL_COLORS = {
  [1] = { 1.0, 1.0, 0.0, 1 },     -- Physical (yellow)
  [2] = { 1.0, 0.9, 0.5, 1 },     -- Holy
  [4] = { 1.0, 0.5, 0.0, 1 },     -- Fire
  [8] = { 0.3, 1.0, 0.3, 1 },     -- Nature
  [16] = { 0.5, 0.5, 1.0, 1 },    -- Frost
  [32] = { 0.5, 0.0, 1.0, 1 },    -- Shadow
  [64] = { 1.0, 0.5, 1.0, 1 },    -- Arcane
}

-- Raw pipe: indexed storage for secret values that must pass through untouched
ns.rawPipe = {}
ns.rawPipeNextId = 1

function ns.allocRawPipe(value)
  local id = ns.rawPipeNextId
  ns.rawPipe[id] = value
  ns.rawPipeNextId = id + 1
  return id
end

-- Secret value detection
function ns.isSafeNumber(v)
  if type(v) ~= "number" then return false end
  local ok = pcall(function() return v + 0 end)
  return ok
end

-- Number formatting (abbreviate large numbers)
function ns.formatNumber(n)
  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  elseif n >= 1000 then
    return string.format("%.1fk", n / 1000)
  else
    return tostring(math.floor(n))
  end
end

-- Threshold check using C_CurveUtil (works on secret values)
function ns.passesThreshold(rawValue, threshold)
  if threshold <= 0 then return true end

  -- If we can read the value directly, just compare
  if ns.isSafeNumber(rawValue) then
    return rawValue >= threshold
  end

  -- Secret value: use C_CurveUtil step curve (engine-side evaluation)
  if C_CurveUtil and C_CurveUtil.GetCurveValueAtPoint then
    local ok, result = pcall(function()
      return C_CurveUtil.GetCurveValueAtPoint(rawValue, {
        { x = 0, y = 0 },
        { x = threshold - 1, y = 0 },
        { x = threshold, y = 1 },
      })
    end)
    if ok and type(result) == "number" then
      return result >= 1
    end
  end

  -- Fallback: show everything if we can't evaluate
  return true
end

-- Cast queue expiry time (seconds)
ns.CAST_QUEUE_EXPIRY = 0.85
