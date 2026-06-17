local addon = SmartMark
addon.UI = addon.UI or {}

local UI = addon.UI

local panel

local function createPanel()
    if panel then
        return
    end

    panel = CreateFrame("Frame", "SmartMarkSettingsPanel", UIParent)
    panel:SetSize(480, 280)
    panel:SetPoint("CENTER")
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 11, top = 11, bottom = 11 },
    })
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("SmartMark Settings")

    local copy = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    copy:SetPoint("TOPLEFT", 24, -52)
    copy:SetJustifyH("LEFT")
    copy:SetText("UI scaffolding is ready. Full settings controls are next.")

    local closeButton = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -4, -4)
end

function UI:OpenConfig()
    createPanel()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end
