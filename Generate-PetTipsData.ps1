# Generates PetTips Data/Vanilla/*.lua from Petopia (abilities.html) joined
# with the 1.15 client DB (wago.tools CSVs). Petopia is the authority for
# obtainability/source/mobs; the client DB for spell IDs, rank order, TP
# costs and family availability. Mismatches are reported, not silently fixed.
$ErrorActionPreference = "Stop"
$sp  = $PSScriptRoot
$out = "D:\Development\WoW Addons\PetTips\Data\Vanilla"
New-Item -ItemType Directory -Force $out | Out-Null
$report = New-Object System.Collections.Generic.List[string]

# ---------------------------------------------------------------- client DB
$fam = Import-Csv "$sp\CreatureFamily.csv"
$sla = Import-Csv "$sp\SkillLineAbility.csv"
$sn  = Import-Csv "$sp\SpellName.csv"
$nameById = @{}; foreach ($r in $sn) { $nameById[[int]$r.ID] = $r.Name_lang }

$famName  = @{}   # famId -> enUS name
$famLine  = @{}   # famId -> family skill line
$lineFam  = @{}   # skill line -> famId
foreach ($f in $fam) {
    $famName[[int]$f.ID] = $f.Name_lang
    if ([int]$f.SkillLine_0 -gt 0) {
        $famLine[[int]$f.ID] = [int]$f.SkillLine_0
        $lineFam[[int]$f.SkillLine_0] = [int]$f.ID
    }
}
$GENERIC = 270

# petopia family key ('carrionbird') / mob family text ('Carrion Bird') -> famId
$famByNorm = @{}
foreach ($id in $famLine.Keys) {
    $famByNorm[($famName[$id] -replace '\s','').ToLower()] = $id
}

# rows on pet skill lines, deduped per (spell), remembering which lines carry it
$spellLines = @{}   # spellId -> set of skill lines
$spellSup   = @{}   # spellId -> superceded spell
$spellTP    = @{}   # spellId -> training point cost
foreach ($r in $sla) {
    $line = [int]$r.SkillLine
    if ($line -ne $GENERIC -and -not $lineFam.ContainsKey($line)) { continue }
    $s = [int]$r.Spell
    if (-not $spellLines.ContainsKey($s)) { $spellLines[$s] = @{} }
    $spellLines[$s][$line] = $true
    $spellSup[$s] = [int]$r.SupercedesSpell
    $spellTP[$s]  = [int]$r.CharacterPoints_1
}

# ordered rank chain for one ability name
function Get-Chain([string]$abilityName) {
    $ids = @($spellLines.Keys | Where-Object { $nameById[$_] -eq $abilityName })
    if ($ids.Count -eq 0) { return @() }
    $set = @{}; foreach ($i in $ids) { $set[$i] = $true }
    $roots = @($ids | Where-Object { $spellSup[$_] -eq 0 -or -not $set.ContainsKey($spellSup[$_]) })
    if ($roots.Count -ne 1) { $report.Add("CHAIN: $abilityName has $($roots.Count) roots"); return @($ids | Sort-Object) }
    $chain = New-Object System.Collections.Generic.List[int]
    $cur = $roots[0]
    while ($cur) {
        $chain.Add($cur)
        $next = @($ids | Where-Object { $spellSup[$_] -eq $cur })
        if ($next.Count -gt 1) { $report.Add("CHAIN: $abilityName fork at $cur") }
        $cur = if ($next.Count -ge 1) { $next[0] } else { $null }
    }
    if ($chain.Count -ne $ids.Count) { $report.Add("CHAIN: $abilityName chain $($chain.Count) != $($ids.Count) spells") }
    return $chain
}

