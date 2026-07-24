Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $repoRoot '.tmp\wowhead'
$outputPath = Join-Path $repoRoot 'RESEARCH_OUTPUT_RAIDS.md'
$raidOutputPath = Join-Path $repoRoot 'Config\RaidMobDB.lua'

$raidZoneSpecs = @(
    [pscustomobject]@{ Id = 3457; Name = 'Karazhan';              MinLevel = 70 },
    [pscustomobject]@{ Id = 3923; Name = "Gruul's Lair";          MinLevel = 70 },
    [pscustomobject]@{ Id = 3836; Name = "Magtheridon's Lair";    MinLevel = 70 },
    [pscustomobject]@{ Id = 3607; Name = 'Serpentshrine Cavern';  MinLevel = 70 },
    [pscustomobject]@{ Id = 3845; Name = 'Tempest Keep';          MinLevel = 70 },
    [pscustomobject]@{ Id = 3606; Name = 'Hyjal Summit';          MinLevel = 70 },
    [pscustomobject]@{ Id = 3959; Name = 'Black Temple';          MinLevel = 70 },
    [pscustomobject]@{ Id = 3805; Name = "Zul'Aman";              MinLevel = 70 },
    [pscustomobject]@{ Id = 4075; Name = 'Sunwell Plateau';       MinLevel = 70 }
)

$typeMap = @{
    1 = 'Beast'; 2 = 'Dragonkin'; 3 = 'Demon'; 4 = 'Elemental'
    5 = 'Giant'; 6 = 'Undead';    7 = 'Humanoid'; 8 = 'Critter'; 9 = 'Mechanical'
}

# Numeric sort rank: lower = higher kill priority.
# kill10=10, kill20=20, kill30=30, kill40=40
# cc types sorted after all kill entries.
$ccSortRank = @{
    cc_shackle = 50; cc_banish = 55; cc_trap = 60; cc_sheep = 65; cc_sap = 70; skip = 90
}

function Get-RaidNotes {
    param([string]$Name)

    $patterns = @(
        @{ Regex = 'Healer|Priest|Physician|Soulpriest';           Note = 'Healer. Kill or interrupt immediately.' },
        @{ Regex = 'Channeler|Ritualist';                          Note = 'Interrupt to prevent buffs or adds.' },
        @{ Regex = 'Summoner';                                     Note = 'Summons adds. Kill fast.' },
        @{ Regex = 'Necromancer|Necrolyte';                        Note = 'Undead caster. Interrupt reanimation/raises.' },
        @{ Regex = 'Warlock|Darkcaster|Shadowmage|Shadowstalker'; Note = 'Dangerous shadow caster. Interrupt.' },
        @{ Regex = 'Astromancer|Astromage';                        Note = 'Arcane caster. CC or kill before pull spreads.' },
        @{ Regex = 'Sorcerer|Sorceress|Spellbinder';               Note = 'Caster pressure. Interrupt when possible.' },
        @{ Regex = 'Nexus-Stalker|Assassin|Infiltrator';           Note = 'Stealthed opener. Assign dedicated pickup.' },
        @{ Regex = 'Archer|Rifleman|Sharpshooter';                 Note = 'Ranged. LOS pull or kill early.' },
        @{ Regex = 'Abomination';                                  Note = 'Cleave and disease AoE. Tank away from raid.' },
        @{ Regex = 'Infernal';                                     Note = 'Wave mob. Kite or burst down quickly.' },
        @{ Regex = 'Gargoyle';                                     Note = 'Flying wave mob. Assign ranged kill.' },
        @{ Regex = 'Fel Stalker|Felstalker';                       Note = 'High-threat demon. Kill or banish.' },
        @{ Regex = 'Coilskar|Naga|Siren';                          Note = 'Naga trash. Watch fear/sleep auras.' },
        @{ Regex = 'Warlord|Commander|General|Captain';            Note = 'Leader mob. Auras or patrol buffs. Kill fast.' },
        @{ Regex = 'Illidari';                                     Note = 'Illidari elite. High melee threat.' },
        @{ Regex = 'Ashtongue';                                    Note = 'Broken mob. Mixed physical and caster roles.' }
    )

    foreach ($entry in $patterns) {
        if ($Name -match $entry.Regex) { return $entry.Note }
    }
    return ''
}

