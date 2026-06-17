# Research Task: TBC Classic Dungeon & Raid Mob Database

## Context

You are building a data file for a World of Warcraft: The Burning Crusade Classic addon called **SmartMark**. This addon helps a tank automatically assign raid target marks to groups of enemies during dungeon runs. Your job is to research every non-boss mob in TBC Classic dungeons and raids and classify each one according to the schema below.

The output will be imported directly into the addon, so formatting precision is critical.

---

## What You Need to Research

### Scope

Cover all trash mobs (non-boss enemies) in every **TBC Classic 5-man dungeon** and, as a secondary priority, **TBC Classic raids**. Bosses should be excluded — they are never marked with raid targets during normal play.

**5-man Dungeons (primary — cover all of these):**

| Dungeon                  | Abbreviation | Min Level | Heroic? |
|--------------------------|--------------|-----------|---------|
| Hellfire Ramparts        | HFR          | 60        | Yes     |
| The Blood Furnace        | BF           | 61        | Yes     |
| The Shattered Halls      | SH           | 70        | Yes     |
| The Slave Pens           | SP           | 62        | Yes     |
| The Underbog             | UB           | 63        | Yes     |
| The Steamvault           | SV           | 70        | Yes     |
| Mana-Tombs               | MT           | 64        | Yes     |
| Auchenai Crypts          | AC           | 65        | Yes     |
| Sethekk Halls            | SetH         | 67        | Yes     |
| Shadow Labyrinth         | SLab         | 70        | Yes     |
| Old Hillsbrad Foothills  | OHF          | 66        | Yes     |
| The Black Morass         | BM           | 68        | Yes     |
| The Mechanar             | Mech         | 69        | Yes     |
| The Botanica             | Bot          | 70        | Yes     |
| The Arcatraz             | Arc          | 70        | Yes     |
| Magisters' Terrace       | MgT          | 70        | Yes     |

**Raids (secondary — cover if time allows):**
- Karazhan
- Gruul's Lair
- Magtheridon's Lair
- Serpentshrine Cavern
- Tempest Keep: The Eye
- Black Temple
- Mount Hyjal
- Zul'Aman
- Sunwell Plateau

---

## Data You Must Find Per Mob

For each non-boss trash mob, find:

1. **NPC ID** — The numeric identifier used by the game server. This is the most critical field. Can be found on Wowhead (TBC Classic version: `tbc.wowhead.com`), WoWDB, or similar database sites. The NPC ID appears in the URL of the mob's page, e.g. `tbc.wowhead.com/npc=17816/bonechewer-beastmaster` → NPC ID is `17816`.

2. **Mob Name** — The exact in-game display name. Include spaces and apostrophes exactly as they appear.

3. **Priority Type** — The classification for how the addon should handle this mob. See the Priority Type Reference below.

4. **Dungeon/Zone** — The full dungeon name (not abbreviation) where this mob appears.

5. **Notes** (optional but encouraged) — Any information useful to the player: key abilities that make the mob dangerous or desirable to CC, interrupt targets, etc. Keep notes under 80 characters. Examples:
   - `"Casts Arcane Missiles — interrupt"`
   - `"Enrages at 20% health"`
   - `"Fear on pull — sap before engaging"`

---

## Priority Type Reference

Assign exactly one of the following values to each mob:

| Priority Type | Mark Used  | Meaning & When to Use                                                                 |
|---------------|------------|---------------------------------------------------------------------------------------|
| `kill1`       | Skull      | Highest danger: caster with burst damage, healer, enrager, or has a critical interrupt target. Kill immediately. |
| `kill2`       | Cross      | High-priority kill: dangerous melee or secondary caster. Kill after skull.           |
| `kill3`       | Square     | Standard kill target — moderate threat, no CC available or not worth CCing.          |
| `kill4`       | Moon       | Low-priority kill: low damage, slow, or easy to kite. Kill last.                     |
| `cc_sheep`    | Triangle   | Should be Polymorphed (Mage). Mob must be a **Humanoid** or **Beast** or **Critter**. |
| `cc_trap`     | Diamond    | Should be Freezing Trapped (Hunter). Mob must be a **Beast** or **Dragonkin**.       |
| `cc_banish`   | Circle     | Should be Banished (Warlock). Mob must be a **Demon** or **Elemental**.              |
| `cc_sap`      | Star       | Should be Sapped (Rogue). Mob must be a **Humanoid** (and sap only works out of combat). |
| `cc_shackle`  | (extended) | Should be Shackled (Priest). Mob must be **Undead**.                                 |
| `cc_hibernate`| (extended) | Should be Hibernated (Druid). Mob must be a **Beast** or **Dragonkin**.              |
| `skip`        | (none)     | Never mark — totems, pets, low-health throwaway adds, or mobs that die to AoE instantly. |

**Priority type selection rules:**

- A mob's creature type constrains which CC types are valid. Do not assign `cc_sheep` to a Demon.
- If a mob *can* be CC'd but is more dangerous left alive (e.g., a healer), prefer `kill1` or `kill2` over CC.
- If multiple CC types are valid, choose the one most commonly available in a typical 5-man group. Sheep (`cc_sheep`) > Trap (`cc_trap`) > Banish (`cc_banish`) > Sap (`cc_sap`) as a general preference hierarchy when in doubt.
- If a mob is in a dungeon room with only 1–2 pulls and is low-damage, `kill3` or `kill4` is fine even if technically sheepable.
- Mark mob-spawned adds (like totems) as `skip`.

**Creature type quick reference** (for CC eligibility):

