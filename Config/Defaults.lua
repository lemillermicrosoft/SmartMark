local addon = SmartMark
addon.Defaults = addon.Defaults or {}

addon.Defaults.DB = {
    dbVersion = 1,
    settings = {
        modifierKeys = { alt = true, shift = true, ctrl = false },
        activationMode = "hold", -- hold | toggle
        disableInCombat = false,
        overwriteExistingMarks = false,
        reassignmentMode = "deferred", -- deferred | realtime
        autoDetectGroupCC = true,
        markOrder = {
            kill = { 8, 7, 6, 2 },
            cc = { 5, 4, 3, 1 },
        },
        priorityToMark = {
            kill1 = 8,
            kill2 = 7,
            kill3 = 6,
            kill4 = 2,
            cc_sheep = 5,
            cc_sap = 4,
            cc_banish = 3,
            cc_shackle = 1,
            cc_trap = 1,
        },
    },
    mobs = {},
}

addon.Defaults.CharDB = {
    markingActive = false,
    lastSession = {
        timestamp = 0,
        zone = "",
        marks = {},
    },
}
