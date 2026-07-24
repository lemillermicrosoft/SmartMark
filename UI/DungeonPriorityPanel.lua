local addon = SmartMark
addon.UI = addon.UI or {}

local UI = addon.UI

local panel
local zoneDropdown
local scrollFrame
local rows = {}

local state = {
    selectedZone = nil,
    zones = {},
    entries = {},
}

local PRIORITY_OPTIONS = {
    { label = "kill", value = "kill" },
    { label = "cc_sheep", value = "cc_sheep" },
    { label = "cc_sap", value = "cc_sap" },
    { label = "cc_banish", value = "cc_banish" },
    { label = "cc_shackle", value = "cc_shackle" },
    { label = "cc_trap", value = "cc_trap" },
    { label = "skip", value = "skip" },
    { label = "auto", value = "auto" },
}

local VALID_PRIORITY = {
    kill = true,
    cc_sheep = true,
    cc_sap = true,
    cc_banish = true,
    cc_shackle = true,
    cc_trap = true,
    skip = true,
    auto = true,
}

local ROW_HEIGHT = 24
local VISIBLE_ROWS = 12

local function printMsg(msg)
    if addon.Print then
        addon.Print(msg)
    end
end

local function triggerRealtimeReassign()
    if not addon.MarkManager or not addon.Config or not addon.PriorityEngine then
        return
    end

    if addon.Config:Get("reassignmentMode") ~= "realtime" then
        return
    end

    if addon.MarkManager.session and addon.MarkManager.session.active then
        addon.PriorityEngine:Reassign(addon.MarkManager.session)
    end
end

local function saveMobEntry(npcID, entry)
    if not addon.MobDatabase then
        return
    end

    entry.source = "user"
    addon.MobDatabase:Set(npcID, entry)
end

