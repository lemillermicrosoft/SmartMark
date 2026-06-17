local addon = SmartMark

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")

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

frame:SetScript("OnEvent", function(_, event)
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
        if addon.Config and addon.Config:Get("disableInCombat") and addon.MarkManager then
            addon.MarkManager:StopSession(true)
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        if addon.MarkManager and addon.Config:Get("reassignmentMode") == "realtime" and addon.MarkManager.session and addon.MarkManager.session.active then
            addon.PriorityEngine:Reassign(addon.MarkManager.session)
        end
    end
end)
