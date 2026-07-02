SmartMark = SmartMark or {}

SmartMark.VERSION = "0.1.0-alpha"

BINDING_HEADER_SMARTMARK = "SmartMark"
BINDING_NAME_SMARTMARK_CLEAR_MARKS = "Clear all marks"
BINDING_NAME_SMARTMARK_TOGGLE_SESSION = "Toggle marking session"

local addon = SmartMark
addon.modules = addon.modules or {}

local function ensureSavedVariables()
    SmartMarkDB = SmartMarkDB or {}
    SmartMarkCharDB = SmartMarkCharDB or {}
end

local function printMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99SmartMark|r: " .. msg)
end

addon.Print = printMsg

function SmartMark_ClearAllMarks()
    if addon.MarkManager then
        if addon.MarkManager:IsDeferredClearActive() then
            local extra = addon.MarkManager:CancelDeferredClearRetry()
            printMsg("Clear retry canceled (additional clears: " .. tostring(extra or 0) .. ")")
            return
        end

        local cleared = addon.MarkManager:ResetSession(true) or 0
        printMsg("Cleared marks: " .. tostring(cleared))
    end
end

function SmartMark_ToggleSession()
    if not addon.MarkManager then
        return
    end

    if addon.MarkManager.session and addon.MarkManager.session.active then
        addon.MarkManager:StopSession(true)
        printMsg("Session stopped")
    else
        addon.MarkManager:StartSession("toggle")
        printMsg("Session started")
    end
end

-- F-key quick-assign globals (invoked by Ctrl+Alt+F1–F8 keybindings).
-- Each binding remaps one priority type → its F-key's icon index.
local markIconNames = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
for i = 1, 8 do
    _G["SmartMark_SetMarkF" .. i] = function()
        if not addon.Config then return end
        local priority = addon.Config:Get("fKeyPriorityMap.f" .. i)
        if not priority then return end
        addon.Config:Set("priorityToMark." .. priority, i)
        printMsg(priority .. " -> " .. (markIconNames[i] or i) .. " (" .. i .. ")")
    end
end

local function handleSlashCommand(input)
    local cmd, rest = string.match(input or "", "^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    rest = rest or ""

    if cmd == "" or cmd == "help" then
        printMsg("Commands: /sm start, /sm stop, /sm reset, /sm status, /sm config, /sm ie, /sm export, /sm import")
        return
    end

    if cmd == "start" then
        if addon.MarkManager then
            addon.MarkManager:StartSession("manual")
            printMsg("Session started")
        end
        return
    end

    if cmd == "stop" then
        if addon.MarkManager then
            addon.MarkManager:StopSession(true)
            printMsg("Session stopped")
        end
        return
    end

    if cmd == "reset" then
        if addon.MarkManager then
            addon.MarkManager:ResetSession(true)
            printMsg("Session reset")
        end
        return
    end

    if cmd == "status" then
        if addon.MarkManager then
            local status = addon.MarkManager:GetStatusText()
            printMsg(status)
        end
        return
    end

    if cmd == "config" then
        if addon.UI and addon.UI.OpenConfig then
            addon.UI:OpenConfig()
        else
            printMsg("Config UI not implemented yet")
        end
        return
    end

    if cmd == "ie" or cmd == "importexport" then
        if addon.UI and addon.UI.OpenMobEditor then
            addon.UI:OpenMobEditor()
        else
            printMsg("Import/export window not available")
        end
        return
    end

    if cmd == "export" then
        if not addon.ImportExport then
            printMsg("Import/export module unavailable")
            return
        end

        local data = addon.ImportExport:Export()
        printMsg("Export ready. Paste from chat edit box.")
        ChatFrame_OpenChat(data)
        return
    end

    if cmd == "import" or cmd == "importreplace" then
        if not addon.ImportExport then
            printMsg("Import/export module unavailable")
            return
        end

        local mode = "merge"
        local payload = rest

        if cmd == "importreplace" then
            mode = "replace"
        else
            local firstWord, remaining = string.match(rest, "^(%S+)%s*(.-)%s*$")
            local lowerWord = string.lower(firstWord or "")
            if lowerWord == "replace" then
                mode = "replace"
                payload = remaining or ""
            elseif lowerWord == "merge" then
                mode = "merge"
                payload = remaining or ""
            end
        end

        if payload == "" then
            printMsg("Usage: /sm import [merge|replace] SMDB:1:...")
            return
        end

        local ok, result = addon.ImportExport:Import(payload, mode)
        if ok then
            printMsg(result)
        else
            printMsg("Import failed: " .. tostring(result))
        end
        return
    end

    printMsg("Unknown command. Use /sm help")
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event ~= "ADDON_LOADED" or arg1 ~= "SmartMark" then
        return
    end

    ensureSavedVariables()

    if addon.Config and addon.Config.Initialize then
        addon.Config:Initialize()
    end

    SLASH_SMARTMARK1 = "/smartmark"
    SLASH_SMARTMARK2 = "/sm"
    SlashCmdList.SMARTMARK = handleSlashCommand

    printMsg("Loaded v" .. addon.VERSION)
end)
