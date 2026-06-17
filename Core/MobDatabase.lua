local addon = SmartMark
addon.MobDatabase = addon.MobDatabase or {}

local MobDatabase = addon.MobDatabase

function MobDatabase:Lookup(npcID)
    if not npcID then
        return nil
    end
    local db = addon.Config:GetMobDB()
    return db[tostring(npcID)]
end

function MobDatabase:Set(npcID, entry)
    if not npcID or type(entry) ~= "table" then
        return false
    end
    local db = addon.Config:GetMobDB()
    db[tostring(npcID)] = entry
    return true
end

function MobDatabase:Delete(npcID)
    if not npcID then
        return false
    end
    local db = addon.Config:GetMobDB()
    db[tostring(npcID)] = nil
    return true
end
