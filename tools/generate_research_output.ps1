Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $repoRoot '.tmp\wowhead'
$outputPath = Join-Path $repoRoot 'RESEARCH_OUTPUT.md'
$builtinOutputPath = Join-Path $repoRoot 'Config\BuiltinMobDB.lua'

$zoneSpecs = @(
    [pscustomobject]@{ Id = 3562; Name = 'Hellfire Ramparts'; MinLevel = 60 },
    [pscustomobject]@{ Id = 3713; Name = 'The Blood Furnace'; MinLevel = 61 },
    [pscustomobject]@{ Id = 3717; Name = 'The Slave Pens'; MinLevel = 62 },
    [pscustomobject]@{ Id = 3716; Name = 'The Underbog'; MinLevel = 63 },
    [pscustomobject]@{ Id = 3792; Name = 'Mana-Tombs'; MinLevel = 64 },
    [pscustomobject]@{ Id = 3790; Name = 'Auchenai Crypts'; MinLevel = 65 },
    [pscustomobject]@{ Id = 2367; Name = 'Old Hillsbrad Foothills'; MinLevel = 66 },
    [pscustomobject]@{ Id = 3791; Name = 'Sethekk Halls'; MinLevel = 67 },
    [pscustomobject]@{ Id = 2366; Name = 'The Black Morass'; MinLevel = 68 },
    [pscustomobject]@{ Id = 3849; Name = 'The Mechanar'; MinLevel = 69 },
    [pscustomobject]@{ Id = 3714; Name = 'The Shattered Halls'; MinLevel = 70 },
    [pscustomobject]@{ Id = 3715; Name = 'The Steamvault'; MinLevel = 70 },
    [pscustomobject]@{ Id = 3789; Name = 'Shadow Labyrinth'; MinLevel = 70 },
    [pscustomobject]@{ Id = 3847; Name = 'The Botanica'; MinLevel = 70 },
    [pscustomobject]@{ Id = 3848; Name = 'The Arcatraz'; MinLevel = 70 },
    [pscustomobject]@{ Id = 4131; Name = "Magisters' Terrace"; MinLevel = 70 }
)

$typeMap = @{
    1 = 'Beast'
    2 = 'Dragonkin'
    3 = 'Demon'
    4 = 'Elemental'
    5 = 'Giant'
    6 = 'Undead'
    7 = 'Humanoid'
    8 = 'Critter'
    9 = 'Mechanical'
}

$priorityOrder = @{
    kill1 = 1
    kill2 = 2
    kill3 = 3
    kill4 = 4
    cc_sheep = 5
    cc_trap = 6
    cc_banish = 7
    cc_sap = 8
    cc_shackle = 9
    cc_hibernate = 10
    skip = 11
}

$excludedNpcIds = @(17540)

