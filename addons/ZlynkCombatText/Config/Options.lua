local _, ns = ...

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
          fontSize = {
            name = "Font Size",
            type = "range",
            order = 11,
            min = 12,
            max = 48,
            step = 1,
            get = function() return ns.db.profile.font.size end,
            set = function(_, val)
              ns.db.profile.font.size = val
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

  LibStub("AceConfig-3.0"):RegisterOptionsTable("ZlynkCombatText", options)
  LibStub("AceConfigDialog-3.0"):AddToBlizOptions("ZlynkCombatText", "Zlynk Combat Text")
end
