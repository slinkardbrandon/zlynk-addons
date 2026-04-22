local _, ns = ...

-- TODO: healing + shields + absorbs. Damage-only for now; OUTGOING_HEAL /
-- INCOMING_HEAL types reserved for future work.

-- Event type enum
ns.EVENT_TYPE = {
  OUTGOING_DAMAGE = 1,
  INCOMING_DAMAGE = 3,
  PET_DAMAGE = 5,
  PET_INCOMING_DAMAGE = 6,
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

  if ns.isSafeNumber(rawValue) then
    return rawValue >= threshold
  end

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

-- Attribution window: if the player cast a spell within this window, a
-- subsequent damage event on an engaged nameplate is attributed to the player.
-- Longer for non-physical (projectile travel time).
ns.PLAYER_CAST_WINDOW_PHYSICAL = 0.7
ns.PLAYER_CAST_WINDOW_MAGIC = 2.5

-- Engagement timeouts (seconds). In solo content, we hold engagement long
-- enough to catch DoT ticks and long pet fights. In group content, we keep
-- it short to avoid attributing teammate damage to ourselves — UNIT_COMBAT
-- has no source attribution, so a wide window would leak ally hits.
ns.ENGAGEMENT_WINDOW_SOLO = 30.0
ns.ENGAGEMENT_WINDOW_GROUP = 2.5
