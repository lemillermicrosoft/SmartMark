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
9. [Limitations & Considerations](#limitations--considerations)

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
| 1     | ⭐ Star  | Kill 4 / Sap    |
| 2     | 🔴 Circle | CC (Banish/Fear) |
| 3     | 💎 Diamond | CC (Trap)      |
| 4     | 🔺 Triangle | CC (Sheep)   |
| 5     | 🌙 Moon  | Kill 4 / overflow |
| 6     | 🟦 Square | Kill 3         |
| 7     | ❌ Cross | Kill 2          |
| 8     | 💀 Skull | Kill 1          |

Default SmartMark convention (configurable):
- **Kill priority order:** Skull (8) → Cross (7) → Square (6) → Moon (5)
- **CC order:** Triangle (4, Sheep) → Diamond (3, Trap) → Circle (2, Banish) → Star (1, Sap)

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
- Maintain a `nextKillIndex` pointer into the kill mark list `{8, 7, 6, 5}` (Skull, X, Square, Moon)
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
| `kill4`         | Moon (5)       | Kill fourth                      |
| `cc_sheep`      | Triangle (4)   | Polymorph target                 |
| `cc_trap`       | Diamond (3)    | Hunter trap target               |
| `cc_banish`     | Circle (2)     | Banish/Fear target               |
| `cc_sap`        | Star (1)       | Sap target                       |
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
     Beast                → cc_trap (trappable)
     Demon                → cc_banish
     Undead               → (not sheepable, not sapable) → kill
     Elemental            → cc_banish or kill
     Dragonkin            → kill
     elite classification → bump to higher kill priority

3. SORT & ASSIGN PHASE
   Separate into two lists:
     killList    = all mobs with kill* priority
     ccList      = all mobs with cc_* priority

   Sort killList by priority weight:
     kill1 > kill2 > kill3 > kill4 > auto_elite > auto_normal

   Sort ccList by CC type (user-configured preference order)

   Assign marks top-down:
     killList[1] → Skull, killList[2] → Cross, etc.
     ccList sorted by type → Triangle, Diamond, Circle, Star (as available)
     Overflow kills (beyond 4) → no mark or lowest available

4. APPLY PHASE
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
   - Drag-and-drop (or up/down buttons) to reorder kill marks (Skull, X, Square, Moon)
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
- **Priority Type** (dropdown: kill1–kill4, cc_sheep, cc_trap, cc_banish, cc_sap, skip)
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
            kill  = { 8, 7, 6, 5 },      -- Skull, X, Square, Moon
            cc    = { 4, 3, 2, 1 },      -- Triangle, Diamond, Circle, Star
        },
        priorityToMark = {               -- user can remap these
            kill1    = 8,
            kill2    = 7,
            kill3    = 6,
            kill4    = 5,
            cc_sheep = 4,
            cc_trap  = 3,
            cc_banish = 2,
            cc_sap   = 1,
        },
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

### Milestone 1 — Skeleton & Core Loop

- [ ] `SmartMark.toc` with correct interface version
- [ ] `SmartMark.lua` namespace setup (`SmartMark = {}`)
- [ ] `Config/Defaults.lua` with full default settings table
- [ ] `Config/Config.lua` with `Get`/`Set` wrappers around `SmartMarkDB`
- [ ] `Core/EventHandler.lua` registering `UPDATE_MOUSEOVER_UNIT`
- [ ] `Core/MarkManager.lua` with session start/stop and sequential mark assignment
- [ ] Slash commands: `/sm reset`, `/sm start`, `/sm stop`, `/sm config`
- [ ] **Deliverable:** Hold Alt+Shift, mouse over mobs, they get Skull/X/Square/Moon in order

### Milestone 2 — Smart Priority Engine

- [ ] `Core/MobDatabase.lua` with lookup by NPC ID
- [ ] `Core/PriorityEngine.lua` with heuristic + DB-based assignment
- [ ] Deferred reassignment on session end (keys released)
- [ ] GUID → unit token resolution via nameplates
- [ ] Mark application retry queue for out-of-range units
- [ ] **Deliverable:** Mixed pack of Humanoids/Beasts/Demons auto-sorted into kill + CC marks

### Milestone 3 — Configuration UI

- [ ] `UI/SettingsPanel.lua` — standalone frame, tabs, modifier key picker, mode toggles
- [ ] `UI/MobEditor.lua` — scrollable list + add/edit/delete + "Add from Target" shortcut
- [ ] Mark order remapping UI
- [ ] **Deliverable:** Fully configurable via in-game UI, no config file editing needed

### Milestone 4 — Import/Export

- [ ] `Config/ImportExport.lua` — encoder/decoder for `SMDB:` format
- [ ] Import UI panel with merge/replace options and validation feedback
- [ ] Export panel with "Select All + Copy" instruction
- [ ] **Deliverable:** Share mob databases between players via copy-paste strings

### Milestone 5 — Polish & Dungeon Data

- [ ] Populate initial mob database with TBC Classic dungeon mobs (based on your research)
- [ ] Session overlay HUD
- [ ] `NAME_PLATE_UNIT_ADDED` retry for deferred mark failures
- [ ] Combat state handling (disable in combat option)
- [ ] `/sm status` command showing current session mobs and marks
- [ ] **Deliverable:** Ready-to-use addon with practical dungeon data

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
