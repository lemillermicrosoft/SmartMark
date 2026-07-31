SmartMark = SmartMark or {}

SmartMark.VERSION = "0.2.2"

BINDING_HEADER_SMARTMARK = "SmartMark"
BINDING_NAME_SMARTMARK_CLEAR_MARKS = "Clear all marks"
BINDING_NAME_SMARTMARK_TOGGLE_SESSION = "Toggle marking session"

local addon = SmartMark
addon.modules = addon.modules or {}

local validPriorityTypes = {
    kill = true,
    kill1 = true,
    kill2 = true,
    kill3 = true,
    kill4 = true,
    cc_sheep = true,
    cc_sap = true,
    cc_banish = true,
    cc_shackle = true,
    cc_trap = true,
    skip = true,
    auto = true,
}

local legacyKillRank = {
    kill1 = 10,
    kill2 = 20,
    kill3 = 30,
    kill4 = 40,
}

local function canonicalizePriorityType(priorityType)
    if priorityType == "kill1" or priorityType == "kill2" or priorityType == "kill3" or priorityType == "kill4" then
        return "kill", legacyKillRank[priorityType]
    end
    return priorityType, nil
end

local function getNpcIDFromUnit(unit)
    local guid = UnitGUID(unit)
    if not guid then
        return nil
    end

    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" then
        return tonumber(npcID)
    end

    return nil
end

local function setMobPriorityByUnit(unit, priorityType)
    if not addon.Config or not addon.MobDatabase then
        return false, "Config or MobDatabase unavailable"
    end

    if not validPriorityTypes[priorityType] then
        return false, "Invalid priorityType"
    end

    local normalizedPriority, defaultRank = canonicalizePriorityType(priorityType)

    local npcID = getNpcIDFromUnit(unit)
    if not npcID then
        return false, "No valid NPC under " .. unit
    end

    if normalizedPriority == "auto" then
        addon.MobDatabase:Delete(npcID)
        return true, string.format("%s NPC %d set to auto (custom entry removed)", unit, npcID)
    end

    local name = UnitName(unit) or ("NPC " .. tostring(npcID))
    local zone = GetRealZoneText() or ""
    local existing = addon.MobDatabase:Lookup(npcID)

    addon.MobDatabase:Set(npcID, {
        name = existing and existing.name or name,
        priorityType = normalizedPriority,
        notes = existing and existing.notes or "",
        zone = existing and existing.zone or zone,
        killRank = existing and existing.killRank or defaultRank,
        source = "user",
    })

    return true, string.format("%s (NPC %d) -> %s", name, npcID, normalizedPriority)
end

local function setMobPriorityByNpcID(npcID, priorityType)
    if not addon.Config or not addon.MobDatabase then
        return false, "Config or MobDatabase unavailable"
    end

    if not validPriorityTypes[priorityType] then
        return false, "Invalid priorityType"
    end

    local normalizedPriority, defaultRank = canonicalizePriorityType(priorityType)

    local idNum = tonumber(npcID)
    if not idNum or idNum <= 0 then
        return false, "Invalid NPC ID"
    end

    if normalizedPriority == "auto" then
        addon.MobDatabase:Delete(idNum)
        return true, string.format("NPC %d set to auto (custom entry removed)", idNum)
    end

    local existing = addon.MobDatabase:Lookup(idNum)
    addon.MobDatabase:Set(idNum, {
        name = existing and existing.name or ("NPC " .. tostring(idNum)),
        priorityType = normalizedPriority,
        notes = existing and existing.notes or "",
        zone = existing and existing.zone or (GetRealZoneText() or ""),
        killRank = existing and existing.killRank or defaultRank,
        source = "user",
    })

    return true, string.format("NPC %d -> %s", idNum, normalizedPriority)
end

local function normalizeRankToken(token)
    local lower = string.lower(token or "")
    if lower == "clear" or lower == "auto" or lower == "none" then
        return true, nil
    end

    local rank = tonumber(token)
    if not rank then
        return false, "Invalid rank"
    end

    rank = math.floor(rank)
    if rank < 1 or rank > 999 then
        return false, "Rank must be 1-999"
    end

    return true, rank
end

local function setMobRankByNpcID(npcID, rank)
    if not addon.MobDatabase then
        return false, "MobDatabase unavailable"
    end

    local idNum = tonumber(npcID)
    if not idNum or idNum <= 0 then
        return false, "Invalid NPC ID"
    end

    local existing = addon.MobDatabase:Lookup(idNum) or {
        name = "NPC " .. tostring(idNum),
        priorityType = "auto",
        notes = "",
        zone = GetRealZoneText() or "",
        source = "user",
    }

    existing.killRank = rank
    existing.source = "user"
    addon.MobDatabase:Set(idNum, existing)

    if rank then
        return true, string.format("NPC %d kill rank -> %d", idNum, rank)
    end
    return true, string.format("NPC %d kill rank cleared", idNum)
end

local function setMobRankByUnit(unit, rank)
    local npcID = getNpcIDFromUnit(unit)
    if not npcID then
        return false, "No valid NPC under " .. unit
    end

    local ok, msg = setMobRankByNpcID(npcID, rank)
    if not ok then
        return false, msg
    end

    local name = UnitName(unit) or ("NPC " .. tostring(npcID))
    if rank then
        return true, string.format("%s (NPC %d) kill rank -> %d", name, npcID, rank)
    end
    return true, string.format("%s (NPC %d) kill rank cleared", name, npcID)
