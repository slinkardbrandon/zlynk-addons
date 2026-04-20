local _, ns = ...

ns.defaults = {
  profile = {
    enabled = true,
    font = {
      name = "Friz Quadrata TT",
      size = 24,
      flags = "OUTLINE",
    },
    outgoing = {
      damage = true,
      healing = true,
    },
    incoming = {
      damage = true,
      healing = true,
    },
    colors = {
      outgoingDamage = { 1, 1, 1, 1 },
      outgoingCrit = { 1, 0.8, 0, 1 },
      outgoingHealing = { 0.1, 1, 0.1, 1 },
      outgoingHealCrit = { 0.1, 1, 0.5, 1 },
      incomingDamage = { 1, 0.2, 0.2, 1 },
      incomingCrit = { 1, 0.0, 0.0, 1 },
      incomingHealing = { 0.1, 0.8, 0.1, 1 },
      incomingHealCrit = { 0.1, 1, 0.5, 1 },
    },
    animation = {
      duration = 1.5,
      distance = 80,
      critScale = 1.5,
    },
    filters = {
      minDamage = 0,
      minHealing = 0,
      suppressArena = false,
      suppressBG = false,
    },
  },
}
