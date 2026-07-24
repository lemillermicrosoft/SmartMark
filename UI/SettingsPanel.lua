local addon = SmartMark
addon.UI = addon.UI or {}

local UI = addon.UI

local panel
local controls = {}
local checkboxCounter = 0

local function setConfig(path, value)
    if addon.Config then
        addon.Config:Set(path, value)
    end
end

local function getConfig(path)
    if addon.Config then
        return addon.Config:Get(path)
    end
    return nil
end

local function createCheckButton(parent, label, x, y, path)
    checkboxCounter = checkboxCounter + 1
    local name = "SmartMarkSettingsCheck" .. checkboxCounter
    local checkbox = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", x, y)

    local text = checkbox.Text or _G[name .. "Text"]
    if not text then
        text = checkbox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        text:SetPoint("LEFT", checkbox, "RIGHT", 2, 1)
    end
    text:SetText(label)

    checkbox:SetScript("OnClick", function(self)
        setConfig(path, self:GetChecked() and true or false)
    end)
    return checkbox
end

local function createDropdown(parent, width, x, y, values, onSelect)
    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", x, y)
    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_Initialize(dropdown, function(self)
        for _, row in ipairs(values) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = row.label
            info.value = row.value
            info.func = function()
                UIDropDownMenu_SetSelectedValue(self, row.value)
                onSelect(row.value)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    return dropdown
end

local function refreshControls()
    if not panel then
        return
    end

    controls.alt:SetChecked(getConfig("modifierKeys.alt"))
    controls.shift:SetChecked(getConfig("modifierKeys.shift"))
    controls.ctrl:SetChecked(getConfig("modifierKeys.ctrl"))

    controls.disableCombat:SetChecked(getConfig("disableInCombat"))
    controls.overwrite:SetChecked(getConfig("overwriteExistingMarks"))
    controls.autoCC:SetChecked(getConfig("autoDetectGroupCC"))
    controls.autoReset:SetChecked(getConfig("autoResetOnPackDeath"))

    local activation = getConfig("activationMode")
    UIDropDownMenu_SetSelectedValue(controls.activationMode, activation)
    UIDropDownMenu_SetText(controls.activationMode, activation == "toggle" and "Toggle" or "Hold")

    local reassignment = getConfig("reassignmentMode")
    UIDropDownMenu_SetSelectedValue(controls.reassignmentMode, reassignment)
    UIDropDownMenu_SetText(controls.reassignmentMode, reassignment == "realtime" and "Real-time" or "Deferred")
end

local function createPanel()
    if panel then
        return
    end

    local frameTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
    panel = CreateFrame("Frame", "SmartMarkSettingsPanel", UIParent, frameTemplate)
    panel:SetSize(560, 450)
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
    title:SetText("SmartMark Settings")

    local modifierHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    modifierHeader:SetPoint("TOPLEFT", 26, -50)
    modifierHeader:SetText("Modifier Keys (Hold Mode)")

    controls.alt = createCheckButton(panel, "Alt", 26, -76, "modifierKeys.alt")
    controls.shift = createCheckButton(panel, "Shift", 26, -104, "modifierKeys.shift")
    controls.ctrl = createCheckButton(panel, "Ctrl", 26, -132, "modifierKeys.ctrl")

    local activationHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    activationHeader:SetPoint("TOPLEFT", 290, -50)
    activationHeader:SetText("Activation")

    local activationLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    activationLabel:SetPoint("TOPLEFT", 290, -76)
    activationLabel:SetText("Mode")

    controls.activationMode = createDropdown(panel, 130, 280, -94, {
        { label = "Hold", value = "hold" },
        { label = "Toggle", value = "toggle" },
    }, function(value)
        setConfig("activationMode", value)
    end)

    local reassignmentLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    reassignmentLabel:SetPoint("TOPLEFT", 290, -136)
    reassignmentLabel:SetText("Reassignment")

    controls.reassignmentMode = createDropdown(panel, 130, 280, -154, {
        { label = "Deferred", value = "deferred" },
        { label = "Real-time", value = "realtime" },
    }, function(value)
        setConfig("reassignmentMode", value)
    end)

    local behaviorHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    behaviorHeader:SetPoint("TOPLEFT", 26, -192)
    behaviorHeader:SetText("Behavior")

    controls.disableCombat = createCheckButton(panel, "Disable while in combat", 26, -218, "disableInCombat")
    controls.overwrite = createCheckButton(panel, "Overwrite existing marks", 26, -246, "overwriteExistingMarks")
    controls.autoCC = createCheckButton(panel, "Auto-detect available group CC", 26, -274, "autoDetectGroupCC")
    controls.autoReset = createCheckButton(panel, "Auto-reset session when all tracked mobs die", 26, -302, "autoResetOnPackDeath")

    local helper = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helper:SetPoint("TOPLEFT", 26, -342)
    helper:SetJustifyH("LEFT")
    helper:SetText("Tip: Use /sm export to copy your mob DB, and /sm import merge|replace SMDB:1:...")

    local importExportButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    importExportButton:SetSize(120, 24)
    importExportButton:SetPoint("TOPLEFT", 26, -376)
    importExportButton:SetText("Import/Export")
    importExportButton:SetScript("OnClick", function()
        if addon.UI and addon.UI.OpenMobEditor then
            addon.UI:OpenMobEditor()
        end
    end)

    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(120, 24)
    resetButton:SetPoint("BOTTOMLEFT", 24, 18)
    resetButton:SetText("Reset Session")
    resetButton:SetScript("OnClick", function()
        if addon.MarkManager then
            local cleared = addon.MarkManager:ResetSession(true) or 0
            addon.Print("Session reset. Cleared marks: " .. tostring(cleared))
        end
    end)

    local closeTextButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    closeTextButton:SetSize(120, 24)
    closeTextButton:SetPoint("BOTTOMRIGHT", -24, 18)
    closeTextButton:SetText("Close")
    closeTextButton:SetScript("OnClick", function()
        panel:Hide()
    end)

    local closeButton = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -4, -4)
end

function UI:OpenConfig()
    local ok, err = pcall(function()
        createPanel()
        if panel:IsShown() then
            panel:Hide()
        else
            refreshControls()
            panel:Show()
        end
    end)

    if not ok then
        if addon.Print then
            addon.Print("Failed to open settings: " .. tostring(err))
        end
        return false
    end

    return panel and panel:IsShown() or false
end
