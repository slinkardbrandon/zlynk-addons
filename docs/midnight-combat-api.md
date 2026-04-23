# WoW 12.x (Midnight) Combat API Reference

## Overview

WoW Midnight (12.0, launched Feb 2026) removed the traditional combat log API and introduced "Secret Values." This document covers what's available for combat text addons post-Midnight.

## What Is Gone (Do NOT Use)

| API / Event | Status | Notes |
|-------------|--------|-------|
| `COMBAT_LOG_EVENT_UNFILTERED` | **Removed** | No longer provides actionable data to addon Lua |
| `COMBAT_LOG_EVENT` | **Removed** | Same as above |
| `CombatLogGetCurrentEventInfo()` | **Dead** | Returns nil / secret values |
| Inter-addon communication (LibComm, etc.) | **Blocked in instances** | Cannot share combat data between addons in M+/raids |

## Available Data Sources

### COMBAT_TEXT_UPDATE + C_CombatText.GetCurrentEventInfo()

**Primary source for outgoing damage.** Despite earlier reports of it being broken, ZSBT (the most actively maintained SCT addon) uses this as its main data source successfully.

- Returns `(rawArg1, rawArg2, rawArg3)` — rawArg2 is often a spell ID
- Values may be secret (userdata) or real numbers depending on context
- Appears to only fire for the local player's combat actions (safe for attribution)
- Must be paired with a pending cast queue (`UNIT_SPELLCAST_SUCCEEDED`) for spell matching

### UNIT_COMBAT

**Primary source for incoming damage. Secondary for outgoing.**

Arguments: `unitTarget, event, flagText, amount, schoolMask`

- `unitTarget`: The unit **receiving** the combat action (defender, not attacker)
- `event`: "WOUND" (damage), "HEAL", "BLOCK", "DODGE", "PARRY", "MISS", etc.
- `flagText`: "CRITICAL", "CRUSHING", "GLANCING", or ""
- `amount`: Damage/heal number (may be secret in restricted content)
- `schoolMask`: Bitmask (1=physical, 2=holy, 4=fire, 8=nature, 16=frost, 32=shadow, 64=arcane)

**Critical behavior:**
- Fires on the **defender** unit, not the attacker
- `UNIT_COMBAT("player")` → damage/heals the player receives from ANY source (reliable for incoming)
- `UNIT_COMBAT("target")` → ALL damage the target takes from ANY source (leaks other players' damage)
- **No source attribution** — no spell ID, no attacker identity
- Must re-register on `PLAYER_TARGET_CHANGED` when using "target" unit

### UNIT_SPELLCAST_SUCCEEDED

**Used to build a pending cast queue for correlation.**

- Fires when the player finishes a cast
- Provides spell ID and target
- Queue entries expire after ~0.85-1.0s
- Match against `COMBAT_TEXT_UPDATE` spell IDs or `UNIT_COMBAT` timing

### UNIT_HEALTH / UNIT_HEALTH_FREQUENT

**Weakest signal — health delta correlation.**

- Track `UnitHealth("target")` over time, correlate drops to recent casts
- Returns **secret values** in instanced content (M+, raids, boss fights) — cannot calculate deltas
- Only usable in solo/open-world content
- Requires dedup against other outgoing paths

### Chat Messages (Fallback)

- `CHAT_MSG_COMBAT_SELF_HITS`, `CHAT_MSG_SPELL_DAMAGE`, `CHAT_MSG_SPELL_PERIODIC_DAMAGE`, etc.
- Text parsing with regex patterns
- Last-resort fallback when other sources fail

### Instance / Content Detection (Fully Functional)

| API | Purpose |
|-----|---------|
| `GetInstanceInfo()` | Returns instance type ("arena", "pvp", "party", "raid", "none") |
| `IsActiveBattlefieldArena()` | True if in arena |
| `C_PvP.IsBattleground()` | True if in battleground |
| `IsInInstance()` | Generic instance check |

### Other Whitelisted APIs

| API | Status |
|-----|--------|
| `UnitHealthMax()` / `UnitPowerMax()` | Non-secret for player units |
| Player's own spellcasts / GCD | Whitelisted |
| Class secondary resources (Runes, Holy Power, Maelstrom, Soul Fragments) | Whitelisted |

## Secret Values System

"Secret values" are a Lua userdata type that replaced direct number returns for combat data.

**What you CAN do:**
- Pass directly to `FontString:SetText()` for display
- Pass to `C_CurveUtil.GetCurveValueAtPoint()` for threshold evaluation
- Store in indexed arrays for passthrough

**What you CANNOT do:**
- Compare (`if dmg > threshold` will error)
- Arithmetic (`dmg * 2` will error)
- Use as table keys
- Store in variables for conditional logic
- Convert to string with `tostring()`

### Detection

```lua
local function isSafeNumber(v)
  if type(v) ~= "number" then return false end
  local ok = pcall(function() return v + 0 end)
  return ok
end
```

### Threshold Filtering with Secret Values

Use `C_CurveUtil.GetCurveValueAtPoint()` with a step curve — evaluation happens engine-side, not in Lua:

```lua
local function passesThreshold(secretValue, threshold)
  local ok, result = pcall(function()
    return C_CurveUtil.GetCurveValueAtPoint(secretValue, {
      { x = 0, y = 0 },
      { x = threshold - 1, y = 0 },
      { x = threshold, y = 1 },
    })
  end)
  if ok and type(result) == "number" then
    return result >= 1
  end
  return true -- fallback: show everything
end
```

### Raw Pipe Pattern (Display Passthrough)

Store secret values by index, never touch them in Lua, pass directly to UI:

```lua
local rawPipe = {}

-- In event handler:
rawPipe[nextId] = rawSecretValue

-- In display layer:
local raw = rawPipe[event.rawPipeId]
if isSafeNumber(raw) then
  fontString:SetText(formatNumber(raw))
else
  fontString:SetText(raw) -- secret value passthrough
end
rawPipe[event.rawPipeId] = nil
```

## Scope of Restrictions

| Content | Restriction Level | Notes |
|---------|------------------|-------|
| Open world / solo | Relaxed | UNIT_COMBAT amounts are real numbers, UNIT_HEALTH readable |
| Dungeons (non-M+) | Moderate | Some values secret |
| Mythic+ | Full | Health values secret, strict attribution required |
| Raids / Boss encounters | Full | Same as M+ |
| Arena / BGs | Full | Same as M+ |

## Proven Architecture (Based on ZSBT v1.1.9)

The most successful approach in the current API landscape:

1. **`COMBAT_TEXT_UPDATE`** as primary outgoing source, matched against pending cast queue
2. **`UNIT_COMBAT("player")`** as reliable incoming source
3. **`UNIT_COMBAT("target")`** as secondary outgoing, with strict cast correlation (disabled in group instances)
4. **`UNIT_HEALTH` delta correlation** as weakest outgoing signal (disabled in instances)
5. **Chat message parsing** as last-resort fallback
6. **Instance-aware restriction** — tighten attribution in group content, relax in solo
7. **pcall wrapping** on all combat value access
8. **Raw pipe pattern** for secret value display passthrough
9. **C_CurveUtil step curves** for threshold filtering on secret values

## Reference Addons

| Addon | Approach | Status (Apr 2026) |
|-------|----------|-------------------|
| ZSBT (Zore's) | Multi-signal correlation, no CLEU | Active (updated Apr 19) |
| MSBT Midnight (MrGank) | UNIT_COMBAT, accepts group leak | Active (updated Apr 16) |
| MidnightBattleText (SheaGlass) | CLEU sourceFlags + dedup | Stale (last update Mar 19) |
