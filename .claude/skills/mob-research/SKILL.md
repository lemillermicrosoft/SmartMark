# TBC Mob Research and Builtin DB Workflow

## Overview

Use this skill to rebuild or refresh SmartMark's TBC dungeon mob database from web sources, generate both research artifacts and addon-ready Lua data, and safely merge builtin entries into runtime defaults.

This workflow was proven in SmartMark and is optimized for:

- high NPC ID accuracy
- repeatable generation from local source snapshots
- explicit handling of known source gaps

## When to use this skill

Use this skill when the user asks to:

- research TBC dungeon trash mobs
- regenerate RESEARCH_OUTPUT.md
- create or update Config/BuiltinMobDB.lua
- improve priority classification quality
- backfill missing dungeon data from secondary sources

## Inputs and outputs

Inputs:

- saved Wowhead zone HTML snapshots in .tmp/wowhead/zone_<zoneId>.html
- secondary source mob names for exceptional dungeons
- verified NPC IDs from Wowhead search and NPC pages

Primary outputs:

- RESEARCH_OUTPUT.md
- Config/BuiltinMobDB.lua

Supporting code:

- tools/generate_research_output.ps1
- Config/Config.lua (merge builtin data into SavedVariables)
- SmartMark.toc (load order includes Config/BuiltinMobDB.lua)

## Canonical priority schema (important)

SmartMark has migrated from legacy kill1/kill2/kill3/kill4 to a canonical model:

- priorityType = kill
- killRank = numeric ordering (lower means higher kill priority)

CC and non-kill priorities remain explicit:

- cc_sheep
- cc_sap
- cc_banish
- cc_shackle
- cc_trap
- skip
- auto

Compatibility behavior currently in addon:

- legacy kill1-4 inputs are still accepted by slash/import paths
- they are normalized to priorityType = kill with default ranks
- default legacy mapping:
  - kill1 -> killRank 10
  - kill2 -> killRank 20
  - kill3 -> killRank 30
  - kill4 -> killRank 40

Treat kill1-4 as migration-only aliases, not the target output format.

## Core lessons learned

1. Wowhead zone pages can be parsed from embedded Listview NPC payloads.
2. Zone IDs are easy to mis-map; always verify by reading each HTML page <title>.
3. Two dungeons are special cases in this dataset path:
   - Old Hillsbrad Foothills
   - Magisters' Terrace
   Their saved zone/filter pages may expose bosses only.
4. Hostile filtering must use reaction flags and boss flags, not name matching alone.
5. Search-result ID extraction must be spot-verified against direct NPC page titles before trusting.
6. Keep explicit manual supplemental entries for known source gaps.
7. Research/generator output must emit canonical kill plus killRank, not legacy kill1-4.

## Zone ID mapping used

Use this verified mapping for TBC 5-man coverage:

- 3562 Hellfire Ramparts
- 3713 The Blood Furnace
- 3714 The Shattered Halls
- 3715 The Steamvault
- 3716 The Underbog
- 3717 The Slave Pens
- 3792 Mana-Tombs
- 3790 Auchenai Crypts
- 3791 Sethekk Halls
- 3789 Shadow Labyrinth
- 2367 Old Hillsbrad Foothills
- 2366 The Black Morass
- 3849 The Mechanar
- 3847 The Botanica
- 3848 The Arcatraz
- 4131 Magisters' Terrace

## Proven workflow

1. Collect source pages

- Download all required zone pages into .tmp/wowhead.
- Confirm presence for all 16 dungeon zone IDs.

2. Validate mapping from page titles

- Parse each saved file title:
  - <title>... - Zone - TBC Classic</title>
- Correct any mistaken zone->dungeon assumptions before extracting mobs.

3. Extract NPC rows from embedded Listview data

- Preferred pattern:
  - new Listview({template: 'npc', id: 'npcs', ... data: [...]});
- Alternate filter page pattern exists and differs.

4. Filter to hostile non-boss trash

Apply all filters:

- row has name
- row is not boss
- row location includes the target zone ID
- row react includes -1 (hostile)

5. Handle known gaps with manual supplemental entries

- For Old Hillsbrad and Magisters' Terrace, backfill from secondary sources.
- Resolve IDs with Wowhead search:
  - https://www.wowhead.com/tbc/search?q=<mob name>
- Spot-verify critical IDs via direct NPC pages:
  - https://www.wowhead.com/tbc/npc=<id>
  - confirm page title matches mob name

6. Classify priority and notes

- Use deterministic rules in generator.
- Prefer lower killRank values for healers and dangerous casters.
- Avoid over-defaulting to CC for high-risk caster mobs.
- Keep notes short and practical.