function Get-RaidPriority {
    param([string]$Name, [string]$CreatureType)

    # Skip critters and trivial adds
    if ($CreatureType -eq 'Critter') { return @{ Type = 'skip'; Rank = $null } }
    if ($Name -match '^(Bat|Rat|Frog|Venom Web Spider|Fire Beetle|Frenzied Bat)$') {
        return @{ Type = 'skip'; Rank = $null }
    }

    # Rank 10: critical kill — healers, summoners, buff-channelers
    if ($Name -match 'Healer|Priest|Physician|Soulpriest|Channeler|Ritualist|Summoner|Necromancer|Necrolyte') {
        return @{ Type = 'kill'; Rank = 10 }
    }
    if ($Name -match 'Warlock|Darkcaster|Shadowmage') {
        return @{ Type = 'kill'; Rank = 10 }
    }

    # Rank 20: high priority — dangerous casters, stealthers, ranged
    if ($Name -match 'Sorcerer|Sorceress|Astromancer|Astromage|Spellbinder|Geomancer|Oracle|Prophet|Shaman') {
        return @{ Type = 'kill'; Rank = 20 }
    }
    if ($Name -match 'Nexus-Stalker|Assassin|Infiltrator|Shadowstalker') {
        return @{ Type = 'kill'; Rank = 20 }
    }
    if ($Name -match 'Archer|Rifleman|Sharpshooter') {
        return @{ Type = 'kill'; Rank = 20 }
    }

    # Event/scripted mobs that should not be marked
    if ($Name -match ' Spirit$| Shade$| Echo$| Illusion$| Image$') {
        return @{ Type = 'skip'; Rank = $null }
    }

    # CC-appropriate types for groups that CC in raids
    switch ($CreatureType) {
        'Undead'    { return @{ Type = 'cc_shackle'; Rank = $null } }
        'Demon'     { return @{ Type = 'cc_banish';  Rank = $null } }
        'Elemental' { return @{ Type = 'cc_banish';  Rank = $null } }
        'Beast'     { return @{ Type = 'cc_trap';    Rank = $null } }
    }

    # Rank 30: standard kill target (humanoids and everything else)
    return @{ Type = 'kill'; Rank = 30 }
}

function Escape-LuaString {
    param([AllowEmptyString()][string]$Value)
    return ($Value -replace '\\', '\\\\' -replace '"', '\\"')
}