$manualEntries = @(
    [pscustomobject]@{ NpcId = 17819; Name = 'Durnholde Sentry'; Zone = 'Old Hillsbrad Foothills'; ZoneId = 2367; MinLevel = 66; CreatureType = 'Humanoid'; PriorityType = 'kill2'; Notes = 'Patrol pull. Pick it up before extra aggro.' },
    [pscustomobject]@{ NpcId = 17820; Name = 'Durnholde Rifleman'; Zone = 'Old Hillsbrad Foothills'; ZoneId = 2367; MinLevel = 66; CreatureType = 'Humanoid'; PriorityType = 'kill2'; Notes = 'Ranged pressure. Pull line of sight.' },
    [pscustomobject]@{ NpcId = 17833; Name = 'Durnholde Warden'; Zone = 'Old Hillsbrad Foothills'; ZoneId = 2367; MinLevel = 66; CreatureType = 'Humanoid'; PriorityType = 'kill1'; Notes = 'Heals, dispels, and fears. Hard stop target.' },
    [pscustomobject]@{ NpcId = 17840; Name = 'Durnholde Tracking Hound'; Zone = 'Old Hillsbrad Foothills'; ZoneId = 2367; MinLevel = 66; CreatureType = 'Beast'; PriorityType = 'cc_trap'; Notes = 'Beast control target.' },
    [pscustomobject]@{ NpcId = 17860; Name = 'Durnholde Veteran'; Zone = 'Old Hillsbrad Foothills'; ZoneId = 2367; MinLevel = 66; CreatureType = 'Humanoid'; PriorityType = 'kill3'; Notes = 'Standard melee.' },
    [pscustomobject]@{ NpcId = 18093; Name = 'Tarren Mill Protector'; Zone = 'Old Hillsbrad Foothills'; ZoneId = 2367; MinLevel = 66; CreatureType = 'Humanoid'; PriorityType = 'kill1'; Notes = 'Paladin healer. Sheep or kill immediately.' },
    [pscustomobject]@{ NpcId = 18094; Name = 'Tarren Mill Lookout'; Zone = 'Old Hillsbrad Foothills'; ZoneId = 2367; MinLevel = 66; CreatureType = 'Humanoid'; PriorityType = 'kill2'; Notes = 'Escort-wave ranged support.' },
    [pscustomobject]@{ NpcId = 18934; Name = 'Durnholde Mage'; Zone = 'Old Hillsbrad Foothills'; ZoneId = 2367; MinLevel = 66; CreatureType = 'Humanoid'; PriorityType = 'kill1'; Notes = 'Dangerous caster. Interrupt or sheep.' },
    [pscustomobject]@{ NpcId = 23175; Name = 'Tarren Mill Guardsman'; Zone = 'Old Hillsbrad Foothills'; ZoneId = 2367; MinLevel = 66; CreatureType = 'Humanoid'; PriorityType = 'kill3'; Notes = 'Standard escort trash.' },

    [pscustomobject]@{ NpcId = 24687; Name = 'Sunblade Physician'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Humanoid'; PriorityType = 'kill1'; Notes = 'Healer. Interrupt and kill fast.' },
    [pscustomobject]@{ NpcId = 24686; Name = 'Sunblade Warlock'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Humanoid'; PriorityType = 'kill1'; Notes = 'Dangerous caster. Interrupt shadow casts.' },
    [pscustomobject]@{ NpcId = 24683; Name = 'Sunblade Mage Guard'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Humanoid'; PriorityType = 'kill2'; Notes = 'High caster pressure.' },
    [pscustomobject]@{ NpcId = 24685; Name = 'Sunblade Magister'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Humanoid'; PriorityType = 'kill2'; Notes = 'High caster pressure.' },
    [pscustomobject]@{ NpcId = 24696; Name = 'Coilskar Witch'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Humanoid'; PriorityType = 'kill2'; Notes = 'Caster pressure. Interrupt if possible.' },
    [pscustomobject]@{ NpcId = 24777; Name = 'Sunblade Sentinel'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Humanoid'; PriorityType = 'kill2'; Notes = 'Heavy trash mob. Burns more rep than most.' },
    [pscustomobject]@{ NpcId = 24684; Name = 'Sunblade Blood Knight'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Humanoid'; PriorityType = 'kill3'; Notes = 'Standard melee.' },
    [pscustomobject]@{ NpcId = 24762; Name = 'Sunblade Keeper'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Humanoid'; PriorityType = 'kill3'; Notes = 'Standard melee.' },
    [pscustomobject]@{ NpcId = 24698; Name = 'Ethereum Smuggler'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Humanoid'; PriorityType = 'kill3'; Notes = 'Mixed ranged pressure.' },
    [pscustomobject]@{ NpcId = 24689; Name = 'Wretched Bruiser'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Humanoid'; PriorityType = 'kill3'; Notes = 'Standard melee.' },
    [pscustomobject]@{ NpcId = 24688; Name = 'Wretched Skulker'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Humanoid'; PriorityType = 'kill2'; Notes = 'Rogue-like opener threat.' },
    [pscustomobject]@{ NpcId = 24690; Name = 'Wretched Husk'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Humanoid'; PriorityType = 'kill4'; Notes = 'Low-priority wretched add.' },
    [pscustomobject]@{ NpcId = 24761; Name = 'Brightscale Wyrm'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Dragonkin'; PriorityType = 'cc_trap'; Notes = 'Dragonkin CC target.' },
    [pscustomobject]@{ NpcId = 24697; Name = 'Sister of Torment'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Demon'; PriorityType = 'cc_banish'; Notes = 'Prime banish target.' },
    [pscustomobject]@{ NpcId = 24815; Name = 'Sunblade Imp'; Zone = "Magisters' Terrace"; ZoneId = 4131; MinLevel = 70; CreatureType = 'Demon'; PriorityType = 'skip'; Notes = 'Low-health companion add.' }
)

function Get-EmbeddedNpcRows {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HtmlPath,
        [Parameter(Mandatory = $true)]
        [int]$ZoneId
    )

    if (-not (Test-Path $HtmlPath)) {
        return @()
    }

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

        if (-not $match.Success) {
            return @()
        }

        $json = $match.Groups[1].Value
        return @($json | ConvertFrom-Json)
    }

    $json = '[' + $match.Groups[1].Value + ']'
    return @($json | ConvertFrom-Json)
}

function Is-HostileTrash {
    param(
        [Parameter(Mandatory = $true)]
        $Row,
        [Parameter(Mandatory = $true)]
        [int]$ZoneId
    )

    $nameProp = $Row.PSObject.Properties['name']
    if ($null -eq $nameProp -or -not $nameProp.Value) {
        return $false
    }

    $bossProp = $Row.PSObject.Properties['boss']
    if ($null -ne $bossProp -and $bossProp.Value -eq 1) {
        return $false
    }

    $locationProp = $Row.PSObject.Properties['location']
    if ($null -eq $locationProp) {
        return $false
    }

    $locations = @($locationProp.Value)
    if ($locations -notcontains $ZoneId) {
        return $false
    }

    $reactProp = $Row.PSObject.Properties['react']
    if ($null -eq $reactProp) {
        return $false
    }

    $reactions = @($reactProp.Value)
    if ($reactions -notcontains -1) {
        return $false
    }

    return $true
}

function Get-Notes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $patterns = @(
        @{ Regex = 'Healer|Priest|Soulpriest|Physician'; Note = 'Healer. Interrupt major heals.' },
        @{ Regex = 'Summoner'; Note = 'Summons adds. Interrupt casts.' },
        @{ Regex = 'Warlock|Darkcaster|Shadowmage|Theurgist|Spellbinder'; Note = 'Dangerous caster. Interrupt.' },
        @{ Regex = 'Sorcerer|Sorceress|Astromage|Geomancer|Researcher|Oracle|Prophet|Shaman|Channeler'; Note = 'Caster pressure. Interrupt if possible.' },
        @{ Regex = 'Archer|Sharpshooter|Rifleman|Falconer'; Note = 'Ranged pressure. Pull with line of sight.' },
        @{ Regex = 'Technician|Engineer|Mechanic|Tinkerer'; Note = 'Utility mob. Watch bombs or gadgets.' },
        @{ Regex = 'Beastmaster|Slavehandler|Slavemaster'; Note = 'Handler mob. Control pack early.' },
        @{ Regex = 'Sentry|Sentinel'; Note = 'Patrol or alarm mob. Pick up quickly.' },
        @{ Regex = 'Ravener|Warhound|Lurker|Wasp'; Note = 'Mobile threat. Keep it controlled.' }
    )

    foreach ($entry in $patterns) {
        if ($Name -match $entry.Regex) {
            return $entry.Note
        }
    }

    return ''
}

function Get-PriorityType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $false)]
        [string]$CreatureType
    )

    if ($CreatureType -eq 'Critter') {
        return 'skip'
    }

    if ($Name -match 'Imp|Familiar|Beacon|Snake|Viper|Fire Beetle|Frog|Maggot|Spider$|Crab$') {
        return 'skip'
    }

    if ($Name -match 'Healer|Priest|Soulpriest|Physician|Summoner|Warlock|Darkcaster') {
        return 'kill1'
    }

    if ($Name -match 'Chronomancer|Shadowmage|Sorcerer|Sorceress|Spellbinder|Theurgist|Astromage|Geomancer|Oracle|Prophet|Shaman|Channeler|Adept|Acolyte|Researcher|Scryer|Magister|Mage Guard|Mage|Witch') {
        return 'kill2'
    }

    if ($Name -match 'Sentry|Sentinel|Archer|Sharpshooter|Rifleman|Falconer|Technician|Engineer|Mechanic|Tinkerer|Slayer|Controller|Executioner') {
        return 'kill2'
    }

    if ($Name -match 'Destroyer|Annihilator|Devourer|Ravener|Ripper|Champion|Vindicator|Legionnaire|Reaver|Crusher|Wrecker|Protean Horror|Soul Devourer|Rift Lord|Bog Giant|Underbog Lord') {
        return 'kill3'
    }

    if ($Name -match 'Slave|Neophyte|Apprentice|Skulker|Husk|Stalker|Scavenger|Steward|Greenkeeper|Crocolisk|Whelp') {
        return 'kill4'
    }

    switch ($CreatureType) {
        'Humanoid' { return 'cc_sheep' }
        'Beast' { return 'cc_trap' }
        'Dragonkin' { return 'cc_trap' }
        'Demon' { return 'cc_banish' }
        'Elemental' { return 'cc_banish' }
        'Undead' { return 'cc_shackle' }
        default { return 'kill3' }
    }
}

function Escape-LuaString {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    return ($Value -replace '\\', '\\\\' -replace '"', '\\"')
}

$records = New-Object System.Collections.Generic.List[object]
$omissions = New-Object System.Collections.Generic.List[string]

foreach ($zone in $zoneSpecs) {
    $htmlPath = Join-Path $sourceDir ("zone_{0}.html" -f $zone.Id)
    $rows = Get-EmbeddedNpcRows -HtmlPath $htmlPath -ZoneId $zone.Id
    $hostileRows = @($rows | Where-Object { Is-HostileTrash -Row $_ -ZoneId $zone.Id })
    $manualZoneRows = @($manualEntries | Where-Object ZoneId -eq $zone.Id)

    if ($hostileRows.Count -eq 0) {
        if ($manualZoneRows.Count -eq 0) {
            $omissions.Add("$($zone.Name): no hostile trash NPCs were exposed in the saved Wowhead page.")
            continue
        }
    }

    foreach ($row in $hostileRows) {
        if ($excludedNpcIds -contains [int]$row.id) {
            continue
        }

        $creatureType = ''
        if ($null -ne $row.type -and $typeMap.ContainsKey([int]$row.type)) {
            $creatureType = $typeMap[[int]$row.type]
        }

        $records.Add([pscustomobject]@{
            NpcId = [int]$row.id
            Name = [string]$row.name
            Zone = [string]$zone.Name
            ZoneId = [int]$zone.Id
            MinLevel = [int]$zone.MinLevel
            CreatureType = [string]$creatureType
            PriorityType = Get-PriorityType -Name ([string]$row.name) -CreatureType ([string]$creatureType)
            Notes = Get-Notes -Name ([string]$row.name)
        })
    }
}

foreach ($entry in $manualEntries) {
    $records.Add($entry)
}

$deduped = $records |
    Sort-Object MinLevel, Zone, NpcId |
    Group-Object NpcId |
    ForEach-Object { $_.Group | Select-Object -First 1 }

$summary = foreach ($zone in $zoneSpecs) {
    [pscustomobject]@{
        Zone = $zone.Name
        Count = @($deduped | Where-Object Zone -eq $zone.Name).Count
    }
}

$luaLines = New-Object System.Collections.Generic.List[string]
$luaLines.Add('```lua')
$luaLines.Add('SmartMark_BuiltinDB = {')

$builtinLines = New-Object System.Collections.Generic.List[string]
$builtinLines.Add('local addon = SmartMark')
$builtinLines.Add('addon.BuiltinMobDB = {')

foreach ($zone in $zoneSpecs) {
    $zoneRecords = @($deduped | Where-Object Zone -eq $zone.Name | Sort-Object @{ Expression = { $priorityOrder[$_.PriorityType] } }, Name, NpcId)
    if ($zoneRecords.Count -eq 0) {
        continue
    }

    $luaLines.Add('    -- =========================================================')
    $luaLines.Add("    -- $($zone.Name)")
    $luaLines.Add('    -- =========================================================')

    foreach ($record in $zoneRecords) {
        $name = Escape-LuaString -Value $record.Name
        $zoneName = Escape-LuaString -Value $record.Zone
        $notes = Escape-LuaString -Value $record.Notes
        $luaLines.Add("    [$($record.NpcId)] = {")
        $luaLines.Add(('        name         = "{0}",' -f $name))
        $luaLines.Add(('        priorityType = "{0}",' -f $record.PriorityType))
        $luaLines.Add(('        zone         = "{0}",' -f $zoneName))
        $luaLines.Add(('        notes        = "{0}",' -f $notes))
        $luaLines.Add('        source       = "builtin",')
        $luaLines.Add('    },')

        $builtinLines.Add(('    ["{0}"] = {{' -f $record.NpcId))
        $builtinLines.Add(('        name = "{0}",' -f $name))
        $builtinLines.Add(('        priorityType = "{0}",' -f $record.PriorityType))
        $builtinLines.Add(('        notes = "{0}",' -f $notes))
        $builtinLines.Add(('        zone = "{0}",' -f $zoneName))
        $builtinLines.Add('        source = "builtin",')
        $builtinLines.Add('    },')
    }
}

$luaLines.Add('}')
$luaLines.Add('```')
    $builtinLines.Add('}')

$importEntries = $deduped |
    Sort-Object MinLevel, @{ Expression = { $priorityOrder[$_.PriorityType] } }, Name, NpcId |
    ForEach-Object {
        $safeName = ($_.Name -replace '[,|]', ';')
        $safeZone = ($_.Zone -replace '[,|]', ';')
        "$($_.NpcId),$($_.PriorityType),$safeName,$safeZone"
    }

$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add('| Dungeon | Mobs Found |')
$summaryLines.Add('| --- | ---: |')
foreach ($item in $summary) {
    $summaryLines.Add("| $($item.Zone) | $($item.Count) |")
}

$outputLines = New-Object System.Collections.Generic.List[string]
$outputLines.Add('# SmartMark Research Output')
$outputLines.Add('')
$outputLines.Add('This draft was generated from saved Wowhead zone pages in .tmp/wowhead.')
$outputLines.Add('Priority assignments and notes are heuristic where direct comment research was not available.')
$outputLines.Add('')
$outputLines.AddRange($summaryLines)
$outputLines.Add('')
$outputLines.AddRange($luaLines)
$outputLines.Add('')
$outputLines.Add('```text')
$outputLines.Add('SMDB:1:' + ($importEntries -join '|'))
$outputLines.Add('```')
$outputLines.Add('')
$outputLines.Add('## Omitted')
if ($omissions.Count -eq 0) {
    $outputLines.Add('- None')
} else {
    foreach ($omission in $omissions) {
        $outputLines.Add('- ' + $omission)
    }
}
$outputLines.Add('')
$outputLines.Add('## General Notes')
$outputLines.Add('- Old Hillsbrad Foothills and Magisters'' Terrace were backfilled from secondary sources plus verified Wowhead NPC searches.')
$outputLines.Add('- Some creature types were missing from Wowhead rows; those entries were classified with broader heuristics and should be reviewed manually.')
$outputLines.Add('- Duplicate NPC IDs were kept only in the lowest-level dungeon listed in the task requirements.')

$outputLines | Set-Content -Path $outputPath
$builtinLines | Set-Content -Path $builtinOutputPath
Write-Host "Wrote $outputPath"