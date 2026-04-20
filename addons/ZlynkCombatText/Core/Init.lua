local addonName, ns = ...

local Addon = LibStub("AceAddon-3.0"):NewAddon(
  addonName,
  "AceConsole-3.0",
  "AceEvent-3.0"
)
ns.Addon = Addon
ns.addonName = addonName

function Addon:OnInitialize()
  -- Initialize saved variables database
  self.db = LibStub("AceDB-3.0"):New("ZlynkCombatTextDB", ns.defaults, true)
  ns.db = self.db

  -- Register options table
  ns.RegisterOptions(self)

  -- Register slash commands
  self:RegisterChatCommand("zlynk", "SlashCommand")
  self:RegisterChatCommand("zct", "SlashCommand")
end

function Addon:OnEnable()
  self:Print("loaded. Type /zlynk for settings.")
end

function Addon:SlashCommand(input)
  input = strtrim(input or "")

  if input == "" or input == "config" or input == "options" then
    Settings.OpenToCategory("Zlynk Combat Text")
  elseif input == "help" then
    self:Print("Commands:")
    self:Print("  /zlynk - Open settings")
    self:Print("  /zlynk toggle - Enable/disable")
    self:Print("  /zlynk reset - Reset to defaults")
    self:Print("  /zlynk help - Show this help")
  elseif input == "toggle" then
    self.db.profile.enabled = not self.db.profile.enabled
    self:Print(self.db.profile.enabled and "Enabled" or "Disabled")
  elseif input == "reset" then
    self.db:ResetProfile()
    self:Print("Profile reset to defaults.")
  else
    self:Print("Unknown command. Type /zlynk help")
  end
end