Recommended rank bands:

- 10: critical kill target (old kill1)
- 20: high-priority secondary (old kill2)
- 30: standard kill target (old kill3)
- 40: low-priority kill target (old kill4)

7. Deduplicate NPC IDs

- Keep only one record per NPC ID.
- Follow lowest-level dungeon preference when duplicates exist.

8. Generate artifacts

- Write RESEARCH_OUTPUT.md with:
  - summary table
  - SmartMark_BuiltinDB block
  - SMDB import string
  - omissions
  - general notes
- Write Config/BuiltinMobDB.lua for addon runtime use.

Canonical output requirement for generated entries:

- for kill entries, write:
  - priorityType = kill
  - killRank = <number>
- for CC/skip/auto entries:
  - priorityType = cc_* or skip or auto
  - killRank may be omitted unless explicitly needed

9. Merge builtin data safely at startup

In Config:Initialize:

- if addon.BuiltinMobDB exists, copy entries into SmartMarkDB.mobs only when missing
- do not overwrite existing user/imported entries

10. Validate final result

- script runs without errors
- RESEARCH_OUTPUT includes non-zero counts for all expected covered dungeons
- omissions section is accurate
- generated Lua file parses
- TOC includes Config/BuiltinMobDB.lua before Config/Defaults.lua and Config/Config.lua load usage
- generated kill entries use priorityType = kill with numeric killRank
- no new research output defaults to legacy kill1-4

## SmartMark-specific implementation notes

Generator script:

- tools/generate_research_output.ps1

Generated runtime data:

- Config/BuiltinMobDB.lua

Config merge point:

- Config/Config.lua in Config:Initialize()
  - normalizes legacy kill1-4 to kill
  - backfills killRank defaults for migrated rows

Import/export migration behavior:

- Config/ImportExport.lua accepts legacy kill1-4, converts to kill plus default rank

Runtime ranking behavior:

- Core/PriorityEngine.lua sorts kill list by killRank first (lower first), then fallback weight/order

UI editing behavior:

- UI/DungeonPriorityPanel.lua exposes priority dropdown plus explicit rank input

TOC load order requirement:

- SmartMark.toc must include Config/BuiltinMobDB.lua

## Known pitfalls and mitigations

1. Pitfall: using wrong zone ID labels.
Mitigation: derive labels from saved page titles, not memory.

2. Pitfall: including friendly NPCs, escorts, or ambient units.
Mitigation: require hostile react flag and zone-local location.

3. Pitfall: filter pages with different Listview shape.
Mitigation: support alternate regex path in parser.

4. Pitfall: incorrect IDs from search ambiguity.
Mitigation: verify direct NPC page title for selected critical entries.

5. Pitfall: stale omissions after manual backfill.
Mitigation: compute omissions after considering manual entries for each zone.

6. Pitfall: polluting user data with forced overrides.
Mitigation: merge builtin entries only when key is absent.

7. Pitfall: generating legacy kill1-4 in new data files.
Mitigation: emit kill plus killRank in generator and research artifacts; keep legacy forms only for import compatibility.

## Suggested command sequence

Run from repo root:

```powershell
& '.\tools\generate_research_output.ps1'
```

Quick checks:

```powershell
Select-String -Path '.\RESEARCH_OUTPUT.md' -Pattern "Old Hillsbrad Foothills|Magisters' Terrace|## Omitted|- None"
```

```powershell
Get-Content '.\Config\BuiltinMobDB.lua' -First 80
```

Verify canonical kill model in generated DB:

```powershell
Select-String -Path '.\Config\BuiltinMobDB.lua' -Pattern 'priorityType\s*=\s*"kill"|killRank\s*=' | Select-Object -First 40
```

Check for accidental legacy kill types in generated DB:

```powershell
Select-String -Path '.\Config\BuiltinMobDB.lua' -Pattern 'priorityType\s*=\s*"kill[1-4]"'
```

## Data quality policy

- If an NPC ID cannot be verified confidently, omit it.
- Prefer explicit uncertainty notes over silent guessing.
- Prioritize ID correctness over perfect priority tuning.
- Keep manual supplemental entries small, documented, and reviewable.
- Keep kill ranking consistent and explicit so pull order is deterministic.

## Future improvements

- Replace regex extraction with a more structured parser if source format changes.
- Add optional per-entry provenance tags (zone page, manual supplement, verified search).
- Add a strict validation mode that checks sampled IDs against live NPC page titles automatically.
- Update generator to emit canonical kill plus killRank directly in both markdown sample table and Config/BuiltinMobDB.lua.
