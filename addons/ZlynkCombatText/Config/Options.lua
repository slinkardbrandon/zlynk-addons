local _, ns = ...

local LSM = LibStub("LibSharedMedia-3.0", true)

local fontFlagValues = {
  ["OUTLINE"] = "Outline",
  ["THICKOUTLINE"] = "Thick Outline",
  ["MONOCHROME"] = "Monochrome",
  [""] = "None",
}

local function GetOptions()
  return {
    name = "Zlynk Combat Text",
    type = "group",
    childGroups = "tab",
    args = {
      general = {
        name = "General",
        type = "group",
        order = 1,
        args = {
          enabled = {
            name = "Enable",
            desc = "Enable or disable the addon",
            type = "toggle",
            order = 1,
            width = "full",
            get = function() return ns.db.profile.enabled end,
            set = function(_, val)
              ns.db.profile.enabled = val
            end,
          },
          header_font = {
            name = "Font",
            type = "header",
            order = 10,
          },
          fontName = {
            name = "Font Face",
            desc = "The font used for combat text",
            type = "select",
            order = 11,
            dialogControl = LSM and "LSM30_Font" or nil,
            values = LSM and LSM:HashTable("font") or {},
            get = function() return ns.db.profile.font.name end,
            set = function(_, val)
              ns.db.profile.font.name = val
            end,
          },
          fontSize = {
            name = "Font Size",
            type = "range",
            order = 12,
            min = 12,
            max = 48,
            step = 1,
            get = function() return ns.db.profile.font.size end,
            set = function(_, val)
              ns.db.profile.font.size = val
            end,
          },
          fontFlags = {
            name = "Font Outline",
            type = "select",
            order = 13,
            values = fontFlagValues,
            get = function() return ns.db.profile.font.flags end,
            set = function(_, val)
              ns.db.profile.font.flags = val
            end,
          },
          header_anim = {
            name = "Animation",
            type = "header",
            order = 20,
          },
          animDuration = {
            name = "Duration",
            desc = "How long combat text stays visible (seconds)",
            type = "range",
            order = 21,
            min = 0.5,
            max = 4.0,
            step = 0.1,
            get = function() return ns.db.profile.animation.duration end,
            set = function(_, val)
              ns.db.profile.animation.duration = val
            end,
          },
          animDistance = {
            name = "Float Distance",
            desc = "How far combat text floats upward (pixels)",
            type = "range",
            order = 22,
            min = 20,
            max = 200,
            step = 5,
            get = function() return ns.db.profile.animation.distance end,
            set = function(_, val)
              ns.db.profile.animation.distance = val
            end,
          },
          critScale = {
            name = "Critical Scale",
            desc = "Size multiplier for critical hits",
            type = "range",
            order = 23,
            min = 1.0,
            max = 3.0,
            step = 0.1,
            get = function() return ns.db.profile.animation.critScale end,
            set = function(_, val)
              ns.db.profile.animation.critScale = val
            end,
          },
        },
      },
      directions = {
        name = "Directions",
        type = "group",
        order = 2,
        args = {
          desc = {
            name = "Choose which combat text categories to display.",
            type = "description",
            order = 0,
          },
          header_outgoing = {
            name = "Outgoing",
            type = "header",
            order = 1,
          },
          outDamage = {
            name = "Outgoing Damage",
            desc = "Show damage you deal",
            type = "toggle",
            order = 2,
            width = "full",
            get = function() return ns.db.profile.outgoing.damage end,
            set = function(_, val)
              ns.db.profile.outgoing.damage = val
            end,
          },
          outHealing = {
            name = "Outgoing Healing",
            desc = "Show healing you do",
            type = "toggle",
            order = 3,
            width = "full",
            get = function() return ns.db.profile.outgoing.healing end,
            set = function(_, val)
              ns.db.profile.outgoing.healing = val
            end,
          },
          header_incoming = {
            name = "Incoming",
            type = "header",
            order = 10,
          },
          incDamage = {
            name = "Incoming Damage",
            desc = "Show damage you take",
            type = "toggle",
            order = 11,
            width = "full",
            get = function() return ns.db.profile.incoming.damage end,
            set = function(_, val)
              ns.db.profile.incoming.damage = val
            end,
          },
          incHealing = {
            name = "Incoming Healing",
            desc = "Show healing you receive",
            type = "toggle",
            order = 12,
            width = "full",
            get = function() return ns.db.profile.incoming.healing end,
            set = function(_, val)
              ns.db.profile.incoming.healing = val
            end,
          },
        },
      },
      colors = {
        name = "Colors",
        type = "group",
        order = 3,
        args = {
          header_outgoing = {
            name = "Outgoing",
            type = "header",
            order = 1,
          },
          outgoingDamage = {
            name = "Damage",
            type = "color",
            order = 2,
            hasAlpha = true,
            get = function()
              local c = ns.db.profile.colors.outgoingDamage
              return c[1], c[2], c[3], c[4]
            end,
            set = function(_, r, g, b, a)
              ns.db.profile.colors.outgoingDamage = { r, g, b, a }
            end,
          },
          outgoingCrit = {
            name = "Damage (Critical)",
            type = "color",
            order = 3,
            hasAlpha = true,
            get = function()
              local c = ns.db.profile.colors.outgoingCrit
              return c[1], c[2], c[3], c[4]
            end,
            set = function(_, r, g, b, a)
              ns.db.profile.colors.outgoingCrit = { r, g, b, a }
            end,
          },
          outgoingHealing = {
            name = "Healing",
            type = "color",
            order = 4,
            hasAlpha = true,
            get = function()
              local c = ns.db.profile.colors.outgoingHealing
              return c[1], c[2], c[3], c[4]
            end,
            set = function(_, r, g, b, a)
              ns.db.profile.colors.outgoingHealing = { r, g, b, a }
            end,
          },
          outgoingHealCrit = {
            name = "Healing (Critical)",
            type = "color",
            order = 5,
            hasAlpha = true,
            get = function()
              local c = ns.db.profile.colors.outgoingHealCrit
              return c[1], c[2], c[3], c[4]
            end,
            set = function(_, r, g, b, a)
              ns.db.profile.colors.outgoingHealCrit = { r, g, b, a }
            end,
          },
          header_incoming = {
            name = "Incoming",
            type = "header",
            order = 10,
          },
          incomingDamage = {
            name = "Damage",
            type = "color",
            order = 11,
            hasAlpha = true,
            get = function()
              local c = ns.db.profile.colors.incomingDamage
              return c[1], c[2], c[3], c[4]
            end,
            set = function(_, r, g, b, a)
              ns.db.profile.colors.incomingDamage = { r, g, b, a }
            end,
          },
          incomingCrit = {
            name = "Damage (Critical)",
            type = "color",
            order = 12,
            hasAlpha = true,
            get = function()
              local c = ns.db.profile.colors.incomingCrit
              return c[1], c[2], c[3], c[4]
            end,
            set = function(_, r, g, b, a)
              ns.db.profile.colors.incomingCrit = { r, g, b, a }
            end,
          },
          incomingHealing = {
            name = "Healing",
            type = "color",
            order = 13,
            hasAlpha = true,
            get = function()
              local c = ns.db.profile.colors.incomingHealing
              return c[1], c[2], c[3], c[4]
            end,
            set = function(_, r, g, b, a)
              ns.db.profile.colors.incomingHealing = { r, g, b, a }
            end,
          },
          incomingHealCrit = {
            name = "Healing (Critical)",
            type = "color",
            order = 14,
            hasAlpha = true,
            get = function()
              local c = ns.db.profile.colors.incomingHealCrit
              return c[1], c[2], c[3], c[4]
            end,
            set = function(_, r, g, b, a)
              ns.db.profile.colors.incomingHealCrit = { r, g, b, a }
            end,
          },
        },
      },
      filters = {
        name = "Filters",
        type = "group",
        order = 4,
        args = {
          desc = {
            name = "Filter out low-value combat text and suppress in specific content.",
            type = "description",
            order = 0,
          },
          header_threshold = {
            name = "Thresholds",
            type = "header",
            order = 1,
          },
          minDamage = {
            name = "Minimum Damage",
            desc = "Hide damage numbers below this value",
            type = "range",
            order = 2,
            min = 0,
            max = 10000,
            softMax = 5000,
            step = 50,
            bigStep = 100,
            get = function() return ns.db.profile.filters.minDamage end,
            set = function(_, val)
              ns.db.profile.filters.minDamage = val
            end,
          },
          minHealing = {
            name = "Minimum Healing",
            desc = "Hide healing numbers below this value",
            type = "range",
            order = 3,
            min = 0,
            max = 10000,
            softMax = 5000,
            step = 50,
            bigStep = 100,
            get = function() return ns.db.profile.filters.minHealing end,
            set = function(_, val)
              ns.db.profile.filters.minHealing = val
            end,
          },
          header_content = {
            name = "Content Suppression",
            type = "header",
            order = 10,
          },
          suppressArena = {
            name = "Hide in Arena",
            desc = "Suppress all combat text while in arena",
            type = "toggle",
            order = 11,
            width = "full",
            get = function() return ns.db.profile.filters.suppressArena end,
            set = function(_, val)
              ns.db.profile.filters.suppressArena = val
            end,
          },
          suppressBG = {
            name = "Hide in Battlegrounds",
            desc = "Suppress all combat text while in battlegrounds",
            type = "toggle",
            order = 12,
            width = "full",
            get = function() return ns.db.profile.filters.suppressBG end,
            set = function(_, val)
              ns.db.profile.filters.suppressBG = val
            end,
          },
        },
      },
      profiles = "nil", -- placeholder, set in RegisterOptions
    },
  }
end

function ns.RegisterOptions(addon)
  local options = GetOptions()
  options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(addon.db)
  options.args.importExport = ns.GetImportExportOptions()

  LibStub("AceConfig-3.0"):RegisterOptionsTable("ZlynkCombatText", options)
  LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ZlynkCombatText", "Zlynk Combat Text")
end
