local addon = SmartMark
addon.MarkManager = addon.MarkManager or {}

local MarkManager = addon.MarkManager

local function getNpcID(unit)
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

local function modComboSatisfied()
    local keys = addon.Config:Get("modifierKeys") or {}

    local altOK = (not keys.alt) or IsAltKeyDown()
    local shiftOK = (not keys.shift) or IsShiftKeyDown()
    local ctrlOK = (not keys.ctrl) or IsControlKeyDown()

    return altOK and shiftOK and ctrlOK
end

local function addUnitToken(tokens, token)
    if token and token ~= "" then
        tokens[#tokens + 1] = token
    end
end

local function buildClearUnitTokenList()
    local tokens = {}

    -- Core unit tokens.
    addUnitToken(tokens, "target")
    addUnitToken(tokens, "focus")
    addUnitToken(tokens, "mouseover")

    -- Party units and their targets/pets.
    for i = 1, 4 do
        addUnitToken(tokens, "party" .. i)
        addUnitToken(tokens, "party" .. i .. "target")
        addUnitToken(tokens, "partypet" .. i)
        addUnitToken(tokens, "partypet" .. i .. "target")
    end

    -- Raid units and their targets/pets.
    for i = 1, 40 do
        addUnitToken(tokens, "raid" .. i)
        addUnitToken(tokens, "raid" .. i .. "target")
        addUnitToken(tokens, "raidpet" .. i)
        addUnitToken(tokens, "raidpet" .. i .. "target")
    end

    -- Nearby enemies.
    for i = 1, 40 do
        addUnitToken(tokens, "nameplate" .. i)
    end

    return tokens
end

function MarkManager:Initialize()
    self.session = {
        active = false,
        mobs = {},
        guidIndex = {},
        marks = {},
        nextKillIndex = 1,
    }
    self.pendingClearUntil = 0
    self.pendingClearNextSweepAt = 0
    self.pendingClearExtraCleared = 0
    self.pendingClearAnnounced = false
end

function MarkManager:UpdateOverlayState()
    if not addon.UI then
        return
    end

    local active = self.session and self.session.active
    if addon.UI.SetOverlayActive then
        addon.UI:SetOverlayActive(active)
    end

    if active and addon.UI.UpdateOverlay then
        local count = #(self.session.mobs or {})
        local markMode = addon.Config:Get("activationMode") or "hold"
        addon.UI:UpdateOverlay(string.format("SmartMark Active\nMode: %s\nTracked Mobs: %d", markMode, count))
    end
end

function MarkManager:PerformClearSweep()
    local cleared = 0
    local seenGUID = {}
    local tokens = buildClearUnitTokenList()

    for _, unit in ipairs(tokens) do
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            local mark = GetRaidTargetIndex(unit)
            if mark and mark > 0 and (not guid or not seenGUID[guid]) then
                SetRaidTarget(unit, 0)
                cleared = cleared + 1
                if guid then
                    seenGUID[guid] = true
                end
            end
        end
    end

    -- Retry clear for units from the current session map when resolvable.
    if addon.PriorityEngine and self.session and self.session.marks then
        for guid in pairs(self.session.marks) do
            if not seenGUID[guid] then
                local unit = addon.PriorityEngine:FindUnitByGUID(guid)
                if unit and UnitExists(unit) then
                    local mark = GetRaidTargetIndex(unit)
                    if mark and mark > 0 then
                        SetRaidTarget(unit, 0)
                        cleared = cleared + 1
                        seenGUID[guid] = true
                    end
                end
            end
        end
    end

    return cleared
end

function MarkManager:BeginDeferredClearRetry()
    local now = GetTime()
    self.pendingClearUntil = now + 8.0
    self.pendingClearNextSweepAt = now
    self.pendingClearExtraCleared = 0
    self.pendingClearAnnounced = true

    if addon.Print then
        addon.Print("Clear retry active for 8s")
    end
end

function MarkManager:IsDeferredClearActive()
    return self.pendingClearUntil and self.pendingClearUntil > GetTime()
end

function MarkManager:CancelDeferredClearRetry()
    local extraCleared = self.pendingClearExtraCleared or 0
    self.pendingClearUntil = 0
    self.pendingClearNextSweepAt = 0
    self.pendingClearExtraCleared = 0
    self.pendingClearAnnounced = false
    return extraCleared
end

function MarkManager:ProcessDeferredClear()
    local now = GetTime()
    if not self.pendingClearUntil or self.pendingClearUntil <= 0 then
        return
    end

    if now >= self.pendingClearUntil then
        if self.pendingClearAnnounced and addon.Print then
            addon.Print("Clear retry finished. Additional marks cleared: " .. tostring(self.pendingClearExtraCleared or 0))
        end
        self.pendingClearUntil = 0
        self.pendingClearNextSweepAt = 0
        self.pendingClearExtraCleared = 0
        self.pendingClearAnnounced = false
        return
    end

    if now < (self.pendingClearNextSweepAt or 0) then
        return
    end

    self.pendingClearNextSweepAt = now + 0.20
    local cleared = self:PerformClearSweep()
    self.pendingClearExtraCleared = (self.pendingClearExtraCleared or 0) + (cleared or 0)
end

function MarkManager:StartSession(reason)
    if not self.session then
        self:Initialize()
    end

    self.session.active = true
    self.session.reason = reason or "unknown"
    self:UpdateOverlayState()
end

function MarkManager:StopSession(runReassign)
    if not self.session or not self.session.active then
        return
    end

    if runReassign and addon.PriorityEngine then
        addon.PriorityEngine:Reassign(self.session)
    end

    self.session.active = false
    SmartMarkCharDB.markingActive = false

    SmartMarkCharDB.lastSession = SmartMarkCharDB.lastSession or {}
    SmartMarkCharDB.lastSession.timestamp = time()
    SmartMarkCharDB.lastSession.zone = GetRealZoneText() or ""
    SmartMarkCharDB.lastSession.marks = self.session.marks
    self:UpdateOverlayState()
end

function MarkManager:ResetSession(clearMarks)
    if not self.session then
        self:Initialize()
    end

    local cleared = 0

    if clearMarks then
        cleared = self:PerformClearSweep()
        self:BeginDeferredClearRetry()
    else
        self.pendingClearUntil = 0
        self.pendingClearNextSweepAt = 0
        self.pendingClearExtraCleared = 0
        self.pendingClearAnnounced = false
    end

    self.session.active = false
    self.session.mobs = {}
    self.session.guidIndex = {}
    self.session.marks = {}
    self.session.nextKillIndex = 1
    self:UpdateOverlayState()

    return cleared
end

function MarkManager:IsMarkingActive()
    local mode = addon.Config:Get("activationMode")

    if mode == "toggle" then
        return self.session.active
    end

    return self.session.active and modComboSatisfied()
end

function MarkManager:TryAutoStartFromHold()
    if addon.Config:Get("activationMode") ~= "hold" then
        return
    end

    if self.session.active then
        return
    end

    if modComboSatisfied() then
        self:StartSession("hold")
    end
end

function MarkManager:AssignTemporaryMark(mobInfo)
    local killMarks = addon.Config:Get("markOrder.kill") or {}
    local mark = killMarks[self.session.nextKillIndex]
    if not mark then
        return
    end

    local unit = "mouseover"
    if UnitExists(unit) and UnitGUID(unit) == mobInfo.guid then
        local current = GetRaidTargetIndex(unit)
        if addon.Config:Get("overwriteExistingMarks") or not current then
            SetRaidTarget(unit, mark)
            self.session.marks[mobInfo.guid] = mark
        end
    end

    self.session.nextKillIndex = self.session.nextKillIndex + 1
end

function MarkManager:OnMouseoverUpdate()
    if addon.Config:Get("disableInCombat") and InCombatLockdown() then
        return
    end

    self:TryAutoStartFromHold()

    if not self:IsMarkingActive() then
        return
    end

    local unit = "mouseover"
    if not UnitExists(unit) then
        return
    end
    if UnitPlayerControlled(unit) then
        return
    end
    if not UnitIsEnemy("player", unit) then
        return
    end
    if UnitIsDead(unit) then
        return
    end

    local guid = UnitGUID(unit)
    if not guid then
        return
    end

    if self.session.guidIndex[guid] then
        return
    end

    local existingMark = GetRaidTargetIndex(unit)
    if existingMark and not addon.Config:Get("overwriteExistingMarks") then
        return
    end

    local name = UnitName(unit)
    local mobInfo = {
        guid = guid,
        npcID = getNpcID(unit),
        name = name or "Unknown",
        level = UnitLevel(unit) or -1,
        classification = UnitClassification(unit) or "normal",
        creatureType = UnitCreatureType(unit) or "Unknown",
        scrubOrder = #self.session.mobs + 1,
        priorityType = "auto",
        assignedMark = nil,
    }

    table.insert(self.session.mobs, mobInfo)
    self.session.guidIndex[guid] = #self.session.mobs
    self:UpdateOverlayState()

    self:AssignTemporaryMark(mobInfo)

    if addon.Config:Get("reassignmentMode") == "realtime" and addon.PriorityEngine then
        addon.PriorityEngine:Reassign(self.session)
    end
end

function MarkManager:UpdateHoldState()
    if addon.Config:Get("activationMode") ~= "hold" then
        return
    end

    if self.session and self.session.active and not modComboSatisfied() then
        self:StopSession(true)
    end
end

function MarkManager:GetStatusText()
    if not self.session then
        return "Session not initialized"
    end

    local active = self.session.active and "active" or "inactive"
    local count = #self.session.mobs
    return string.format("Session %s, tracked mobs: %d", active, count)
end
