local addon = SmartMark
addon.UI = addon.UI or {}

local overlay = CreateFrame("Frame", "SmartMarkSessionOverlay", UIParent)
overlay:SetSize(260, 80)
overlay:SetPoint("CENTER", 0, 220)
overlay:Hide()

local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
text:SetPoint("CENTER")
text:SetText("SmartMark")

overlay.text = text
addon.UI.overlay = overlay

function addon.UI:UpdateOverlay(message)
    if not self.overlay then
        return
    end

    self.overlay.text:SetText(message or "SmartMark")
end
