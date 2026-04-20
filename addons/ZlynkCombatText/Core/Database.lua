local _, ns = ...

ns.defaults = {
  profile = {
    enabled = true,
    font = {
      name = "Fonts\\FRIZQT__.TTF",
      size = 24,
      flags = "OUTLINE",
    },
    colors = {
      damage = { 1, 1, 1, 1 },
      healing = { 0.1, 1, 0.1, 1 },
      critical = { 1, 0.8, 0, 1 },
    },
    animation = {
      duration = 1.5,
      distance = 80,
      critScale = 1.5,
    },
    filters = {
      minDamage = 0,
      showPet = true,
      showDots = true,
      showHots = true,
    },
  },
}