function Get-EmbeddedNpcRows {
    param([string]$HtmlPath, [int]$ZoneId)

    if (-not (Test-Path $HtmlPath)) { return @() }
    $raw = Get-Content -Raw $HtmlPath

    $match = [regex]::Match(
        $raw,
        "new Listview\(\{template: 'npc', id: 'npcs'.*?data: \[(.*?)\]\}\);",
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    if (-not $match.Success) {
        $match = [regex]::Match(
            $raw,
            'new Listview\((\{"sort".*?"template":"npc".*?"data":\[.*?\]\})\);',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        if (-not $match.Success) { return @() }
        return @($match.Groups[1].Value | ConvertFrom-Json)
    }

    $json = '[' + $match.Groups[1].Value + ']'
    return @($json | ConvertFrom-Json)
}

function Is-HostileTrash {
    param($Row, [int]$ZoneId)

    if (-not $Row.PSObject.Properties['name'] -or -not $Row.name) { return $false }
    if ($Row.PSObject.Properties['boss'] -and $Row.boss -eq 1) { return $false }
    if (-not $Row.PSObject.Properties['location']) { return $false }
    if (@($Row.location) -notcontains $ZoneId) { return $false }
    if (-not $Row.PSObject.Properties['react']) { return $false }
    if (@($Row.react) -notcontains -1) { return $false }
    return $true
}

$records = New-Object System.Collections.Generic.List[object]
$omissions = New-Object System.Collections.Generic.List[string]

foreach ($zone in $raidZoneSpecs) {
    $htmlPath = Join-Path $sourceDir ("zone_{0}.html" -f $zone.Id)
    $rows = Get-EmbeddedNpcRows -HtmlPath $htmlPath -ZoneId $zone.Id
    $hostileRows = @($rows | Where-Object { Is-HostileTrash -Row $_ -ZoneId $zone.Id })

    if ($hostileRows.Count -eq 0) {
        $omissions.Add("$($zone.Name): no hostile trash NPCs exposed in saved Wowhead page.")
        continue
    }

    foreach ($row in $hostileRows) {
        $creatureType = ''
        if ($null -ne $row.PSObject.Properties['type'] -and $typeMap.ContainsKey([int]$row.type)) {
            $creatureType = $typeMap[[int]$row.type]
        }

        $prio = Get-RaidPriority -Name ([string]$row.name) -CreatureType ([string]$creatureType)

        $records.Add([pscustomobject]@{
            NpcId        = [int]$row.id
            Name         = [string]$row.name
            Zone         = [string]$zone.Name
            ZoneId       = [int]$zone.Id
            MinLevel     = [int]$zone.MinLevel
            CreatureType = [string]$creatureType
            PriorityType = $prio.Type
            KillRank     = $prio.Rank
            Notes        = Get-RaidNotes -Name ([string]$row.name)
        })
    }
}

# Deduplicate: keep first occurrence per NpcId (lowest ZoneId wins)
$deduped = $records |
    Sort-Object ZoneId, NpcId |
    Group-Object NpcId |
    ForEach-Object { $_.Group | Select-Object -First 1 }

# Sort key: kill entries by KillRank, CC/skip entries by type rank
function Get-SortKey { param($r)
    if ($r.PriorityType -eq 'kill') { return [int]$r.KillRank }
    if ($ccSortRank.ContainsKey($r.PriorityType)) { return $ccSortRank[$r.PriorityType] }
    return 99
}

# Build Lua output for RaidMobDB.lua
$raidLuaLines = New-Object System.Collections.Generic.List[string]
$raidLuaLines.Add('local addon = SmartMark')
$raidLuaLines.Add('addon.RaidMobDB = {')

# Build summary table and Lua code block for RESEARCH_OUTPUT_RAIDS.md
$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add('| Raid | Mobs Found |')
$summaryLines.Add('| --- | ---: |')

$mdLuaLines = New-Object System.Collections.Generic.List[string]
$mdLuaLines.Add('```lua')
$mdLuaLines.Add('SmartMark_RaidDB = {')

foreach ($zone in $raidZoneSpecs) {
    $zoneRecords = @(
        $deduped |
        Where-Object Zone -eq $zone.Name |
        Sort-Object @{ Expression = { Get-SortKey $_ } }, Name, NpcId
    )
    $summaryLines.Add("| $($zone.Name) | $($zoneRecords.Count) |")

    if ($zoneRecords.Count -eq 0) { continue }

    $mdLuaLines.Add('    -- =========================================================')
    $mdLuaLines.Add("    -- $($zone.Name)")
    $mdLuaLines.Add('    -- =========================================================')

    $raidLuaLines.Add("    -- =========================================================")
    $raidLuaLines.Add("    -- $($zone.Name)")
    $raidLuaLines.Add("    -- =========================================================")

    foreach ($record in $zoneRecords) {
        $name     = Escape-LuaString $record.Name
        $zoneName = Escape-LuaString $record.Zone
        $notes    = Escape-LuaString $record.Notes

        # Markdown Lua block
        $mdLuaLines.Add("    [$($record.NpcId)] = {")
        $mdLuaLines.Add(('        name         = "{0}",' -f $name))
        $mdLuaLines.Add(('        priorityType = "{0}",' -f $record.PriorityType))
        if ($null -ne $record.KillRank) {
            $mdLuaLines.Add(('        killRank     = {0},'   -f $record.KillRank))
        }
        $mdLuaLines.Add(('        zone         = "{0}",' -f $zoneName))
        $mdLuaLines.Add(('        notes        = "{0}",' -f $notes))
        $mdLuaLines.Add('        source       = "builtin",')
        $mdLuaLines.Add('    },')

        # RaidMobDB.lua
        $raidLuaLines.Add(('    ["{0}"] = {{' -f $record.NpcId))
        $raidLuaLines.Add(('        name = "{0}",' -f $name))
        $raidLuaLines.Add(('        priorityType = "{0}",' -f $record.PriorityType))
        if ($null -ne $record.KillRank) {
            $raidLuaLines.Add(('        killRank = {0},' -f $record.KillRank))
        }
        $raidLuaLines.Add(('        notes = "{0}",' -f $notes))
        $raidLuaLines.Add(('        zone = "{0}",' -f $zoneName))
        $raidLuaLines.Add('        source = "builtin",')
        $raidLuaLines.Add('    },')
    }
}

$mdLuaLines.Add('}')
$mdLuaLines.Add('```')
$raidLuaLines.Add('}')

# SMDB import string for raid DB
$importEntries = $deduped |
    Sort-Object ZoneId, @{ Expression = { Get-SortKey $_ } }, Name, NpcId |
    ForEach-Object {
        $safeName = ($_.Name -replace '[,|]', ';')
        $safeZone = ($_.Zone -replace '[,|]', ';')
        if ($null -ne $_.KillRank) {
            "$($_.NpcId),$($_.PriorityType):$($_.KillRank),$safeName,$safeZone"
        } else {
            "$($_.NpcId),$($_.PriorityType),$safeName,$safeZone"
        }
    }

# Build RESEARCH_OUTPUT_RAIDS.md
$outputLines = New-Object System.Collections.Generic.List[string]
$outputLines.Add('# SmartMark Raid Research Output')
$outputLines.Add('')
$outputLines.Add('Generated from saved Wowhead zone pages in .tmp/wowhead.')
$outputLines.Add('All kill entries use canonical `priorityType = "kill"` with explicit `killRank`.')
$outputLines.Add('kill1-4 legacy format is NOT used here.')
$outputLines.Add('')
$outputLines.AddRange($summaryLines)
$outputLines.Add('')
$outputLines.AddRange($mdLuaLines)
$outputLines.Add('')
$outputLines.Add('```text')
$outputLines.Add('SMDB:1:' + ($importEntries -join '|'))
$outputLines.Add('```')
$outputLines.Add('')
$outputLines.Add('## Omitted')
if ($omissions.Count -eq 0) {
    $outputLines.Add('- None')
} else {
    foreach ($o in $omissions) { $outputLines.Add('- ' + $o) }
}
$outputLines.Add('')
$outputLines.Add('## General Notes')
$outputLines.Add('- All kill entries use canonical priorityType = "kill" with explicit killRank (not kill1-4).')
$outputLines.Add('- killRank 10 = critical kill target (healers, summoners, buff-channelers, dangerous casters).')
$outputLines.Add('- killRank 20 = high priority secondary (casters, stealthers, ranged).')
$outputLines.Add('- killRank 30 = standard kill target (melee, mixed mobs).')
$outputLines.Add('- CC types (cc_shackle, cc_banish, cc_trap, cc_sheep) represent suggested CC options, not requirements.')
$outputLines.Add("- Hyjal Summit trash is wave-based; all listed NPCs spawn during scripted waves.")
$outputLines.Add("- Gruul's Lair and Magtheridon's Lair have minimal trash; their Wowhead zone pages may expose only a subset.")
$outputLines.Add('- NPC IDs sourced from Wowhead TBC zone pages. Boss mobs (boss=1) are excluded.')
$outputLines.Add('- Duplicate NPC IDs resolved to first (lowest ZoneId) occurrence.')

$outputLines | Set-Content -Path $outputPath -Encoding UTF8
$raidLuaLines | Set-Content -Path $raidOutputPath -Encoding UTF8

Write-Host "Wrote $outputPath"
Write-Host "Wrote $raidOutputPath"
Write-Host "Total raid mob entries: $($deduped.Count)"
foreach ($zone in $raidZoneSpecs) {
    $count = @($deduped | Where-Object Zone -eq $zone.Name).Count
    Write-Host ("  {0,-30} {1}" -f $zone.Name, $count)
}
