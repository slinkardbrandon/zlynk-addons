local _, ns = ...

-- Profile import/export using LibSerialize + LibDeflate
-- Produces a compact base64 string that can be shared between machines

local EXPORT_PREFIX = "ZCT1"  -- version prefix for string validation

local function GetLibs()
  local LibSerialize = LibStub("LibSerialize", true)
  local LibDeflate = LibStub("LibDeflate", true)
  if not LibSerialize or not LibDeflate then
    return nil, nil
  end
  return LibSerialize, LibDeflate
end

function ns.ExportProfile()
  local LibSerialize, LibDeflate = GetLibs()
  if not LibSerialize or not LibDeflate then
    return nil, "Required libraries not loaded (LibSerialize, LibDeflate)"
  end

  local profileData = ns.db.profile
  local serialized = LibSerialize:Serialize(profileData)
  local compressed = LibDeflate:CompressDeflate(serialized)
  local encoded = LibDeflate:EncodeForPrint(compressed)

  return EXPORT_PREFIX .. encoded, nil
end

function ns.ImportProfile(importString)
  local LibSerialize, LibDeflate = GetLibs()
  if not LibSerialize or not LibDeflate then
    return false, "Required libraries not loaded (LibSerialize, LibDeflate)"
  end

  if not importString or importString == "" then
    return false, "Import string is empty"
  end

  -- Validate prefix
  local prefix = importString:sub(1, #EXPORT_PREFIX)
  if prefix ~= EXPORT_PREFIX then
    return false, "Invalid import string (unrecognized format)"
  end

  local encoded = importString:sub(#EXPORT_PREFIX + 1)
  local compressed = LibDeflate:DecodeForPrint(encoded)
  if not compressed then
    return false, "Failed to decode import string"
  end

  local serialized = LibDeflate:DecompressDeflate(compressed)
  if not serialized then
    return false, "Failed to decompress import data"
  end

  local success, profileData = LibSerialize:Deserialize(serialized)
  if not success or type(profileData) ~= "table" then
    return false, "Failed to deserialize profile data"
  end

  -- Apply imported data to current profile
  local profile = ns.db.profile
  for key, value in pairs(profileData) do
    if profile[key] ~= nil then
      profile[key] = value
    end
  end

  return true, nil
end

function ns.GetImportExportOptions()
  local importBuffer = ""

  return {
    name = "Import / Export",
    type = "group",
    order = 90,
    args = {
      header_export = {
        name = "Export",
        type = "header",
        order = 1,
      },
      exportDesc = {
        name = "Copy this string to share your profile settings.",
        type = "description",
        order = 2,
      },
      exportString = {
        name = "Export String",
        type = "input",
        order = 3,
        multiline = 6,
        width = "full",
        get = function()
          local str, err = ns.ExportProfile()
          if err then return "Error: " .. err end
          return str
        end,
        set = function() end,  -- read-only
      },
      header_import = {
        name = "Import",
        type = "header",
        order = 10,
      },
      importDesc = {
        name = "Paste an import string below and click Apply to load it.",
        type = "description",
        order = 11,
      },
      importString = {
        name = "Import String",
        type = "input",
        order = 12,
        multiline = 6,
        width = "full",
        get = function() return importBuffer end,
        set = function(_, val) importBuffer = val end,
      },
      importApply = {
        name = "Apply Import",
        type = "execute",
        order = 13,
        func = function()
          local success, err = ns.ImportProfile(importBuffer)
          if success then
            ns.Addon:Print("Profile imported successfully.")
            importBuffer = ""
          else
            ns.Addon:Print("Import failed: " .. (err or "unknown error"))
          end
        end,
      },
    },
  }
end
