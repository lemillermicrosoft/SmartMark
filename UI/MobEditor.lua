local addon = SmartMark
addon.UI = addon.UI or {}

local frame
local editBox

local function createWindow()
    if frame then
        return
    end

    local frameTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "SmartMarkImportExportFrame", UIParent, frameTemplate)
    frame:SetSize(700, 420)
    frame:SetPoint("CENTER")
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 11, top = 11, bottom = 11 },
        })
    end
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("SmartMark Import / Export")

    local helpText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", 20, -46)
    helpText:SetText("Paste SMDB:1:... strings below. Use Export to generate one from your local DB.")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -70)
    scroll:SetPoint("BOTTOMRIGHT", -42, 58)

    editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(620)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnTextChanged", function(self)
        local _, lines = self:GetText():gsub("\n", "\n")
        self:SetHeight(math.max(260, (lines + 1) * 14 + 8))
    end)
    scroll:SetScrollChild(editBox)

    local exportButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportButton:SetSize(110, 24)
    exportButton:SetPoint("BOTTOMLEFT", 20, 20)
    exportButton:SetText("Export")
    exportButton:SetScript("OnClick", function()
        if not addon.ImportExport then
            addon.Print("Import/export module unavailable")
            return
        end
        local data = addon.ImportExport:Export()
        editBox:SetText(data)
        editBox:HighlightText(0, -1)
        editBox:SetFocus()
        addon.Print("Exported database into text box")
    end)

    local importMergeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importMergeButton:SetSize(130, 24)
    importMergeButton:SetPoint("LEFT", exportButton, "RIGHT", 10, 0)
    importMergeButton:SetText("Import (Merge)")
    importMergeButton:SetScript("OnClick", function()
        if not addon.ImportExport then
            addon.Print("Import/export module unavailable")
            return
        end
        local ok, result = addon.ImportExport:Import(editBox:GetText() or "", "merge")
        if ok then
            addon.Print(result)
        else
            addon.Print("Import failed: " .. tostring(result))
        end
    end)

    local importReplaceButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importReplaceButton:SetSize(140, 24)
    importReplaceButton:SetPoint("LEFT", importMergeButton, "RIGHT", 10, 0)
    importReplaceButton:SetText("Import (Replace)")
    importReplaceButton:SetScript("OnClick", function()
        if not addon.ImportExport then
            addon.Print("Import/export module unavailable")
            return
        end
        local ok, result = addon.ImportExport:Import(editBox:GetText() or "", "replace")
        if ok then
            addon.Print(result)
        else
            addon.Print("Import failed: " .. tostring(result))
        end
    end)

    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetSize(90, 24)
    clearButton:SetPoint("LEFT", importReplaceButton, "RIGHT", 10, 0)
    clearButton:SetText("Clear")
    clearButton:SetScript("OnClick", function()
        editBox:SetText("")
    end)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(90, 24)
    closeButton:SetPoint("BOTTOMRIGHT", -20, 20)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local panelCloseButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    panelCloseButton:SetPoint("TOPRIGHT", -4, -4)
end

function addon.UI:OpenMobEditor()
    createWindow()
    frame:Show()
end
