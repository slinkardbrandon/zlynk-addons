std = "lua51"
max_line_length = 100
codes = true

globals = {
  "SlashCmdList",
  "SLASH_ZLYNK1",
  "SLASH_ZLYNK2",
}

read_globals = {
  -- WoW API
  "CreateFrame",
  "UIParent",
  "Settings",
  "C_Timer",
  "C_CVar",
  "GetTime",
  "UnitName",
  "UnitClass",
  "UnitPower",
  "UnitPowerMax",
  "GetSpellInfo",
  "CombatLogGetCurrentEventInfo",
  "COMBATLOG_OBJECT_AFFILIATION_MINE",
  "COMBATLOG_OBJECT_AFFILIATION_PARTY",
  "COMBATLOG_OBJECT_AFFILIATION_RAID",

  -- Ace3 / Libraries
  "LibStub",

  -- WoW Frames / Globals
  "DEFAULT_CHAT_FRAME",
  "GameFontNormal",
  "GameFontNormalLarge",
  "GameFontHighlight",
  "GameTooltip",
  "InterfaceOptionsFrame_OpenToCategory",

  -- WoW string globals
  "format",
  "tinsert",
  "tremove",
  "wipe",
  "strsplit",
  "strtrim",
  "strupper",
  "strlower",

  -- Blizzard templates
  "BackdropTemplateMixin",
}

exclude_files = {
  "libs/",
  "vendor/",
  "node_modules/",
}
