local addon = SmartMark
addon.ImportExport = addon.ImportExport or {}

local ImportExport = addon.ImportExport
local PREFIX = "SMDB:1:"

local validPriority = {
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

local function normalizePriority(priorityType)
    if priorityType == "kill1" or priorityType == "kill2" or priorityType == "kill3" or priorityType == "kill4" then
        return "kill", legacyKillRank[priorityType]
    end
    return priorityType, nil
end

function ImportExport:Export()
    local db = addon.Config:GetMobDB()
    local out = {}

    for npcID, entry in pairs(db) do
        local name = tostring(entry.name or "")
        local zone = tostring(entry.zone or "")
        name = string.gsub(name, "[,|]", ";")
        zone = string.gsub(zone, "[,|]", ";")

        out[#out + 1] = table.concat({
            tostring(npcID),
            tostring(entry.priorityType or "kill"),
            name,
            zone,
        }, ",")
    end

    table.sort(out)
    return PREFIX .. table.concat(out, "|")
end

function ImportExport:Import(input, mode)
    if type(input) ~= "string" then
        return false, "Invalid payload"
    end

    if string.sub(input, 1, string.len(PREFIX)) ~= PREFIX then
        return false, "Invalid prefix"
    end

    local payload = string.sub(input, string.len(PREFIX) + 1)
    local db = addon.Config:GetMobDB()

    if mode == "replace" then
        for k in pairs(db) do
            db[k] = nil
        end
    end

    local imported = 0
    local skipped = 0

    for entry in string.gmatch(payload, "[^|]+") do
        local npcID, priorityType, name, zone = string.match(entry, "^(%d+),([^,]+),([^,]*),([^,]*)$")
        local idNum = tonumber(npcID)

        if idNum and validPriority[priorityType] then
            local normalizedPriority, defaultRank = normalizePriority(priorityType)
            local key = tostring(idNum)
            if mode == "merge" and db[key] then
                skipped = skipped + 1
            else
                db[key] = {
                    name = name or "",
                    priorityType = normalizedPriority,
                    killRank = defaultRank,
                    notes = "",
                    zone = zone or "",
                    source = "imported",
                }
                imported = imported + 1
            end
        else
            skipped = skipped + 1
        end
    end

    return true, string.format("Imported: %d, Skipped: %d", imported, skipped)
end