# ------------------------------------------------- trainer costs (cmangos)
# npc_trainer INSERT rows from the cmangos classic-db 1.12 dump: teach-
# wrapper spell -> (cost copper, reqlevel). Other classes have same-named
# spells (warrior Charge, druid Prowl/Cower/Claw/Dash), so costs are only
# joined onto abilities whose petopia source says trainer.
$trainerCosts = @{}   # ability name -> list of {cost, reqlevel}
if (Test-Path "$sp\npc_trainer_inserts.sql") {
    $txtTrainer = Get-Content "$sp\npc_trainer_inserts.sql" -Raw
    $seenWrap = @{}
    foreach ($m in [regex]::Matches($txtTrainer, "\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+),")) {
        $wrapSpell = [int]$m.Groups[2].Value
        if ($seenWrap.ContainsKey($wrapSpell)) { continue }
        $seenWrap[$wrapSpell] = $true
        $wname = $nameById[$wrapSpell]
        if ($wname) {
            if (-not $trainerCosts.ContainsKey($wname)) { $trainerCosts[$wname] = New-Object System.Collections.Generic.List[object] }
            $trainerCosts[$wname].Add([pscustomobject]@{ cost = [int]$m.Groups[3].Value; reqlevel = [int]$m.Groups[6].Value })
        }
    }
} else {
    $report.Add("COST: npc_trainer_inserts.sql missing - money costs all 0")
}

# ---------------------------------------------------------------- petopia
$html = Get-Content "$sp\abilities.html" -Raw -Encoding UTF8
$secRe = [regex]"<h3 class='guide_heading classic' id='(?<key>\w+)'><img[^>]*>(?<name>[^<]+)</h3>"
$secs = $secRe.Matches($html)
$abilities = @()
for ($i = 0; $i -lt $secs.Count; $i++) {
    $m = $secs[$i]
    $end = if ($i + 1 -lt $secs.Count) { $secs[$i + 1].Index } else { $html.Length }
    $body = $html.Substring($m.Index, $end - $m.Index)

    $famIds = $null   # nil = all families
    if ($body -notmatch 'All Families') {
        $famIds = @()
        foreach ($fm in [regex]::Matches($body, "family\.php\?id=(\w+)'")) {
            $id = $famByNorm[$fm.Groups[1].Value.ToLower()]
            if ($null -eq $id) { $report.Add("FAMILY: unknown petopia family key '$($fm.Groups[1].Value)'") }
            else { $famIds += $id }
        }
        $famIds = @($famIds | Sort-Object -Unique)
    }

    $ranks = @()
    $rankRe = [regex]"<li id='\w+' class='abilityrank classic'><span class='abilityrankname classic'>(?<rname>[^<]+)</span>: Pet Level (?<lvl>\d+), Cost (?<tp>\d+) TP\."
    $rms = $rankRe.Matches($body)
    for ($k = 0; $k -lt $rms.Count; $k++) {
        $rm = $rms[$k]
        $rEnd = if ($k + 1 -lt $rms.Count) { $rms[$k + 1].Index } else { $body.Length }
        $chunk = $body.Substring($rm.Index, $rEnd - $rm.Index)
        $isTrainer = $chunk.Contains('Can be learned from trainers.')
        $isTaming  = $chunk.Contains('Can be learned by taming:')
        $isNone    = $chunk.Contains('No known training source.')
        $src = if ($isTrainer -and $isTaming) { 'tw' } elseif ($isTrainer) { 't' } elseif ($isTaming) { 'w' } else { 'n' }
        if ($isNone -and ($isTrainer -or $isTaming)) { $report.Add("SOURCE: $($rm.Groups['rname'].Value) has none+other") }
        $mobs = @()
        foreach ($mm in [regex]::Matches($chunk, "npc=(?<npc>\d+)'>(?<mname>[^<]+)</a> \((?<mfam>[^,]+), (?<mlvl>[^,]+), (?<mzone>[^)]+)\)")) {
            $mobs += [pscustomobject]@{
                npc = [int]$mm.Groups['npc'].Value; name = $mm.Groups['mname'].Value.Trim()
                fam = $mm.Groups['mfam'].Value.Trim(); lvl = $mm.Groups['mlvl'].Value.Trim()
                zone = $mm.Groups['mzone'].Value.Trim()
            }
        }
        if ($isTaming -and $mobs.Count -eq 0) { $report.Add("MOBS: $($rm.Groups['rname'].Value) taming but 0 mobs parsed") }
        $ranks += [pscustomobject]@{
            rname = $rm.Groups['rname'].Value.Trim()
            lvl = [int]$rm.Groups['lvl'].Value; tp = [int]$rm.Groups['tp'].Value
            src = $src; mobs = $mobs
        }
    }
    $abilities += [pscustomobject]@{
        key = $m.Groups['key'].Value; name = $m.Groups['name'].Value.Trim()
        fams = $famIds; ranks = $ranks
    }
}
$report.Add("INFO: petopia abilities parsed: $($abilities.Count), ranks: $(($abilities | ForEach-Object { $_.ranks.Count } | Measure-Object -Sum).Sum)")