end

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
        local canceledExtra = nil
        if addon.MarkManager:IsDeferredClearActive() then
            canceledExtra = addon.MarkManager:CancelDeferredClearRetry()
        end

        local cleared = addon.MarkManager:ResetSession(true) or 0
        if canceledExtra ~= nil then
            printMsg("Cleared marks: " .. tostring(cleared) .. " (retry restarted; prior extra clears: " .. tostring(canceledExtra or 0) .. ")")
        else
            printMsg("Cleared marks: " .. tostring(cleared))
        end
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

-- F-key quick-assign globals (invoked by Ctrl+Alt+F1â€“F8 keybindings).
-- Each binding remaps one priority type â†’ its F-key's icon index.
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
        printMsg("Commands: /sm start, /sm stop, /sm reset, /sm status, /sm config, /sm dungeon, /sm ie, /sm export, /sm import, /sm prio, /sm rank")
        return
    end

    if cmd == "dungeon" or cmd == "dungeons" then
        if addon.UI and addon.UI.OpenDungeonPriorityPanel then
            local ok, shownOrErr = pcall(function()
                return addon.UI:OpenDungeonPriorityPanel()
            end)

            if not ok then
                printMsg("Dungeon priorities UI error: " .. tostring(shownOrErr))
            elseif shownOrErr then
                printMsg("Dungeon priorities opened")
            else
                printMsg("Dungeon priorities closed")
            end
        else
            printMsg("Dungeon priorities UI not available")
        end
        return
    end

    if cmd == "rank" then
        local mode, a, b = string.match(rest, "^(%S+)%s*(%S*)%s*(.-)%s*$")
        mode = string.lower(mode or "")

        if mode == "" or mode == "help" then
            printMsg("Usage: /sm rank target <n|clear> | /sm rank mouseover <n|clear> | /sm rank npc <id> <n|clear>")
            printMsg("Lower rank = higher kill priority when mob is in kill bucket")
            return
        end

        if mode == "target" or mode == "mouseover" then
            local okRank, rankOrErr = normalizeRankToken(a)
            if not okRank then
                printMsg("Rank update failed: " .. tostring(rankOrErr))
                return
            end

            local ok, message = setMobRankByUnit(mode, rankOrErr)
            if ok then
                printMsg(message)
                if addon.MarkManager and addon.Config:Get("reassignmentMode") == "realtime" and addon.MarkManager.session and addon.MarkManager.session.active then
                    addon.PriorityEngine:Reassign(addon.MarkManager.session)
                end
            else
                printMsg("Rank update failed: " .. tostring(message))
            end
            return
        end

        if mode == "npc" then
            local npcID = a
            local okRank, rankOrErr = normalizeRankToken(b)
            if not okRank then
                printMsg("Rank update failed: " .. tostring(rankOrErr))
                return
            end

            local ok, message = setMobRankByNpcID(npcID, rankOrErr)
            if ok then
                printMsg(message)
            else
                printMsg("Rank update failed: " .. tostring(message))
            end
            return
        end

        printMsg("Unknown rank mode. Use: target, mouseover, or npc")
        return
    end

    if cmd == "prio" or cmd == "priority" then
        local mode, a, b = string.match(rest, "^(%S+)%s*(%S*)%s*(.-)%s*$")
        mode = string.lower(mode or "")

        if mode == "" or mode == "help" then
            printMsg("Usage: /sm prio target <type> | /sm prio mouseover <type> | /sm prio npc <id> <type>")
            printMsg("Types: kill cc_sheep cc_sap cc_banish cc_shackle cc_trap skip auto")
            printMsg("Legacy kill1-4 is supported and auto-converted to kill + default rank")
            return
        end

        if mode == "target" or mode == "mouseover" then
            local priorityType = string.lower(a or "")
            local ok, message = setMobPriorityByUnit(mode, priorityType)
            if ok then
                printMsg(message)
                if addon.MarkManager and addon.Config:Get("reassignmentMode") == "realtime" and addon.MarkManager.session and addon.MarkManager.session.active then
                    addon.PriorityEngine:Reassign(addon.MarkManager.session)
                end
            else
                printMsg("Priority update failed: " .. tostring(message))
            end
            return
        end

        if mode == "npc" then
            local npcID = a
            local priorityType = string.lower(b or "")
            local ok, message = setMobPriorityByNpcID(npcID, priorityType)
            if ok then
                printMsg(message)
            else
                printMsg("Priority update failed: " .. tostring(message))
            end
            return
        end

        printMsg("Unknown prio mode. Use: target, mouseover, or npc")
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
            local ok, shownOrErr = pcall(function()
                return addon.UI:OpenConfig()
            end)

            if not ok then
                printMsg("Config UI error: " .. tostring(shownOrErr))
                if addon.UI and addon.UI.OpenMobEditor then
                    addon.UI:OpenMobEditor()
                    printMsg("Opened Import/Export window as fallback")
                end
            elseif shownOrErr then
                printMsg("Config opened")
            else
                printMsg("Config closed")
            end
        else
            if addon.UI and addon.UI.OpenMobEditor then
                addon.UI:OpenMobEditor()
                printMsg("Config UI unavailable; opened Import/Export window")
            else
                printMsg("Config UI not implemented yet")
            end
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


