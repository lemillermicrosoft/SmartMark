# SmartMark — Comprehensive Design Plan

A TBC Classic WoW addon for tanks that automates raid target marking during dungeon runs.

---

## Table of Contents

1. [Overview & Goals](#overview--goals)
2. [TBC Classic API Reference](#tbc-classic-api-reference)
3. [File Structure](#file-structure)
4. [Feature Specifications](#feature-specifications)
   - [Phase 1 — Core Marking (Mouseover Scrub)](#phase-1--core-marking-mouseover-scrub)
   - [Phase 2 — Smart Priority Assignment](#phase-2--smart-priority-assignment)
   - [Phase 3 — Config UI & Import/Export](#phase-3--config-ui--importexport)
5. [Data Models](#data-models)
6. [Core Algorithms](#core-algorithms)
7. [UI Design](#ui-design)
8. [Implementation Milestones](#implementation-milestones)
9. [Limitations & Considerations](#limitations--considerations)6. [Planned: Auto Pack Reset](#planned-auto-pack-reset)
7. [Planned: F-Key Mark Assignment Hotkeys](#planned-f-key-mark-assignment-hotkeys)
---

## Overview & Goals

SmartMark is a TBC Classic addon designed for a tank leveling through 5-man dungeons. The core workflow is:

1. Tank holds a modifier key combo (e.g. `Alt+Shift`) and **mouses over** a group of enemies.
2. The addon detects each new mouseover target while the keys are held and assigns a raid mark in real time.
3. As the tank scrubs over the pack, the addon **re-evaluates** the full group and promotes/demotes marks intelligently — kill order first, then CC assignments based on mob type or a user-populated mob database.

**Non-goals for now:** Automatic threat or aggro logic, party-wide notifications, or healer/DPS assistance features.

---

## TBC Classic API Reference

These are the key Blizzard APIs available in the 2.x (TBC Classic) client that this addon depends on.

### Raid Target Marks

| Index | Icon    | Common Use      |
|-------|---------|-----------------|
| 0     | (none)  | Remove mark     |
| 1     | ⭐ Star  | CC (Shackle / Trap) |
| 2     | 🔴 Circle | Kill 4 / Flex   |
| 3     | 💎 Diamond | CC (Banish/Fear) |
| 4     | 🔺 Triangle | CC (Sap)      |
| 5     | 🌙 Moon  | CC (Sheep)      |
| 6     | 🟦 Square | Kill 3         |
| 7     | ❌ Cross | Kill 2          |
| 8     | 💀 Skull | Kill 1          |

Default SmartMark convention (configurable):
- **Kill priority order:** Skull (8) → Cross (7) → Square (6) → Circle (2)
- **CC order:** Moon (5, Sheep) → Triangle (4, Sap) → Diamond (3, Banish/Fear) → Star (1, Shackle/Trap)

### Key API Functions

```lua
-- Mark assignment (requires raid leader/assist, or solo)
SetRaidTarget(unit, index)             -- index 0–8
GetRaidTargetIndex(unit)               -- returns 0–8 or nil

-- Mouseover unit inspection
UnitExists("mouseover")
UnitIsEnemy("player", "mouseover")
UnitIsDead("mouseover")
UnitName("mouseover")                  -- returns name, realm
UnitLevel("mouseover")
UnitClassification("mouseover")        -- "normal","elite","rare","rareelite","worldboss","trivial"
UnitCreatureType("mouseover")          -- "Beast","Humanoid","Undead","Demon","Elemental","Dragonkin",etc.
UnitGUID("mouseover")                  -- used to extract NPC ID

-- Modifier key state (polled; no event)
IsAltKeyDown()
IsShiftKeyDown()
IsControlKeyDown()

-- Group status
IsInRaid()
IsInGroup()
UnitIsGroupLeader("player")
UnitIsGroupAssistant("player")

-- Group composition / class scan
GetNumGroupMembers()
UnitClass("unit")
```

### NPC ID Extraction

GUID format: `"Creature-0-RRRR-ZZZZ-AAAA-NPCID-XXXXXXXX"`

```lua
local function GetNPCID(unit)
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" then
        return tonumber(npcID)
    end
    return nil
end
```

### Relevant Events

| Event                    | When it fires                                  |
|--------------------------|------------------------------------------------|
| `UPDATE_MOUSEOVER_UNIT`  | Mouse moves onto a new unit frame or 3D model  |
| `PLAYER_ENTERING_WORLD`  | Zone change / reload — use to reset session    |
| `PLAYER_REGEN_DISABLED`  | Combat starts — optional auto-disable scrub    |
| `COMBAT_LOG_EVENT_UNFILTERED` | Death detection for dead mobs           |

---

## File Structure

```
SmartMark/
├── SmartMark.toc               -- Addon metadata, file load order
├── SmartMark.lua               -- Bootstrap: namespace, SavedVariables init, slash commands
│
├── Core/
│   ├── EventHandler.lua        -- Register/handle all Blizzard events
│   ├── MarkManager.lua         -- Session state, mark assignment, scrub logic
│   ├── PriorityEngine.lua      -- Smart mark ordering algorithm
│   └── MobDatabase.lua         -- NPC ID → priority type lookups
│
├── Config/
│   ├── Defaults.lua            -- Default settings table
│   ├── Config.lua              -- Runtime config access (wraps SavedVariables)
│   └── ImportExport.lua        -- Serialize/deserialize mob database entries
│
├── UI/
│   ├── SettingsPanel.lua       -- Main options window (key combo, mark order, toggles)
│   ├── MobEditor.lua           -- Add/edit/remove mob database entries
│   └── SessionOverlay.lua      -- Optional minimal HUD showing current session marks
│
└── Libs/
    ├── LibStub.lua             -- Minimal LibStub for library versioning
    └── LibSerialize/           -- (Optional) compact table serialization for export strings
```

### TOC File (interface version 20504 for TBC Classic 2.5.4)

```
## Interface: 20504
## Title: SmartMark
## Notes: Smart raid mark assignment for TBC Classic tanks
## Author: YourName
## Version: 0.1.0
## SavedVariables: SmartMarkDB
## SavedVariablesPerCharacter: SmartMarkCharDB

Libs\LibStub.lua

SmartMark.lua
Core\EventHandler.lua
Core\MobDatabase.lua
Core\PriorityEngine.lua
Core\MarkManager.lua

Config\Defaults.lua
Config\Config.lua
Config\ImportExport.lua

UI\SettingsPanel.lua
UI\MobEditor.lua
UI\SessionOverlay.lua
```

---

## Feature Specifications

### Phase 1 — Core Marking (Mouseover Scrub)

**Goal:** Hold modifier keys → mouse over any hostile mob → it gets assigned the next available kill mark in sequence.

#### Activation Modes

Two modes, both configurable:

1. **Hold Mode (default):** Marking is active while `IsAltKeyDown() and IsShiftKeyDown()` (or user-configured combo) returns true. No marks are changed when keys are released.
2. **Toggle Mode:** Press the keybind once to enter marking mode, press again (or press Escape) to exit. Useful when the mouse needs to travel far.

The user can configure which modifier combination to check. Supported combos:
- `Alt+Shift` (default)
- `Ctrl+Shift`
- `Alt+Ctrl`
- Single keys: `Alt`, `Shift`, `Ctrl`

#### Scrub Session Lifecycle

```
Keys pressed / Toggle ON
        │
        ▼
  SESSION_START
  - Clear session mob list
  - Do NOT clear existing marks (allow additive scrubbing)
        │
        ▼ (UPDATE_MOUSEOVER_UNIT fires)
  For each new mouseover:
  - Is it a valid target? (enemy, alive, not already in session)
  - If yes → add to session mob list → trigger mark assignment
        │
        ▼
  Keys released / Toggle OFF
  SESSION_END
  - Run PriorityEngine reassignment over full session list
  - Finalize marks
```

#### Valid Target Check

A unit is eligible for marking if ALL of these are true:
- `UnitExists("mouseover")` is true
- `UnitIsEnemy("player", "mouseover")` is true
- `UnitIsDead("mouseover")` is false
- The unit's GUID is not already marked in the current session (deduplication)
- The unit does not already have a mark (unless `overwriteExistingMarks` config is true)

#### Immediate (Phase 1) Mark Assignment

In Phase 1, with no mob database, assignment is purely sequential:
- Maintain a `nextKillIndex` pointer into the kill mark list `{8, 7, 6, 2}` (Skull, X, Square, Circle)
- Each newly scrubbed mob gets `killMarks[nextKillIndex]` and the pointer advances
- When kill marks are exhausted, additional mobs are unmarked (or optionally cycle CC marks)
- A `/smartmark reset` slash command clears all marks and resets the session

---

### Phase 2 — Smart Priority Assignment

**Goal:** After the tank scrubs over a pack, reassign marks intelligently based on mob priority data.

#### Priority Types

Each mob entry in the database is classified as one of:

| Priority Type   | Assigned Mark  | Meaning                          |
|-----------------|----------------|----------------------------------|
| `kill1`         | Skull (8)      | Highest threat, kill first       |
| `kill2`         | Cross (7)      | Kill second                      |
| `kill3`         | Square (6)     | Kill third                       |
| `kill4`         | Circle (2)     | Kill fourth / flex kill          |
| `cc_sheep`      | Moon (5)       | Polymorph target                 |
| `cc_sap`        | Triangle (4)   | Sap target                       |
| `cc_banish`     | Diamond (3)    | Banish/Fear target               |
| `cc_shackle`    | Star (1)       | Shackle Undead target            |
| `cc_trap`       | Star (1)       | Hunter trap target (fallback)    |
| `skip`          | (none)         | Ignore entirely (e.g. totems)    |
| `auto`          | (computed)     | No explicit rule; use heuristics |

The user can **remap which mark goes to which priority type** in the settings UI, since group composition varies.

#### PriorityEngine Algorithm

This runs at `SESSION_END` (keys released) or in real time on each new addition (configurable):

```
Input:  sessionMobs[]  -- list of {guid, npcID, name, classification, creatureType}
Output: assignments{}  -- guid → markIndex

1. LOOKUP PHASE
   For each mob in sessionMobs:
     Look up npcID in MobDatabase → get priorityType
     If not found → set priorityType = "auto"

2. HEURISTIC PHASE (for "auto" mobs)
   Apply creature-type heuristics:
     Humanoid             → cc_sap (sappable) or kill
         Beast                → cc_trap (trappable) or kill
     Demon                → cc_banish
         Undead               → cc_shackle (if available) or kill
     Elemental            → cc_banish or kill
     Dragonkin            → kill
     elite classification → bump to higher kill priority

3. GROUP-COMP PHASE
     Scan party/raid classes and build `availableCC` set:
         MAGE    → sheep
         ROGUE   → sap
         WARLOCK → banish/fear
         PRIEST  → shackle
         HUNTER  → trap

     For each mob with CC priority:
         If that CC type is not available in the current group,
         downgrade mob to next valid action in order:
             explicit kill* in DB > alternative available CC > kill3

4. SORT & ASSIGN PHASE
   Separate into two lists:
     killList    = all mobs with kill* priority
     ccList      = all mobs with cc_* priority

   Sort killList by priority weight:
     kill1 > kill2 > kill3 > kill4 > auto_elite > auto_normal

   Sort ccList by CC type (user-configured preference order)

   Assign marks top-down:
     killList[1] → Skull, killList[2] → Cross, etc.
    ccList sorted by type → Moon, Triangle, Diamond, Star (as available)
     Overflow kills (beyond 4) → no mark or lowest available

5. APPLY PHASE
   For each assignment:
     If current mark on mob differs from desired → SetRaidTarget(guid_unit, mark)
     Track applied marks to avoid conflicts
```

#### Real-Time vs. Deferred Reassignment

- **Deferred (default):** Assignments only finalize when keys are released. During scrubbing, mobs get a temporary sequential mark so the tank has visual feedback. On release, marks are reshuffled to their smart positions.
- **Real-time:** Each new mob addition triggers a full reassignment immediately. More accurate but causes visible mark shuffling as you scrub.

Both are configurable via the settings panel.

#### Conflict Resolution

If two mobs in the session share the same desired mark:
- Higher-explicit-priority wins (e.g., two `kill1` database entries → first-scrubbed gets Skull, second gets Cross)
- Ties in the same priority level are broken by: explicit DB entry > elite classification > normal

---

### Phase 3 — Config UI & Import/Export

#### Settings Panel

Opened via `/smartmark config` or the standard Blizzard addon options interface.

Sections:
1. **Activation**
   - Modifier key combo picker (checkboxes: Alt, Shift, Ctrl)
   - Mode toggle: Hold vs. Toggle
   - Checkbox: "Disable in combat"
   - Checkbox: "Overwrite existing marks"
   - Checkbox: "Real-time vs. deferred reassignment"

2. **Mark Order**
    - Drag-and-drop (or up/down buttons) to reorder kill marks (Skull, X, Square, Circle)
   - Drag-and-drop to reorder CC marks
   - Re-map which priority type uses which mark (dropdowns)

3. **Mob Database**
   - Scrollable list of all user-defined mob entries
   - Each row: NPC ID | Mob Name | Priority Type | Source (user/imported)
   - Buttons: Add, Edit, Delete
   - "Add current target" button — populates from current `target` unit

4. **Import / Export**
   - Export: serializes entire mob database to a copyable string in a scrollable text box
   - Import: paste string into text box → validate → merge or replace

#### Mob Database Editor (per-entry)

Fields:
- **NPC ID** (auto-populated if added from target; or typed manually)
- **Mob Name** (cosmetic label only; NPC ID is the key)
- **Priority Type** (dropdown: kill1–kill4, cc_sheep, cc_sap, cc_banish, cc_shackle, cc_trap, skip)
- **Notes** (free text; e.g. "Mana Wyrm — interrupt arcane missiles")
- **Zone / Dungeon** (optional tag for filtering; e.g. "Hellfire Ramparts")

#### Import / Export Format

A human-readable, copy-pasteable string format. Uses a simple pipe/comma-delimited encoding to avoid JSON dependencies:

```
SMDB:1:28473,kill1,Watchkeeper Gargolmar,Hellfire Ramparts|17816,cc_sheep,Bonechewer Beastmaster,Hellfire Ramparts|...
```

Format: `SMDB:<version>:<entry1>|<entry2>|...`
Each entry: `<npcID>,<priorityType>,<mobName>,<zone>`

The `ImportExport.lua` module:
- `SmartMark.Export()` → returns the encoded string
- `SmartMark.Import(str, mode)` → parses and applies; `mode` is `"merge"` or `"replace"`
  - `"merge"` adds entries not already present, skips conflicts (default)
  - `"replace"` overwrites all existing user entries

Validation on import:
- Check prefix `SMDB:`
- Check version compatibility
- Validate each NPC ID is a positive integer
- Validate priority type is a known value
- Silently skip malformed entries, report count of skipped entries

---

## Data Models

### SavedVariables Structure (`SmartMarkDB`)

```lua
SmartMarkDB = {
    -- User settings
    settings = {
        modifierKeys = { alt = true, shift = true, ctrl = false },
        activationMode = "hold",         -- "hold" | "toggle"
        disableInCombat = false,
        overwriteExistingMarks = false,
        reassignmentMode = "deferred",   -- "deferred" | "realtime"
        markOrder = {
            kill  = { 8, 7, 6, 2 },      -- Skull, X, Square, Circle
            cc    = { 5, 4, 3, 1 },      -- Moon, Triangle, Diamond, Star
        },
        priorityToMark = {               -- user can remap these
            kill1    = 8,
            kill2    = 7,
            kill3    = 6,
            kill4    = 2,
            cc_sheep = 5,
            cc_sap   = 4,
            cc_banish = 3,
            cc_shackle = 1,
            cc_trap  = 1,
        },
        autoDetectGroupCC = true,
    },

    -- Mob database: keyed by NPC ID (as string for SavedVariables safety)
    mobs = {
        ["17816"] = {
            name         = "Bonechewer Beastmaster",
            priorityType = "cc_sheep",
            notes        = "",
            zone         = "Hellfire Ramparts",
            source       = "user",       -- "user" | "imported" | "builtin"
        },
        -- ...
    },

    -- Schema version for future migration
    dbVersion = 1,
}
```

### Per-Character SavedVariables (`SmartMarkCharDB`)

```lua
SmartMarkCharDB = {
    -- Toggle state persists across sessions if using toggle mode
    markingActive = false,
    -- Last session summary (optional, for debug/review)
    lastSession = {
        timestamp = 0,
        zone      = "",
        marks     = {},   -- { [guid] = markIndex }
    },
}
```

### In-Memory Session State (not saved)

```lua
SmartMark.session = {
    active    = false,
    mobs      = {},    -- array of mob info tables, in scrub order
    guidIndex = {},    -- [guid] = position in mobs array (dedup lookup)
    marks     = {},    -- [guid] = currently assigned mark index
}
```

### Mob Info Table (per scrubbed unit)

```lua
{
    guid           = "Creature-0-...",
    npcID          = 17816,
    name           = "Bonechewer Beastmaster",
    level          = 61,
    classification = "normal",   -- from UnitClassification
    creatureType   = "Beast",    -- from UnitCreatureType
    scrubOrder     = 1,          -- order in which it was scrubbed
    priorityType   = "cc_sheep", -- resolved by PriorityEngine
    assignedMark   = 4,          -- final mark index
}
```

---

## Core Algorithms

### EventHandler.lua Skeleton

```lua
local frame = CreateFrame("Frame")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "UPDATE_MOUSEOVER_UNIT" then
        MarkManager:OnMouseoverUpdate()
    elseif event == "PLAYER_ENTERING_WORLD" then
        MarkManager:ResetSession()
    elseif event == "PLAYER_REGEN_DISABLED" then
        if Config:Get("disableInCombat") then
            MarkManager:DeactivateSession()
        end
    end
end)
```

### MarkManager:OnMouseoverUpdate()

```lua
function MarkManager:OnMouseoverUpdate()
    -- Gate: is marking mode active?
    if not self:IsMarkingActive() then return end

    -- Gate: is the mouseover a valid enemy?
    if not UnitExists("mouseover") then return end
    if not UnitIsEnemy("player", "mouseover") then return end
    if UnitIsDead("mouseover") then return end

    local guid = UnitGUID("mouseover")
    if not guid then return end

    -- Deduplication
    if self.session.guidIndex[guid] then return end

    -- Build mob info record
    local mobInfo = {
        guid           = guid,
        npcID          = GetNPCID("mouseover"),
        name           = UnitName("mouseover"),
        level          = UnitLevel("mouseover"),
        classification = UnitClassification("mouseover"),
        creatureType   = UnitCreatureType("mouseover"),
        scrubOrder     = #self.session.mobs + 1,
    }

    table.insert(self.session.mobs, mobInfo)
    self.session.guidIndex[guid] = #self.session.mobs

    -- Immediate visual feedback: assign next sequential mark
    self:AssignTemporaryMark(mobInfo)

    -- If real-time mode, re-run full priority engine now
    if Config:Get("reassignmentMode") == "realtime" then
        PriorityEngine:Reassign(self.session)
    end
end
```

### IsMarkingActive() — Hold Mode

```lua
function MarkManager:IsMarkingActive()
    if not self.session.active then return false end
    if Config:Get("activationMode") == "hold" then
        local keys = Config:Get("modifierKeys")
        local altOk   = (not keys.alt)   or IsAltKeyDown()
        local shiftOk = (not keys.shift) or IsShiftKeyDown()
        local ctrlOk  = (not keys.ctrl)  or IsControlKeyDown()
        return altOk and shiftOk and ctrlOk
    end
    return true  -- toggle mode: active flag is the gate
end
```

**Note:** Since `UPDATE_MOUSEOVER_UNIT` is the trigger, we poll modifier state at event time. This naturally gives "hold to mark" behavior without any separate key-down/key-up event tracking.

To start the session: use a keybinding (defined via `SetBinding` or a `/click` macro on a hidden button) that calls `MarkManager:StartSession()`. In Hold Mode, `StartSession()` just sets `session.active = true` — it will self-deactivate when modifier keys aren't down. Alternatively, the session activates automatically on first mouseover with correct modifiers held.

### PriorityEngine:Reassign(session)

```lua
function PriorityEngine:Reassign(session)
    local killList, ccList = {}, {}

    for _, mob in ipairs(session.mobs) do
        -- 1. Database lookup
        local entry = MobDatabase:Lookup(mob.npcID)
        if entry then
            mob.priorityType = entry.priorityType
        else
            -- 2. Heuristic fallback
            mob.priorityType = self:Heuristic(mob)
        end

        if mob.priorityType:sub(1, 4) == "kill" then
            table.insert(killList, mob)
        elseif mob.priorityType == "skip" then
            -- do nothing
        else
            table.insert(ccList, mob)
        end
    end

    -- 3. Sort kill list
    local killWeight = { kill1 = 1, kill2 = 2, kill3 = 3, kill4 = 4, auto_elite = 5, auto = 6 }
    table.sort(killList, function(a, b)
        local wa = killWeight[a.priorityType] or 99
        local wb = killWeight[b.priorityType] or 99
        if wa ~= wb then return wa < wb end
        return a.scrubOrder < b.scrubOrder  -- tiebreak: first scrubbed
    end)

    -- 4. Sort CC list by type preference
    local ccOrder = Config:Get("markOrder").cc   -- e.g. {4,3,2,1}
    local ccTypeOrder = {}
    for i, mark in ipairs(ccOrder) do
        ccTypeOrder[mark] = i
    end
    table.sort(ccList, function(a, b)
        local pa = ccTypeOrder[Config:Get("priorityToMark")[a.priorityType]] or 99
        local pb = ccTypeOrder[Config:Get("priorityToMark")[b.priorityType]] or 99
        if pa ~= pb then return pa < pb end
        return a.scrubOrder < b.scrubOrder
    end)

    -- 5. Assign marks
    local killMarks = Config:Get("markOrder").kill
    local ccMarkMap = Config:Get("priorityToMark")

    for i, mob in ipairs(killList) do
        mob.assignedMark = killMarks[i]  -- nil if overflow
    end
    for _, mob in ipairs(ccList) do
        mob.assignedMark = ccMarkMap[mob.priorityType]
    end

    -- 6. Apply to game (handle unit re-identification)
    self:ApplyMarks(session)
end
```

### PriorityEngine:Heuristic(mob)

```lua
function PriorityEngine:Heuristic(mob)
    -- Creature type → CC suggestion
    local ccByType = {
        Humanoid  = "cc_sap",
        Beast     = "cc_trap",
        Demon     = "cc_banish",
        Elemental = "cc_banish",
        Undead    = "cc_shackle",
    }
    local cc = ccByType[mob.creatureType]
    if cc then return cc end

    -- Elites bump to kill1 candidate, normals are generic kill
    if mob.classification == "elite" or mob.classification == "rareelite" then
        return "kill1"
    end

    return "auto"  -- treated as kill, lowest priority
end
```

### Group Composition Awareness

Before final mark assignment, SmartMark scans the current group and builds an availability map of CC types.

```lua
function PriorityEngine:BuildAvailableCC()
    local available = {
        cc_sheep = false,
        cc_sap = false,
        cc_banish = false,
        cc_shackle = false,
        cc_trap = false,
    }

    local function applyUnit(unit)
        if not UnitExists(unit) then return end
        local _, class = UnitClass(unit)
        if class == "MAGE" then available.cc_sheep = true end
        if class == "ROGUE" then available.cc_sap = true end
        if class == "WARLOCK" then available.cc_banish = true end
        if class == "PRIEST" then available.cc_shackle = true end
        if class == "HUNTER" then available.cc_trap = true end
    end

    applyUnit("player")

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            applyUnit("raid" .. i)
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            applyUnit("party" .. i)
        end
    end

    return available
end
```

If a mob is tagged with unavailable CC (example: `cc_sheep` and no Mage), the engine downgrades that mob to another available CC type or to a kill priority based on DB rule preference.

### ApplyMarks — Unit Re-identification

`SetRaidTarget` requires a live unit token, not a GUID. Between the time a mob was scrubbed and when we apply marks (especially in deferred mode), the unit token `"mouseover"` no longer points to it. We need to find the current unit token for each GUID.

Strategy:
1. Iterate `"nameplate1"` through `"nameplate40"` — nameplates are the most reliable way to reach nearby enemies by GUID in TBC Classic.
2. Fall back to checking `"target"`, `"focus"`, and party/raid targets.

```lua
function PriorityEngine:FindUnitByGUID(guid)
    -- Check nameplates first
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit) and UnitGUID(unit) == guid then
            return unit
        end
    end
    -- Fallback checks
    for _, unit in ipairs({"target", "focus", "mouseover"}) do
        if UnitExists(unit) and UnitGUID(unit) == guid then
            return unit
        end
    end
    return nil
end
```

**Important:** If no unit token is found for a GUID, the mark cannot be applied until the unit comes into range of a nameplate or is targeted. The addon should queue failed applications and retry on `UPDATE_MOUSEOVER_UNIT` and `NAME_PLATE_UNIT_ADDED` events.

---

## UI Design

### Settings Panel

- Opened via `/sm config` or `/smartmark config`
- Uses standard Blizzard `InterfaceOptions` frame registration OR a standalone draggable frame (standalone preferred for TBC Classic, since the Blizzard options API has limitations)
- Tab-based layout: **General | Mark Order | Mob Database | Import/Export**

### Session Overlay (optional HUD)

A small framelet that appears while marking is active showing:
```
[ SmartMark — Marking Active ]
  💀 Bonechewer Beastmaster
  ❌ Bonechewer Ravager
  🔺 Bonechewer Beastmaster (2)
```
Shows current session marks in a compact list. Fades out when marking deactivates. Fully optional, can be disabled in settings.

### Mob Editor Flow

1. User clicks "Add Mob" → small popup with fields (NPC ID, Name, Priority Type, Zone, Notes)
2. "Add Current Target" button populates NPC ID + Name from `UnitGUID("target")` automatically
3. "Add Mouseover" button populates from the mouseover unit
4. Submit validates NPC ID is numeric and priority type is valid
5. Saved to `SmartMarkDB.mobs`

---

## Implementation Milestones

### Current Status Snapshot (2026-07-02)

- Core addon scaffold is implemented and loadable via `SmartMark.toc`.
- Core scrub-mark loop works (hold/toggle session, mouseover capture, temporary marks, deferred/realtime reassignment).
- Clear-marks keybind exists with retry sweeps for delayed token availability.
- Settings panel is functional for core toggles/modes/modifier keys, including auto-reset toggle.
- Import/export module is implemented with slash commands and an in-game import/export window.
- Mark application retry queue implemented via `NAME_PLATE_UNIT_ADDED` — queued marks apply as units re-enter nameplate range.
- Auto pack reset implemented: all tracked mobs dying fires `ResetSession` automatically.
- F-key quick-assign bindings implemented (`Ctrl+Alt+F1`–`F8`) with configurable priority mapping.
- Overwrite-existing-marks bug fixed: reassignment no longer force-resets manually placed marks.
- Remaining high-priority work: mob database curation, full mob editor CRUD UI, mark remapping UI, F-key remapping dropdowns in Settings Panel.

### Milestone 1 — Skeleton & Core Loop

- [x] `SmartMark.toc` with correct interface version
- [x] `SmartMark.lua` namespace setup (`SmartMark = {}`)
- [x] `Config/Defaults.lua` with full default settings table
- [x] `Config/Config.lua` with `Get`/`Set` wrappers around `SmartMarkDB`
- [x] `Core/EventHandler.lua` registering `UPDATE_MOUSEOVER_UNIT`
- [x] `Core/MarkManager.lua` with session start/stop and sequential mark assignment
- [x] Slash commands: `/sm reset`, `/sm start`, `/sm stop`, `/sm config`
- [x] **Deliverable:** Hold Alt+Shift, mouse over mobs, they get Skull/X/Square/Circle in order

### Milestone 2 — Smart Priority Engine

- [x] `Core/MobDatabase.lua` with lookup by NPC ID
- [x] `Core/PriorityEngine.lua` with heuristic + DB-based assignment
- [x] Deferred reassignment on session end (keys released)
- [x] GUID → unit token resolution via nameplates
- [x] Mark application retry queue for out-of-range units (`NAME_PLATE_UNIT_ADDED` + `PriorityEngine.pendingMarks`)
- [x] **Deliverable:** Mixed pack of Humanoids/Beasts/Demons auto-sorted into kill + CC marks

### Milestone 3 — Configuration UI

- [~] `UI/SettingsPanel.lua` — standalone frame, modifier key picker, mode toggles, auto-reset toggle (functional; tabs and F-key remapping dropdowns still pending)
- [ ] `UI/MobEditor.lua` — scrollable list + add/edit/delete + "Add from Target" shortcut
- [ ] Mark order remapping UI
- [x] F-key quick-assign bindings (`Bindings.xml` + 8 global stubs in `SmartMark.lua` + `fKeyPriorityMap` defaults)
- [ ] 8-dropdown F-Key Quick Assign section in Settings Panel
- [ ] **Deliverable:** Fully configurable via in-game UI, no config file editing needed

### Milestone 4 — Import/Export

- [x] `Config/ImportExport.lua` — encoder/decoder for `SMDB:` format
- [x] Import UI panel with merge/replace options and validation feedback
- [x] Export panel with "Select All + Copy" instruction
- [x] **Deliverable:** Share mob databases between players via copy-paste strings

### Milestone 5 — Polish & Dungeon Data

- [ ] Populate initial mob database with TBC Classic dungeon mobs (based on your research)
- [x] Session overlay HUD
- [x] `NAME_PLATE_UNIT_ADDED` retry for deferred mark failures
- [x] Combat state handling (disable in combat option)
- [x] `/sm status` command showing current session mobs and marks
- [x] Auto pack reset on all-mobs-dead (`COMBAT_LOG_EVENT_UNFILTERED` → `UNIT_DIED` tracking)
- [x] `autoResetOnPackDeath` and `autoResetMinMobs` settings + Settings Panel checkbox
- [ ] **Deliverable:** Ready-to-use addon with practical dungeon data

---

## Planned: Auto Pack Reset

### Problem

After a tank kills a pack, the session still holds the previous mobs and their marks. Starting the next pack requires manually clearing marks and restarting the session via `/sm reset`, which breaks flow.

### Goal

Automatically detect when all mobs in the current session have died, clear their marks, and reset the session state — so scrubbing the next pack works immediately without any user action.

### Detection Strategy

WoW TBC Classic does not fire a single "all tracked mobs are dead" event. The approach is to hook `COMBAT_LOG_EVENT_UNFILTERED` and track UNIT_DIED events for GUIDs in the active session.

```lua
-- EventHandler registers:
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

-- Handler:
if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    local _, subEvent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    if subEvent == "UNIT_DIED" then
        MarkManager:OnUnitDied(destGUID)
    end
end
```

`MarkManager:OnUnitDied(guid)` implementation:

```lua
function MarkManager:OnUnitDied(guid)
    if not self.session or not self.session.guidIndex[guid] then
        return  -- not a mob we're tracking
    end

    self.session.deadCount = (self.session.deadCount or 0) + 1

    local total = #self.session.mobs
    if self.session.deadCount >= total and total > 0 then
        -- All tracked mobs are confirmed dead: clear and reset
        self:ResetSession(true)  -- clears marks and sets deferred retry
        addon.Print("Pack cleared — session reset.")
    end
end
```

### Considerations

- **Minimum mob threshold:** Only auto-reset if the session tracked at least 2 mobs. A single-mob kill (e.g. pulling one stray) should not reset. Make this threshold configurable: `autoResetMinMobs` (default: `2`).
- **Skip mobs:** Mobs with `priorityType == "skip"` do not increment `deadCount` nor count toward the total, so they cannot block auto-reset.
- **In-session death during scrub:** If a mob dies before scrubbing is complete (e.g. AoE nuke during hold), it still counts. The remaining live mobs will eventually die and trigger reset normally.
- **False positives:** `UNIT_DIED` fires for player deaths and pet deaths too — the GUID check against `session.guidIndex` guards against this.
- **Settings:** Add a toggle `autoResetOnPackDeath` (default: `true`) so players can disable auto-reset if they prefer manual control.

### Data Model Additions

New fields in `SmartMarkDB.settings`:

```lua
autoResetOnPackDeath = true,
autoResetMinMobs     = 2,
```

New field in the in-memory session state:

```lua
deadCount = 0,  -- incremented each time a tracked GUID dies
```

### Settings Panel Addition

Under **Behavior** section:
- Checkbox: `"Auto-reset session when all tracked mobs die"` → `autoResetOnPackDeath`
- Number input / slider: `"Minimum mobs for auto-reset"` (1–8) → `autoResetMinMobs`

### Milestone Placement

This belongs in **Milestone 5 — Polish**. It depends on the core session loop (Milestone 1) and the settings panel (Milestone 3).

---

## Planned: F-Key Mark Assignment Hotkeys

### Problem

Many WoW players use F1–F8 to manually set raid marks during play. SmartMark should allow the user to quickly reconfigure which mark gets assigned to a specific priority type by pressing a key combo (e.g. Ctrl+Alt+F1 sets Skull as the kill1 mark, Ctrl+Alt+F5 sets Moon, etc.).

### Goal

Provide 8 keybindings — `Ctrl+Alt+F1` through `Ctrl+Alt+F8` — that the user can remap in the standard WoW Keybindings UI. When pressed, the binding cycles or directly assigns the corresponding raid icon to the "currently focused" priority slot, driven by what the user last had selected in a simple in-game picker.

### WoW Raid Icon Index ↔ F-Key Default Mapping

The default pairing mirrors the conventional F-key → icon convention used by many guilds:

| Keybind         | Raid Icon Index | Icon       | Default Priority |
|-----------------|-----------------|------------|------------------|
| Ctrl+Alt+F1     | 1               | ⭐ Star     | cc_shackle / cc_trap |
| Ctrl+Alt+F2     | 2               | 🔴 Circle  | kill4            |
| Ctrl+Alt+F3     | 3               | 💎 Diamond | cc_banish        |
| Ctrl+Alt+F4     | 4               | 🔺 Triangle| cc_sap           |
| Ctrl+Alt+F5     | 5               | 🌙 Moon    | cc_sheep         |
| Ctrl+Alt+F6     | 6               | 🟦 Square  | kill3            |
| Ctrl+Alt+F7     | 7               | ❌ Cross   | kill2            |
| Ctrl+Alt+F8     | 8               | 💀 Skull   | kill1            |

### Binding Behavior

Each binding does **not** directly set a mark on a unit. Instead, it **remaps the priority → mark assignment** for one priority type:

- The user selects which priority type is the "target" via the Settings Panel (a dropdown: `kill1`, `kill2`, `cc_sheep`, etc.) — this is the "assignment target".
- Pressing `Ctrl+Alt+F5` (for example) sets `priorityToMark[selectedPriorityType] = 5`.
- A chat confirmation is printed: `SmartMark: kill1 is now marked with Moon (5).`

Alternatively (simpler UX): each F-key is hardwired to one priority type in the default mapping above, and pressing it just toggles the mark for that slot to the corresponding index. No picker needed.

**Recommended approach (hardwired defaults + user remappable in Settings):**
1. Bindings call named global functions `SmartMark_SetMarkF1()` … `SmartMark_SetMarkF8()`.
2. Each function sets `priorityToMark[defaultPriorityForKey] = iconIndex`.
3. The user can reassign which priority type each F-key controls from the Settings Panel.

### Bindings.xml Additions

```xml
<Binding name="SMARTMARK_MARK_F1" header="SMARTMARK" default="CTRL-ALT-F1">
    SmartMark_SetMarkF1()
</Binding>
<Binding name="SMARTMARK_MARK_F2" header="SMARTMARK" default="CTRL-ALT-F2">
    SmartMark_SetMarkF2()
</Binding>
<!-- ... F3 through F8 ... -->
<Binding name="SMARTMARK_MARK_F8" header="SMARTMARK" default="CTRL-ALT-F8">
    SmartMark_SetMarkF8()
</Binding>
```

### SmartMark.lua Global Stubs

```lua
-- These globals are invoked by the Bindings system.
-- defaultFKeyPriority is stored in settings as `fKeyPriorityMap`.
for i = 1, 8 do
    _G["SmartMark_SetMarkF" .. i] = function()
        local priority = addon.Config:Get("fKeyPriorityMap.f" .. i)
        if not priority then return end
        addon.Config:Set("priorityToMark." .. priority, i)
        addon.Print(priority .. " remapped to mark index " .. i)
    end
end
```

### Data Model Additions

New field in `SmartMarkDB.settings`:

```lua
fKeyPriorityMap = {
    f1 = "cc_shackle",   -- Star
    f2 = "kill4",        -- Circle
    f3 = "cc_banish",    -- Diamond
    f4 = "cc_sap",       -- Triangle
    f5 = "cc_sheep",     -- Moon
    f6 = "kill3",        -- Square
    f7 = "kill2",        -- Cross
    f8 = "kill1",        -- Skull
},
```

### Settings Panel Addition

Under a new sub-section **"F-Key Quick Assign"**:
- 8 dropdowns, one per F-key slot (F1–F8).
- Each dropdown contains all priority types (`kill1`–`kill4`, `cc_sheep`, `cc_sap`, `cc_banish`, `cc_shackle`, `cc_trap`, `skip`).
- Changing a dropdown updates `fKeyPriorityMap.fN`.
- Label format: `Ctrl+Alt+F1 → [dropdown]`

### Milestone Placement

This belongs in **Milestone 3 — Configuration UI**, since it requires both `Bindings.xml` entries and a Settings Panel section. The global stub functions live in `SmartMark.lua`.

---

## Limitations & Considerations

### Raid Permission Requirements

`SetRaidTarget()` can only be called by:
- The player when **solo**
- The **raid/party leader**
- A **raid assistant**

When in a group without leader/assist, marking will silently fail. The addon should detect this at session end and print a warning: `"SmartMark: You need lead or assist to set marks."`. Check via `UnitIsGroupLeader("player")` and `UnitIsGroupAssistant("player")`.

### Nameplate Range

Nameplates only exist for units within ~40 yards. If the tank is in a position where a scrubbed mob has moved out of nameplate range (rare in dungeons, but possible), the mark cannot be applied until the mob re-enters range. The retry queue handles this.

### Mod Key Polling vs. Events

WoW's event system does not fire an event when modifier keys are pressed or released in isolation. Modifier state is only available by polling (`IsAltKeyDown()` etc.). This means Hold Mode only works by checking modifier state at the moment `UPDATE_MOUSEOVER_UNIT` fires. There is no way to detect "user lifted their fingers" except by detecting it on the next mouseover event. To handle this gracefully:
- In Hold Mode, check modifier state on each mouseover event; session state follows naturally.
- A separate `OnUpdate` throttle (e.g., every 0.1s) can check if modifier keys were released and auto-deactivate the session to trigger PriorityEngine reassignment.

### TBC Classic vs. Retail API

This addon targets **TBC Classic (Interface 20504)**. Several modern APIs (`C_NamePlate`, `C_RaidTarget`, etc.) are **not available**. All code must use the classic-compatible flat function API (`SetRaidTarget`, `GetRaidTargetIndex`, nameplate unit tokens `"nameplate1"` through `"nameplate40"`).

### "Skip" Mob Types

Some mobs should never be marked (totem units, players, etc.). The addon should filter:
- `UnitPlayerControlled("mouseover")` → skip
- `UnitIsUnit("mouseover", "player")` → skip
- Mob names containing known totem patterns (optional, fragile — DB-level `skip` type is more robust)

### Performance

`UPDATE_MOUSEOVER_UNIT` fires very frequently during rapid mousing. The handler must be lightweight:
- GUID dedup check is O(1) via hash table
- All expensive work (PriorityEngine) is deferred to session end
- No string formatting or UI updates in the hot path
