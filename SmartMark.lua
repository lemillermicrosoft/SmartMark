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

local function handleSlashCommand(input)
    local cmd = string.lower(string.match(input or "", "^%s*(%S*)") or "")

    if cmd == "" or cmd == "help" then
        printMsg("Commands: /sm start, /sm stop, /sm reset, /sm status, /sm config")
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
