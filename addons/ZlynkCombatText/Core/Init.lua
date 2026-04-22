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
  if GetCVar and GetCVar("nameplateShowEnemies") == "0" then
    self:Print("|cffffcc00Tip:|r enemy nameplates are disabled, so damage numbers "
      .. "will fall back to your target frame. Enable with "
      .. "|cffffffff/console nameplateShowEnemies 1|r for nameplate-anchored text.")
  end
end

function Addon:SlashCommand(input)
  input = strtrim(input or "")

  local traceSub = input:match("^trace%s*(.-)$")
  local markLabel = input:match("^mark%s+(.+)$") or (input == "mark" and "" or nil)

  if input == "" or input == "config" or input == "options" then
    Settings.OpenToCategory(ns.optionsCategoryID)
  elseif input == "help" then
    self:Print("Commands:")
    self:Print("  /zlynk - Open settings")
    self:Print("  /zlynk toggle - Enable/disable")
    self:Print("  /zlynk reset - Reset to defaults")
    self:Print("  /zlynk diag - Diagnose anchor resolution for current target")
    self:Print("  /zlynk debug - Toggle live anchor resolution logging")
    self:Print("  /zlynk trace start|stop|clear|status|path - Raw event trace")
    self:Print("  /zlynk mark <label> - Insert a marker into the trace log")
    self:Print("  /zlynk help - Show this help")
  elseif traceSub then
    self:HandleTrace(traceSub)
  elseif markLabel then
    self:HandleMark(markLabel)
  elseif input == "toggle" then
    self.db.profile.enabled = not self.db.profile.enabled
    self:Print(self.db.profile.enabled and "Enabled" or "Disabled")
  elseif input == "reset" then
    self.db:ResetProfile()
    self:Print("Profile reset to defaults.")
  elseif input == "diag" then
    self:Print("--- Anchor diagnostics ---")
    local showEnemies = GetCVar and GetCVar("nameplateShowEnemies") or "?"
    self:Print(("  CVar nameplateShowEnemies = %s"):format(tostring(showEnemies)))
    for _, unitId in ipairs({ "target", "player", "pet", "pettarget" }) do
      local np = nil
      if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, frame = pcall(C_NamePlate.GetNamePlateForUnit, unitId)
        if ok and frame then np = frame end
      end
      local state
      if not np then
        state = "none"
      elseif np:IsShown() then
        state = np:IsVisible() and "shown+visible" or "shown-only"
      else
        state = "hidden"
      end
      local guidTail = "?"
      if UnitGUID then
        local okG, g = pcall(UnitGUID, unitId)
        if okG and type(g) == "string" and g ~= "" then guidTail = g:sub(-8) end
      end
      self:Print(("  %s: nameplate=%s guid=%s"):format(unitId, state, guidTail))
    end
    local activeCount = 0
    if C_NamePlate and C_NamePlate.GetNamePlates then
      local okP, plates = pcall(C_NamePlate.GetNamePlates)
      if okP and type(plates) == "table" then activeCount = #plates end
    end
    self:Print(("  Active plates: %d"):format(activeCount))
    self:Print(("  In group: %s"):format(
      tostring(type(IsInGroup) == "function" and IsInGroup() or false)
    ))
  elseif input == "debug" then
    ns.displayDebug = not ns.displayDebug
    self:Print("Anchor debug logging " .. (ns.displayDebug and "ON" or "OFF"))
  else
    self:Print("Unknown command. Type /zlynk help")
  end
end

function Addon:HandleMark(label)
  local log = self.db.global.traceLog
  if not log or not log.active then
    self:Print("No active trace. Start with |cffffffff/zlynk trace start|r first.")
    return
  end
  if #log.entries >= 2000 then
    self:Print("Trace log is full (2000 entries).")
    return
  end
  log.entries[#log.entries + 1] = {
    t = GetTime() - (log.startedAt or 0),
    e = "MARK",
    label = label == "" and "(unlabeled)" or label,
  }
  self:Print(("|cff00ff00Mark:|r %s"):format(label == "" and "(unlabeled)" or label))
end

function Addon:HandleTrace(sub)
  sub = strtrim(sub or "")

  if sub == "" or sub == "start" then
    self.db.global.traceLog = {
      active = true,
      startedAt = GetTime(),
      startedWhen = date("%Y-%m-%d %H:%M:%S"),
      entries = {},
    }
    self:Print("|cff00ff00Trace started.|r Play your test scenario, then run "
      .. "|cffffffff/zlynk trace stop|r and |cffffffff/reload|r.")
  elseif sub == "stop" then
    local log = self.db.global.traceLog
    if log then
      log.active = false
      log.stoppedAt = GetTime()
      local count = log.entries and #log.entries or 0
      self:Print(("|cffffcc00Trace stopped.|r %d entries captured."):format(count))
      self:Print("Run |cffffffff/reload|r to flush to disk, then check:")
      self:Print("  |cffaaaaaaWTF/Account/<ACCT>/SavedVariables/ZlynkCombatTextDB.lua|r")
      self:Print("  Look for |cffffffffZlynkCombatTextDB.global.traceLog.entries|r")
    else
      self:Print("No active trace.")
    end
  elseif sub == "clear" then
    self.db.global.traceLog = nil
    self:Print("Trace log cleared.")
  elseif sub == "status" then
    local log = self.db.global.traceLog
    if not log then
      self:Print("Trace: inactive, no log")
      return
    end
    local state = log.active and "|cff00ff00ACTIVE|r" or "|cffaaaaaastopped|r"
    local count = log.entries and #log.entries or 0
    self:Print(("Trace: %s, %d entries (started %s)"):format(
      state, count, log.startedWhen or "?"
    ))
  elseif sub == "path" then
    self:Print("Trace output after /reload is in:")
    self:Print("  |cffaaaaaaWTF/Account/<ACCT>/SavedVariables/ZlynkCombatTextDB.lua|r")
    self:Print("Look for |cffffffffZlynkCombatTextDB.global.traceLog|r in that file.")
  else
    self:Print("Usage: /zlynk trace start|stop|clear|status|path")
  end
end
