local addon = SmartMark
addon.Config = addon.Config or {}

local Config = addon.Config

local legacyKillRank = {
    kill1 = 10,
    kill2 = 20,
    kill3 = 30,
    kill4 = 40,
}

local ccFallbackKillRank = {
    cc_sheep = 30,
    cc_sap = 30,
    cc_trap = 30,
    cc_banish = 35,
    cc_shackle = 35,
}

local function normalizePriorityType(priorityType)
    if priorityType == "kill1" or priorityType == "kill2" or priorityType == "kill3" or priorityType == "kill4" then
        return "kill"
    end
    return priorityType
end

local function ensureMobRankingDefaults(db)
    for _, entry in pairs(db or {}) do
        if type(entry) == "table" then
            local original = entry.priorityType
            local normalized = normalizePriorityType(original)

            if original ~= normalized then
                entry.priorityType = normalized
            end

            if entry.killRank == nil then
                if legacyKillRank[original] then
                    entry.killRank = legacyKillRank[original]
                elseif normalized == "kill" then
                    entry.killRank = 30
                elseif ccFallbackKillRank[normalized] then
                    entry.killRank = ccFallbackKillRank[normalized]
                elseif normalized == "auto" then
                    entry.killRank = 60
                end
            end
        end
    end
end

local function deepCopy(source)
    if type(source) ~= "table" then
        return source
    end
    local out = {}
    for k, v in pairs(source) do
        out[k] = deepCopy(v)
    end
    return out
end

local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = deepCopy(v)
        elseif type(v) == "table" and type(target[k]) == "table" then
            applyDefaults(target[k], v)
        end
    end
end

function Config:Initialize()
    SmartMarkDB = SmartMarkDB or {}
    SmartMarkCharDB = SmartMarkCharDB or {}

    applyDefaults(SmartMarkDB, addon.Defaults.DB)
    applyDefaults(SmartMarkCharDB, addon.Defaults.CharDB)

    if type(addon.BuiltinMobDB) == "table" then
        for npcID, entry in pairs(addon.BuiltinMobDB) do
            if SmartMarkDB.mobs[npcID] == nil then
                SmartMarkDB.mobs[npcID] = deepCopy(entry)
            end
        end
    end

    if type(addon.RaidMobDB) == "table" then
        for npcID, entry in pairs(addon.RaidMobDB) do
            if SmartMarkDB.mobs[npcID] == nil then
                SmartMarkDB.mobs[npcID] = deepCopy(entry)
            end
        end
    end

    ensureMobRankingDefaults(SmartMarkDB.mobs)
end

function Config:Get(path)
    local node = SmartMarkDB.settings
    for key in string.gmatch(path, "[^%.]+") do
        if type(node) ~= "table" then
            return nil
        end
        node = node[key]
    end
    return node
end

function Config:Set(path, value)
    local node = SmartMarkDB.settings
    local prev
    local last

    for key in string.gmatch(path, "[^%.]+") do
        prev = node
        last = key
        node = node[key]
    end

    if prev and last then
        prev[last] = value
    end
end

function Config:GetAllSettings()
    return SmartMarkDB.settings
end

function Config:GetMobDB()
    return SmartMarkDB.mobs
end