local function buildZones()
    local db = addon.Config and addon.Config:GetMobDB() or {}
    local seen = {}
    local zones = {}

    for _, entry in pairs(db) do
        local zone = entry and entry.zone or ""
        if zone ~= "" and not seen[zone] then
            seen[zone] = true
            zones[#zones + 1] = zone
        end
    end

    table.sort(zones)
    return zones
end

local function buildEntriesForZone(zone)
    local db = addon.Config and addon.Config:GetMobDB() or {}
    local list = {}

    for npcID, entry in pairs(db) do
        if entry and entry.zone == zone then
            list[#list + 1] = {
                npcID = tonumber(npcID),
                npcKey = tostring(npcID),
                entry = entry,
            }
        end
    end

    table.sort(list, function(a, b)
        local an = string.lower((a.entry and a.entry.name) or "")
        local bn = string.lower((b.entry and b.entry.name) or "")
        if an ~= bn then
            return an < bn
        end
        return (a.npcID or 0) < (b.npcID or 0)
    end)

    return list
end

local function defaultZone(zones)
    local current = GetRealZoneText() or ""
    for _, zone in ipairs(zones) do
        if zone == current then
            return zone
        end
    end
    return zones[1]
end

local function createPriorityDropdown(parent, width, x, y, onSelect)
    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dropdown, width)

    UIDropDownMenu_Initialize(dropdown, function(self)
        for _, row in ipairs(PRIORITY_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = row.label
            info.value = row.value
            info.func = function()
                UIDropDownMenu_SetSelectedValue(self, row.value)
                UIDropDownMenu_SetText(self, row.label)
                onSelect(row.value)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    return dropdown
end

local function refreshRows()
    if not scrollFrame then
        return
    end

    local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0

    for i = 1, VISIBLE_ROWS do
        local row = rows[i]
        local idx = i + offset
        local data = state.entries[idx]

        if data then
            local entry = data.entry
            local npcID = tonumber(data.npcKey) or data.npcID or 0
            local priorityType = entry.priorityType
            local killRank = entry.killRank

            if not VALID_PRIORITY[priorityType] then
                priorityType = "auto"
            end

            row.data = data
            row.nameText:SetText(entry.name or ("NPC " .. tostring(npcID)))
            row.npcText:SetText(tostring(npcID))

            UIDropDownMenu_SetSelectedValue(row.priorityDropdown, priorityType)
            UIDropDownMenu_SetText(row.priorityDropdown, priorityType)

            if killRank ~= nil and killRank ~= "" then
                row.rankBox:SetText(tostring(killRank))
            else
                row.rankBox:SetText("")
            end

            row:Show()
        else
            row.data = nil
            row:Hide()
        end
    end

    FauxScrollFrame_Update(scrollFrame, #state.entries, VISIBLE_ROWS, ROW_HEIGHT)
end

local function refreshEntries()
    if not state.selectedZone then
        state.entries = {}
    else
        state.entries = buildEntriesForZone(state.selectedZone)
    end
    refreshRows()
end

local function refreshZones(preferCurrentZone)
    state.zones = buildZones()
    if #state.zones == 0 then
        state.selectedZone = nil
        UIDropDownMenu_SetText(zoneDropdown, "No dungeon data")
        refreshEntries()
        return
    end

    if preferCurrentZone or not state.selectedZone then
        state.selectedZone = defaultZone(state.zones)
    else
        local found = false
        for _, zone in ipairs(state.zones) do
            if zone == state.selectedZone then
                found = true
                break
            end
        end
        if not found then
            state.selectedZone = defaultZone(state.zones)
        end
    end

    UIDropDownMenu_SetSelectedValue(zoneDropdown, state.selectedZone)
    UIDropDownMenu_SetText(zoneDropdown, state.selectedZone)
    refreshEntries()
end

local function commitRank(row)
    if not row or not row.data then
        return
    end

    local text = row.rankBox:GetText() or ""
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    local rank = nil
    if text ~= "" then
        rank = tonumber(text)
        if not rank then
            printMsg("Kill rank must be numeric (or blank to clear)")
            refreshRows()
            return
        end

        rank = math.floor(rank)
        if rank < 1 or rank > 999 then
            printMsg("Kill rank must be between 1 and 999")
            refreshRows()
            return
        end
    end

    local entry = row.data.entry
    entry.killRank = rank
    saveMobEntry(row.data.npcKey, entry)
    triggerRealtimeReassign()
    refreshRows()
end

local function createRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(640, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(true)
    if math.fmod(index, 2) == 0 then
        row.bg:SetTexture(1, 1, 1, 0.06)
    else
        row.bg:SetTexture(0, 0, 0, 0.14)
    end

    row.sep1 = row:CreateTexture(nil, "BORDER")
    row.sep1:SetTexture(1, 1, 1, 0.08)
    row.sep1:SetPoint("TOPLEFT", 255, -2)
    row.sep1:SetPoint("BOTTOMLEFT", 255, 2)
    row.sep1:SetWidth(1)

    row.sep2 = row:CreateTexture(nil, "BORDER")
    row.sep2:SetTexture(1, 1, 1, 0.08)
    row.sep2:SetPoint("TOPLEFT", 312, -2)
    row.sep2:SetPoint("BOTTOMLEFT", 312, 2)
    row.sep2:SetWidth(1)

    row.sep3 = row:CreateTexture(nil, "BORDER")
    row.sep3:SetTexture(1, 1, 1, 0.08)
    row.sep3:SetPoint("TOPLEFT", 510, -2)
    row.sep3:SetPoint("BOTTOMLEFT", 510, 2)
    row.sep3:SetWidth(1)

    row.bottomLine = row:CreateTexture(nil, "BORDER")
    row.bottomLine:SetTexture(1, 1, 1, 0.10)
    row.bottomLine:SetPoint("BOTTOMLEFT", 0, 0)
    row.bottomLine:SetPoint("BOTTOMRIGHT", 0, 0)
    row.bottomLine:SetHeight(1)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", 8, 0)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWidth(250)

    row.npcText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.npcText:SetPoint("LEFT", 262, 0)
    row.npcText:SetJustifyH("LEFT")
    row.npcText:SetWidth(46)

    row.priorityDropdown = createPriorityDropdown(row, 168, 314, 8, function(value)
        if not row.data then
            return
        end
        row.data.entry.priorityType = value
        saveMobEntry(row.data.npcKey, row.data.entry)
        triggerRealtimeReassign()
        refreshRows()
    end)

    row.rankBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.rankBox:SetSize(58, 20)
    row.rankBox:SetPoint("LEFT", 518, 0)
    row.rankBox:SetAutoFocus(false)
    row.rankBox:SetNumeric(true)
    row.rankBox:SetMaxLetters(3)
    row.rankBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        commitRank(row)
    end)
    row.rankBox:SetScript("OnEditFocusLost", function()
        commitRank(row)
    end)

    local hint = row:CreateFontString(nil, "OVERLAY", "GameFontDisableTiny")
    hint:SetPoint("LEFT", 582, 0)
    hint:SetText("1=top")

    return row
end

local function createPanel()
    if panel then
        return
    end

    local frameTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
    panel = CreateFrame("Frame", "SmartMarkDungeonPriorityPanel", UIParent, frameTemplate)
    panel:SetSize(760, 470)
    panel:SetPoint("CENTER")
    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 11, top = 11, bottom = 11 },
        })
    end
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("SmartMark Dungeon Priorities")

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", 24, -44)
    subtitle:SetText("Set CC type and optional kill rank per mob. Lower kill rank = higher kill order.")

    local zoneLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    zoneLabel:SetPoint("TOPLEFT", 24, -68)
    zoneLabel:SetText("Dungeon")

    zoneDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    zoneDropdown:SetPoint("TOPLEFT", 10, -84)
    UIDropDownMenu_SetWidth(zoneDropdown, 260)
    UIDropDownMenu_Initialize(zoneDropdown, function(self)
        for _, zone in ipairs(state.zones) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = zone
            info.value = zone
            info.func = function()
                state.selectedZone = zone
                UIDropDownMenu_SetSelectedValue(self, zone)
                UIDropDownMenu_SetText(self, zone)
                refreshEntries()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local headerName = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerName:SetPoint("TOPLEFT", 30, -126)
    headerName:SetText("Mob")

    local headerNPC = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerNPC:SetPoint("TOPLEFT", 286, -126)
    headerNPC:SetText("NPC ID")

    local headerPriority = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerPriority:SetPoint("TOPLEFT", 350, -126)
    headerPriority:SetText("Priority Type")

    local headerRank = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerRank:SetPoint("TOPLEFT", 540, -126)
    headerRank:SetText("Kill Rank")

    local headerLine = panel:CreateTexture(nil, "BORDER")
    headerLine:SetTexture(1, 1, 1, 0.18)
    headerLine:SetPoint("TOPLEFT", 24, -140)
    headerLine:SetPoint("TOPRIGHT", -56, -140)
    headerLine:SetHeight(1)

    local listFrame = CreateFrame("Frame", nil, panel)
    listFrame:SetSize(680, ROW_HEIGHT * VISIBLE_ROWS)
    listFrame:SetPoint("TOPLEFT", 24, -144)

    scrollFrame = CreateFrame("ScrollFrame", "SmartMarkDungeonPriorityScroll", panel, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 0, -2)
    scrollFrame:SetPoint("BOTTOMLEFT", listFrame, "BOTTOMRIGHT", 0, 2)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, refreshRows)
    end)

    for i = 1, VISIBLE_ROWS do
        rows[i] = createRow(listFrame, i)
    end

    local refreshButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refreshButton:SetSize(90, 24)
    refreshButton:SetPoint("BOTTOMLEFT", 24, 18)
    refreshButton:SetText("Refresh")
    refreshButton:SetScript("OnClick", function()
        refreshZones(true)
    end)

    local closeButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    closeButton:SetSize(90, 24)
    closeButton:SetPoint("BOTTOMRIGHT", -24, 18)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        panel:Hide()
    end)

    local panelCloseButton = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    panelCloseButton:SetPoint("TOPRIGHT", -4, -4)
end

function UI:OpenDungeonPriorityPanel()
    local ok, err = pcall(function()
        createPanel()
        refreshZones(true)

        if panel:IsShown() then
            panel:Hide()
        else
            panel:Show()
        end
    end)

    if not ok then
        printMsg("Failed to open dungeon priorities: " .. tostring(err))
        return false
    end

    return panel and panel:IsShown() or false
end
