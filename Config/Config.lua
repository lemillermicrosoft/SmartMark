local addon = SmartMark
addon.Config = addon.Config or {}

local Config = addon.Config

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
