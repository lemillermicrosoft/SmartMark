local addon = SmartMark
addon.PriorityEngine = addon.PriorityEngine or {}

local PriorityEngine = addon.PriorityEngine

local killWeights = {
    kill1 = 1,
    kill2 = 2,
    kill3 = 3,
    kill4 = 4,
    auto_elite = 5,
    auto = 6,
}

local ccFallbackOrder = { "cc_sheep", "cc_sap", "cc_banish", "cc_shackle", "cc_trap" }

local function isLeaderOrAssist()
    if not IsInGroup() then
        return true
    end
    if UnitIsGroupLeader("player") then
        return true
    end
    return UnitIsGroupAssistant("player")
end

function PriorityEngine:BuildAvailableCC()
    local available = {
        cc_sheep = false,
        cc_sap = false,
        cc_banish = false,
        cc_shackle = false,
        cc_trap = false,
    }

    local function checkUnit(unit)
        if not UnitExists(unit) then
            return
        end

        local _, class = UnitClass(unit)
        if class == "MAGE" then
            available.cc_sheep = true
        elseif class == "ROGUE" then
            available.cc_sap = true
        elseif class == "WARLOCK" then
            available.cc_banish = true
        elseif class == "PRIEST" then
            available.cc_shackle = true
        elseif class == "HUNTER" then
            available.cc_trap = true
        end
    end

    checkUnit("player")

    if IsInRaid() then
        local count = GetNumGroupMembers() or 0
        for i = 1, count do
            checkUnit("raid" .. i)
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            checkUnit("party" .. i)
        end
    end

    return available
end

function PriorityEngine:Heuristic(mob)
    local ccByType = {
        Humanoid = "cc_sap",
        Beast = "cc_trap",
        Demon = "cc_banish",
        Elemental = "cc_banish",
        Undead = "cc_shackle",
    }

    local ccType = ccByType[mob.creatureType or ""]
    if ccType then
        return ccType
    end

    if mob.classification == "elite" or mob.classification == "rareelite" then
        return "kill1"
    end

    return "auto"
end

function PriorityEngine:ResolveCCPriority(priorityType, availableCC)
    if not string.find(priorityType or "", "^cc_") then
        return priorityType
    end

    if availableCC[priorityType] then
        return priorityType
    end

    for _, candidate in ipairs(ccFallbackOrder) do
        if availableCC[candidate] then
            return candidate
        end
    end

    return "kill3"
end

function PriorityEngine:FindUnitByGUID(guid)
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitGUID(unit) == guid then
            return unit
        end
    end

    local fallbackUnits = { "target", "focus", "mouseover" }
    for _, unit in ipairs(fallbackUnits) do
        if UnitExists(unit) and UnitGUID(unit) == guid then
            return unit
        end
    end

    return nil
end

function PriorityEngine:ApplyMarks(session)
    if not isLeaderOrAssist() then
        addon.Print("You need party lead or assist to set raid markers.")
        return
    end

    local overwrite = addon.Config:Get("overwriteExistingMarks")

    for guid, mark in pairs(session.marks) do
        local unit = self:FindUnitByGUID(guid)
        if unit and mark then
            local current = GetRaidTargetIndex(unit)
            if (not overwrite) and current and current > 0 and current ~= mark then
                -- Respect manual or pre-existing marks unless overwrite is explicitly enabled.
                session.marks[guid] = current
            elseif current ~= mark then
                SetRaidTarget(unit, mark)
            end
        end
    end
end

function PriorityEngine:Reassign(session)
    local killList = {}
    local ccList = {}

    local autoDetect = addon.Config:Get("autoDetectGroupCC")
    local availableCC = autoDetect and self:BuildAvailableCC() or {
        cc_sheep = true,
        cc_sap = true,
        cc_banish = true,
        cc_shackle = true,
        cc_trap = true,
    }

    for _, mob in ipairs(session.mobs) do
        local entry = addon.MobDatabase:Lookup(mob.npcID)
        local resolvedPriority

        if entry and entry.priorityType then
            resolvedPriority = entry.priorityType
        else
            resolvedPriority = self:Heuristic(mob)
        end

        if resolvedPriority ~= "skip" then
            resolvedPriority = self:ResolveCCPriority(resolvedPriority, availableCC)
            mob.priorityType = resolvedPriority

            if string.find(resolvedPriority, "^kill") or resolvedPriority == "auto" then
                table.insert(killList, mob)
            elseif string.find(resolvedPriority, "^cc_") then
                table.insert(ccList, mob)
            end
        end
    end

    table.sort(killList, function(a, b)
        local wa = killWeights[a.priorityType] or 99
        local wb = killWeights[b.priorityType] or 99
        if wa ~= wb then
            return wa < wb
        end
        return a.scrubOrder < b.scrubOrder
    end)

    table.sort(ccList, function(a, b)
        local pa = addon.Config:Get("priorityToMark." .. (a.priorityType or "")) or 99
        local pb = addon.Config:Get("priorityToMark." .. (b.priorityType or "")) or 99
        if pa ~= pb then
            return pa > pb
        end
        return a.scrubOrder < b.scrubOrder
    end)

    session.marks = {}

    local killMarks = addon.Config:Get("markOrder.kill") or {}
    for i, mob in ipairs(killList) do
        local mark = killMarks[i]
        if mark then
            mob.assignedMark = mark
            session.marks[mob.guid] = mark
        end
    end

    for _, mob in ipairs(ccList) do
        local mark = addon.Config:Get("priorityToMark." .. mob.priorityType)
        if mark and not session.marks[mob.guid] then
            mob.assignedMark = mark
            session.marks[mob.guid] = mark
        end
    end

    self:ApplyMarks(session)
end
