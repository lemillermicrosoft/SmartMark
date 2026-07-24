local addon = SmartMark
addon.UI = addon.UI or {}

local frameTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
local overlay = CreateFrame("Frame", "SmartMarkSessionOverlay", UIParent, frameTemplate)
overlay:SetSize(320, 88)
overlay:SetPoint("CENTER", 0, 220)
if overlay.SetBackdrop then
    overlay:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if overlay.SetBackdropColor then
        overlay:SetBackdropColor(0, 0, 0, 0.75)
    end
end
overlay:Hide()

local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
text:SetPoint("CENTER")
text:SetJustifyH("LEFT")
text:SetText("SmartMark")

overlay.text = text
addon.UI.overlay = overlay

function addon.UI:UpdateOverlay(message)
    if not self.overlay then
        return
    end

    self.overlay.text:SetText(message or "SmartMark")
end

function addon.UI:SetOverlayActive(active)
    if not self.overlay then
        return
    end

    if active then
        self.overlay:Show()
    else
        self.overlay:Hide()
    end
end