# ---------------------------------------------------------------- join
$abilityOut = New-Object System.Collections.Generic.List[string]
$mobDict = @{}   # npc -> {name fam lvl zone teaches(list)}
foreach ($a in $abilities) {
    $chain = Get-Chain $a.name
    if ($chain.Count -eq 0) { $report.Add("JOIN: '$($a.name)' not found in client DB, skipped"); continue }
    if ($chain.Count -lt $a.ranks.Count) { $report.Add("JOIN: $($a.name) petopia $($a.ranks.Count) ranks > DB $($chain.Count), truncating petopia"); }
    if ($chain.Count -gt $a.ranks.Count) { $report.Add("INFO: $($a.name) DB has $($chain.Count) ranks, petopia lists $($a.ranks.Count) obtainable (extra DB ranks dropped)") }

    # DB family check
    $dbFams = @{}
    $allFam = $false
    for ($k = 0; $k -lt [Math]::Min($chain.Count, $a.ranks.Count); $k++) {
        foreach ($line in $spellLines[$chain[$k]].Keys) {
            if ($line -eq $GENERIC) { $allFam = $true } else { $dbFams[$lineFam[$line]] = $true }
        }
    }
    if ($allFam -and $a.fams) { $report.Add("FAMILY: $($a.name) is generic in DB but petopia lists families") }
    if (-not $allFam -and -not $a.fams) { $report.Add("FAMILY: $($a.name) family-bound in DB but petopia says all") }
    if (-not $allFam -and $a.fams) {
        $dbSet = @($dbFams.Keys | Sort-Object)
        # SoD-only families (e.g. Core Hound) exist in DB but not on petopia classic: warn only if petopia has ones DB lacks
        $missing = @($a.fams | Where-Object { -not $dbFams.ContainsKey($_) })
        if ($missing.Count) { $report.Add("FAMILY: $($a.name) petopia families missing in DB: $(($missing | ForEach-Object { $famName[$_] }) -join ', ')") }
        $extra = @($dbSet | Where-Object { $a.fams -notcontains $_ })
        if ($extra.Count) { $report.Add("INFO: $($a.name) DB-only families (SoD?): $(($extra | ForEach-Object { $famName[$_] }) -join ', ')") }
    }

    $famsLua = if ($a.fams) { "{ " + (($a.fams | ForEach-Object { "$_" }) -join ", ") + " }" } else { "nil" }
    $famsComment = if ($a.fams) { ($a.fams | ForEach-Object { $famName[$_] }) -join ", " } else { "all families" }
    $abilityOut.Add("ability(`"$($a.key)`", $famsLua) -- $($a.name): $famsComment")

    # money costs: only for trainer-sourced abilities; match ranks to
    # npc_trainer rows sorted by reqlevel (reqlevels equal the pet level
    # requirements; Growl 1+2 have reqlevel 0 and cost 1 copper)
    $costRows = $null
    $isTrainerAbility = @($a.ranks | Where-Object { $_.src -eq 't' -or $_.src -eq 'tw' }).Count -gt 0
    if ($isTrainerAbility -and $trainerCosts.ContainsKey($a.name)) {
        $costRows = @($trainerCosts[$a.name] | Sort-Object reqlevel, cost)
        if ($costRows.Count -ne $a.ranks.Count) {
            $report.Add("COST: $($a.name) has $($costRows.Count) trainer rows for $($a.ranks.Count) ranks")
        }
    } elseif ($isTrainerAbility) {
        $report.Add("COST: $($a.name) trainer-sourced but no npc_trainer rows")
    }

    for ($k = 0; $k -lt [Math]::Min($chain.Count, $a.ranks.Count); $k++) {
        $r = $a.ranks[$k]; $spell = $chain[$k]
        if ($spellTP[$spell] -ne $r.tp) { $report.Add("TP: $($r.rname) petopia $($r.tp) != DB $($spellTP[$spell]) (using DB)") }
        $rankNo = $k + 1
        if ($r.rname -match '(\d+)$' -and [int]$Matches[1] -ne $rankNo) { $report.Add("RANK: $($r.rname) ordinal != chain position $rankNo") }
        $money = 0
        if ($costRows -and $k -lt $costRows.Count) {
            $money = $costRows[$k].cost
            if ($costRows[$k].reqlevel -ne 0 -and $costRows[$k].reqlevel -ne $r.lvl) {
                $report.Add("COST: $($r.rname) reqlevel $($costRows[$k].reqlevel) != pet level $($r.lvl)")
            }
        }
        $abilityOut.Add("rank($spell, $rankNo, $($r.lvl), $($spellTP[$spell]), `"$($r.src)`", $money) -- $($r.rname)")
        foreach ($mb in $r.mobs) {
            $famId = $famByNorm[($mb.fam -replace '\s','').ToLower()]
            if ($null -eq $famId) { $report.Add("MOBFAM: npc $($mb.npc) '$($mb.name)' unknown family '$($mb.fam)'"); continue }
            if (-not $mobDict.ContainsKey($mb.npc)) {
                if ($mb.lvl -match '^(\d+)(?:-(\d+))?$') {
                    $mn = [int]$Matches[1]; $mx = if ($Matches[2]) { [int]$Matches[2] } else { $mn }
                } else { $report.Add("MOBLVL: npc $($mb.npc) '$($mb.name)' level '$($mb.lvl)'"); $mn = 0; $mx = 0 }
                $mobDict[$mb.npc] = [pscustomobject]@{
                    name = $mb.name; fam = $famId; min = $mn; max = $mx; zone = $mb.zone
                    teaches = New-Object System.Collections.Generic.List[int]
                }
            }
            if (-not $mobDict[$mb.npc].teaches.Contains($spell)) { $mobDict[$mb.npc].teaches.Add($spell) }
        }
    }
}