| Creature Type | Valid CC Types                            |
|---------------|-------------------------------------------|
| Humanoid      | cc_sheep, cc_sap                          |
| Beast         | cc_sheep, cc_trap, cc_hibernate           |
| Demon         | cc_banish                                 |
| Elemental     | cc_banish                                 |
| Undead        | cc_shackle (not sheepable, not sapable)   |
| Dragonkin     | cc_trap, cc_hibernate                     |
| Giant         | (no standard CC — kill)                   |
| Mechanical    | (no standard CC — kill)                   |

---

## Output Format

Produce your output in two forms: a **Lua table block** and an **SMDB import string**. Both must cover the same set of mobs.

### Form 1: Lua Table (primary)

Output a single Lua table named `SmartMark_BuiltinDB` containing one entry per mob:

```lua
SmartMark_BuiltinDB = {
    -- =========================================================
    -- Hellfire Ramparts
    -- =========================================================
    [17816] = {
        name         = "Bonechewer Beastmaster",
        priorityType = "cc_trap",
        zone         = "Hellfire Ramparts",
        notes        = "Hunter trap. Enrages — bring it down quickly after.",
        source       = "builtin",
    },
    [17805] = {
        name         = "Hellfire Sentry",
        priorityType = "kill2",
        zone         = "Hellfire Ramparts",
        notes        = "Ranged attacker. Pull with LoS to stack on melee.",
        source       = "builtin",
    },
    -- =========================================================
    -- The Blood Furnace
    -- =========================================================
    [17281] = {
        name         = "Laughing Skull Enforcer",
        priorityType = "kill1",
        zone         = "The Blood Furnace",
        notes        = "Hamstring + Mortal Strike. Interrupt Sunder.",
        source       = "builtin",
    },
    -- ... (continue for all dungeons)
}
```

Rules for the Lua table:
- Group entries by dungeon using the comment header `-- ===...=== / -- DungeonName` pattern shown above.
- Within each dungeon group, sort entries by `priorityType` in this order: `kill1`, `kill2`, `kill3`, `kill4`, `cc_sheep`, `cc_trap`, `cc_banish`, `cc_sap`, `cc_shackle`, `cc_hibernate`, `skip`.
- The key is always the numeric NPC ID in brackets: `[17816]`.
- All string values must use double quotes.
- `source` is always the literal string `"builtin"`.
- If `notes` is genuinely unknown or not applicable, use an empty string `""`.
- Do not include boss mobs.
- Do not include mobs that are only found outside of instanced dungeons.

### Form 2: SMDB Import String (secondary)

After the Lua table, output a plain-text SMDB import string covering the same mobs. This is a compact format for in-game import.

Format: `SMDB:1:<entry1>|<entry2>|...`

Each entry: `<npcID>,<priorityType>,<mobName>,<zone>`

- Fields are comma-separated. The mob name and zone must **not** contain commas — if they do, replace the comma with a semicolon.
- Entries are pipe `|` separated.
- No newlines within the string — it must be one continuous line.
- Example:

```
SMDB:1:17816,cc_trap,Bonechewer Beastmaster,Hellfire Ramparts|17805,kill2,Hellfire Sentry,Hellfire Ramparts|17281,kill1,Laughing Skull Enforcer,The Blood Furnace
```

---

## Research Sources

Use the following sources (in order of preference):

1. **tbc.wowhead.com** — Most comprehensive. Each mob's page shows its NPC ID in the URL, its creature type, and player comments about its abilities.
   - Example URL: `https://tbc.wowhead.com/npc=17816/bonechewer-beastmaster`
   - Use the **"Comments"** section on Wowhead to find notes about dangerous abilities, CC suitability, and pull tips from experienced players.
   - The dungeon's own Wowhead page lists all mobs found there.

2. **Classic.wowhead.com zone/dungeon pages** — Each dungeon zone page lists all NPCs found there via the "NPCs" tab.

3. **wowpedia.org** — Good for dungeon overview pages that describe mob composition and abilities.

4. **YouTube "TBC Classic [dungeon name] guide" videos** — Useful for CC recommendations from experienced tanks/guides.

**How to find NPC IDs efficiently:**
- Navigate to `https://tbc.wowhead.com/zone=3562` (replace the zone ID) to list all NPCs in a dungeon.
- Alternatively search `https://tbc.wowhead.com/npcs/name:bonechewer` to find mobs by name.
- The numeric ID in the URL (`/npc=XXXXX/`) is the NPC ID you need.

---

## Quality Standards

- **NPC ID accuracy is mandatory.** An incorrect NPC ID will cause the wrong mob to be marked in-game. Double-check by verifying the mob's name matches the NPC page at that ID.
- If you cannot find the NPC ID for a mob with confidence, **omit that mob entirely** rather than guessing. Note omissions at the end of your output.
- If a mob appears in multiple dungeons (e.g., reused NPC IDs in heroic vs. normal share the same ID), include it only once using the lowest-level dungeon as the zone.
- Prioritize completeness over perfect priority classification. An entry with a rough classification is more useful than a missing entry.
- Flag any mobs where you are uncertain about the priority type with a note like `notes = "UNCERTAIN: may be kill2 instead"`.

---

## Output Structure

Return your complete output in this order:

1. A summary table (Markdown) listing how many mobs were found per dungeon.
2. The full `SmartMark_BuiltinDB` Lua table.
3. The full SMDB import string.
4. A list of any mobs that were omitted due to missing NPC IDs, with the mob name and dungeon.
5. Any general notes about mob populations you found surprising or worth flagging for manual review.
