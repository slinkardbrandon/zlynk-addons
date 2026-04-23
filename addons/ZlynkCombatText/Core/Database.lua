local _, ns = ...

-- TODO: healing + shields + absorbs. Intentionally out of scope for now.
-- Damage-only until the attribution/display pipeline is solid.

ns.defaults = {
  global = {
    -- Diagnostic trace log. Populated by /zlynk trace start. Persists across
    -- reloads (saved to ZlynkCombatTextDB.lua) so the user can capture a
    -- session, /reload, and paste the results.
    traceLog = nil,
  },
  profile = {
    enabled = true,
    font = {
      name = "Friz Quadrata TT",
      size = 28,
      flags = "THICKOUTLINE",
    },
    outgoing = {
      damage = true,
      pet = true,
    },
    incoming = {
      damage = true,
      pet = true,
    },
    colors = {
      outgoingDamage = { 1, 1, 1, 1 },
      outgoingCrit = { 1, 0.85, 0, 1 },
      incomingDamage = { 1, 0.25, 0.25, 1 },
      incomingCrit = { 1, 0.05, 0.05, 1 },
      petDamage = { 1, 0.6, 0.15, 1 },
      petCrit = { 1, 0.75, 0.1, 1 },
      petIncomingDamage = { 0.9, 0.4, 0.4, 1 },
    },
    animation = {
      duration = 1.6,
      distance = 90,
      critScale = 1.8,
      spreadX = 40,
    },
    merging = {
      enabled = true,
      window = 0.3,
      maxPerAnchor = 5,
    },
    filters = {
      minDamage = 0,
      -- PvP instances default to suppressed. UNIT_COMBAT has no source
      -- attribution in Midnight, so heavy group content (arena + BG) leaks
      -- ally/enemy damage as yours. PvE content is fine; suppression is
      -- off by default there.
      suppressArena = true,
      suppressBG = true,
    },
  },
}