# ---------------------------------------------------------------- families file
$usedFams = @{}
foreach ($a in $abilities) { if ($a.fams) { foreach ($f in $a.fams) { $usedFams[$f] = $true } } }
foreach ($m in $mobDict.Values) { $usedFams[$m.fam] = $true }
# every tameable petopia family, even ones without special abilities (e.g. none missing normally)
$famIdsSorted = @($usedFams.Keys | Sort-Object)

$locNames = @{}   # famId -> set of localized names (all locales incl enUS)
foreach ($id in $famIdsSorted) { $locNames[$id] = [ordered]@{}; $locNames[$id][$famName[$id]] = $true }
foreach ($loc in @("deDE","frFR","esES","esMX","ptBR","ruRU","koKR","zhCN","zhTW","itIT")) {
    $f = "$sp\CreatureFamily_$loc.csv"
    if (-not (Test-Path $f)) { continue }
    foreach ($r in (Import-Csv $f)) {
        $id = [int]$r.ID
        if ($usedFams.ContainsKey($id) -and $r.Name_lang) { $locNames[$id][$r.Name_lang] = $true }
    }
}

function Esc([string]$s) { return $s.Replace('\', '\\').Replace('"', '\"') }

$nl = "`n"
$famLua = "local ADDON_NAME, ns = ...$nl$nl" +
"-- Hunter pet families (CreatureFamily IDs from the 1.15 client DB).$nl" +
"-- FAMILY_BY_NAME maps the localized UnitCreatureFamily(`"pet`") string of$nl" +
"-- every client locale back to the family ID (locale-safe detection).$nl" +
"-- Generated by Generate-PetTipsData.ps1 - do not hand-edit.$nl$nl" +
"ns.PET_FAMILIES = {$nl"
foreach ($id in $famIdsSorted) { $famLua += "    [$id] = `"$(Esc $famName[$id])`",$nl" }
$famLua += "}$nl$($nl)ns.FAMILY_BY_NAME = {$nl"
foreach ($id in $famIdsSorted) {
    foreach ($n in $locNames[$id].Keys) { $famLua += "    [`"$(Esc $n)`"] = $id,$nl" }
}
$famLua += "}$nl"
[IO.File]::WriteAllText("$out\FamilyData.lua", $famLua, (New-Object Text.UTF8Encoding($false)))

# ---------------------------------------------------------------- abilities file
$abLua = "local ADDON_NAME, ns = ...$nl$nl" +
"-- Pet ability ranks for Classic Era: every rank a hunter pet can learn,$nl" +
"-- with training point cost, required pet level, usable families and the$nl" +
"-- learning source. Spell IDs / rank order / TP costs from the 1.15 client$nl" +
"-- DB (SkillLineAbility), obtainability and sources from Petopia Classic.$nl" +
"-- Display names/icons come from GetSpellInfo(spellId) at runtime.$nl" +
"--$nl" +
"-- ability(key, families): families = CreatureFamily IDs (nil = all).$nl" +
"-- rank(spellId, rank, petLevel, tpCost, source, moneyCost): source `"t`" =$nl" +
"-- pet trainer, `"w`" = taming wild beasts, `"tw`" = both, `"n`" = no known$nl" +
"-- source. moneyCost in copper (cmangos 1.12 npc_trainer; 0 for taming).$nl$nl" +
"local ability, rank = ns.NewPetAbilityDB()$nl$nl" +
"-- DATA_START (generated by Generate-PetTipsData.ps1; do not hand-edit)$nl" +
(($abilityOut) -join $nl) + $nl +
"-- DATA_END$nl"
[IO.File]::WriteAllText("$out\PetAbilitiesData.lua", $abLua, (New-Object Text.UTF8Encoding($false)))

# ---------------------------------------------------------------- mobs file
$mobOut = New-Object System.Collections.Generic.List[string]
foreach ($npc in ($mobDict.Keys | Sort-Object)) {
    $m = $mobDict[$npc]
    $teach = "{ " + (($m.teaches | Sort-Object) -join ", ") + " }"
    $mobOut.Add("mob($npc, `"$(Esc $m.name)`", $($m.fam), $($m.min), $($m.max), `"$(Esc $m.zone)`", $teach) -- $($famName[$m.fam])")
}
$mobLua = "local ADDON_NAME, ns = ...$nl$nl" +
"-- Tameable beasts that teach at least one pet ability rank (learned by$nl" +
"-- taming them and letting them use the ability). npc IDs match the$nl" +
"-- creature GUID npc field; names/zones are English (Petopia has no$nl" +
"-- translations - shown as-is on all locales).$nl" +
"--$nl" +
"-- mob(npcId, name, familyId, minLevel, maxLevel, zone, { spellIds })$nl$nl" +
"local mob = ns.NewTameMobDB()$nl$nl" +
"-- DATA_START (generated by Generate-PetTipsData.ps1; do not hand-edit)$nl" +
(($mobOut) -join $nl) + $nl +
"-- DATA_END$nl"
[IO.File]::WriteAllText("$out\TameMobsData.lua", $mobLua, (New-Object Text.UTF8Encoding($false)))

# ---------------------------------------------------------------- report
"===== files ====="
Get-ChildItem $out | Format-Table Name, Length -AutoSize
"===== mobs: $($mobDict.Count) ====="
"===== report ($($report.Count)) ====="
$report | ForEach-Object { $_ }
