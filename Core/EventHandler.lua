local addon = SmartMark

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")

local elapsedSincePoll = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    elapsedSincePoll = elapsedSincePoll + elapsed
    if elapsedSincePoll < 0.10 then
        return
    end

    elapsedSincePoll = 0
    if addon.MarkManager and addon.MarkManager.UpdateHoldState then
        addon.MarkManager:UpdateHoldState()
        addon.MarkManager:ProcessDeferredClear()
    end
end)

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        if addon.MarkManager then
            addon.MarkManager:Initialize()
            addon.MarkManager:ResetSession(false)
        end
        return
    end

    if event == "UPDATE_MOUSEOVER_UNIT" then
        if addon.MarkManager then
            addon.MarkManager:OnMouseoverUpdate()
        end
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        if addon.MarkManager and addon.Config:Get("reassignmentMode") == "deferred" and addon.MarkManager.session and addon.MarkManager.session.active then
            addon.PriorityEngine:Reassign(addon.MarkManager.session)
        end

        if addon.Config and addon.Config:Get("disableInCombat") and addon.MarkManager then
            addon.MarkManager:StopSession(true)
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if addon.MarkManager and addon.MarkManager.OnCombatEnded then
            addon.MarkManager:OnCombatEnded()
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        if addon.MarkManager and addon.Config:Get("reassignmentMode") == "realtime" and addon.MarkManager.session and addon.MarkManager.session.active then
            addon.PriorityEngine:Reassign(addon.MarkManager.session)
        end
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, _, _, _, destGUID = ...
        if subEvent == "UNIT_DIED" and addon.MarkManager then
            addon.MarkManager:OnUnitDied(destGUID)
        end
        return
    end

    if event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        if addon.PriorityEngine then
            addon.PriorityEngine:RetryPendingMark(unit)
        end
    end
end)
