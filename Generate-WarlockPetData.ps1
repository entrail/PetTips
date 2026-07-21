# Generates PetTips Data/Vanilla/DemonAbilitiesData.lua from the 1.15
# client DB (wago.tools CSVs). Unlike hunter pets, warlock demons learn
# every trainable rank from GRIMOIRE items sold by Demon Trainer vendors
# (verified: Classic Era demon trainers are vendors, they have no trainer
# window; cmangos/vmangos npc_trainer has no demon rows). The grimoire
# item is the authority for money cost and required warlock level; the
# SkillLineAbility chains give spell IDs, rank order and the auto-learned
# rank 1s (AcquireMethod 2 = known as soon as the demon is summoned).
#
# Inputs (default: next to this script; override with -InputDir):
#   SkillLineAbility.csv, SpellName.csv, SpellLevels.csv, SpellEffect.csv,
#   ItemSparse.csv, ItemEffect.csv, CreatureFamily.csv,
#   CreatureFamily_<locale>.csv (optional, for localized family names)
# all from https://wago.tools/db2/<table>/csv?build=1.15.8.67156
param([string]$InputDir = $PSScriptRoot)
$ErrorActionPreference = "Stop"
$sp  = $InputDir
$out = "D:\Development\WoW Addons\PetTips\Data\Vanilla"
$report = New-Object System.Collections.Generic.List[string]

# ------------------------------------------------------------ client DB
$sn = Import-Csv "$sp\SpellName.csv"
$nameById = @{}; foreach ($r in $sn) { $nameById[[int]$r.ID] = $r.Name_lang }

$baseLevel = @{}
foreach ($r in (Import-Csv "$sp\SpellLevels.csv")) { $baseLevel[[int]$r.SpellID] = [int]$r.BaseLevel }

# demon pet skill lines -> CreatureFamily IDs (Doomguard 19 / Infernal have
# no trainable abilities and are excluded; Felguard 2887 is SoD-only)
$famOfLine = @{ 188 = 23; 204 = 16; 205 = 17; 189 = 15 }
$famOrder  = @(23, 16, 17, 15)   # order the demons are obtained in

# rank spells per family; skip passives/SoD framework spells
$petSpells = @{}   # spellId -> famId
$spellSup  = @{}   # spellId -> superceded spell
$autoLearn = @{}   # spellId -> true (AcquireMethod 2)
foreach ($r in (Import-Csv "$sp\SkillLineAbility.csv")) {
    $l = [int]$r.SkillLine
    if (-not $famOfLine.ContainsKey($l)) { continue }
    $s = [int]$r.Spell
    $n = $nameById[$s]
    if (-not $n -or $n -match 'DND|Scaling|Demonic Pact|Effect$') { continue }
    $petSpells[$s] = $famOfLine[$l]
    $spellSup[$s]  = [int]$r.SupercedesSpell
    if ([int]$r.AcquireMethod -eq 2) { $autoLearn[$s] = $true }
}
$report.Add("INFO: demon rank spells: $($petSpells.Count)")

# grimoire join: ItemEffect use-spell -> SpellEffect LEARN_SPELL(36) -> rank spell
$wrapFor = @{}   # wrapper (item use) spell -> taught pet spell
foreach ($r in (Import-Csv "$sp\SpellEffect.csv")) {
    if ([int]$r.Effect -eq 36 -and $petSpells.ContainsKey([int]$r.EffectTriggerSpell)) {
        $wrapFor[[int]$r.SpellID] = [int]$r.EffectTriggerSpell
    }
}
$itemOfWrap = @{}
foreach ($r in (Import-Csv "$sp\ItemEffect.csv")) {
    $sid = [int]$r.SpellID
    if ($wrapFor.ContainsKey($sid)) { $itemOfWrap[[int]$r.ParentItemID] = $sid }
}
$grimoire = @{}   # pet spell -> {item, price, reqlvl, iname}
foreach ($r in (Import-Csv "$sp\ItemSparse.csv")) {
    $iid = [int]$r.ID
    if (-not $itemOfWrap.ContainsKey($iid)) { continue }
    $pet = $wrapFor[$itemOfWrap[$iid]]
    if ($grimoire.ContainsKey($pet)) { $report.Add("ITEM: rank spell $pet taught by two items ($($grimoire[$pet].item), $iid)"); continue }
    $grimoire[$pet] = [pscustomobject]@{ item = $iid; price = [int]$r.BuyPrice; reqlvl = [int]$r.RequiredLevel; iname = $r.Display_lang }
}
$report.Add("INFO: grimoire items matched: $($grimoire.Count)")

# ------------------------------------------------------------ chains
function Get-Chain([int]$famId, [string]$abilityName) {
    $ids = @($petSpells.Keys | Where-Object { $petSpells[$_] -eq $famId -and $nameById[$_] -eq $abilityName })
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

$fam = Import-Csv "$sp\CreatureFamily.csv"
$famName = @{}; foreach ($f in $fam) { $famName[[int]$f.ID] = $f.Name_lang }

$abilityOut = New-Object System.Collections.Generic.List[string]
foreach ($famId in $famOrder) {
    $names = @($petSpells.Keys | Where-Object { $petSpells[$_] -eq $famId } |
        ForEach-Object { $nameById[$_] } | Sort-Object -Unique)
    foreach ($aname in $names) {
        $chain = Get-Chain $famId $aname
        $key = ($aname -replace '[\s'']', '').ToLower()
        $abilityOut.Add("ability(`"$key`", $famId) -- $($aname): $($famName[$famId])")
        for ($k = 0; $k -lt $chain.Count; $k++) {
            $s = $chain[$k]; $rankNo = $k + 1
            $g = $grimoire[$s]
            if ($g) {
                if ($autoLearn.ContainsKey($s)) { $report.Add("SRC: $aname $rankNo is auto-learn AND has grimoire $($g.item)") }
                # grimoire name rank suffix must match the chain position
                if ($g.iname -match 'Rank (\d+)\)$' -and [int]$Matches[1] -ne $rankNo) {
                    $report.Add("RANK: $($g.iname) != chain position $rankNo")
                }
                $bl = $baseLevel[$s]
                if ($null -ne $bl -and $bl -ne 0 -and $bl -ne $g.reqlvl) {
                    $report.Add("LEVEL: $($g.iname) item reqlvl $($g.reqlvl) != spell base level $bl (using item)")
                }
                $abilityOut.Add("rank($s, $rankNo, $($g.reqlvl), `"g`", $($g.price), $($g.item)) -- $($g.iname)")
            } elseif ($autoLearn.ContainsKey($s)) {
                $bl = $baseLevel[$s]; if ($null -eq $bl) { $bl = 1 }
                $abilityOut.Add("rank($s, $rankNo, $bl, `"a`", 0, nil) -- $aname $rankNo (comes with the demon)")
            } else {
                $report.Add("SRC: $aname rank $rankNo (spell $s) has no grimoire and is not auto-learn")
                $abilityOut.Add("rank($s, $rankNo, $(if ($baseLevel[$s]) { $baseLevel[$s] } else { 1 }), `"a`", 0, nil) -- $aname $rankNo (NO SOURCE FOUND)")
            }
        }
    }
}

# ------------------------------------------------------------ family names
# Incubus (302) is the alternate Succubus appearance on Era and shares
# skill line 205 - its localized names alias to family 17.
$aliasFam = @{ 302 = 17 }
$locNames = @{}   # famId -> ordered set of localized names
foreach ($id in $famOrder) { $locNames[$id] = [ordered]@{}; $locNames[$id][$famName[$id]] = $true }
foreach ($id in $aliasFam.Keys) {
    $tgt = $aliasFam[$id]
    if ($famName[$id]) { $locNames[$tgt][$famName[$id]] = $true }
}
foreach ($loc in @("deDE","frFR","esES","esMX","ptBR","ruRU","koKR","zhCN","zhTW","itIT")) {
    $f = "$sp\CreatureFamily_$loc.csv"
    if (-not (Test-Path $f)) { $report.Add("LOCALE: CreatureFamily_$loc.csv missing"); continue }
    foreach ($r in (Import-Csv $f)) {
        $id = [int]$r.ID
        $tgt = if ($locNames.ContainsKey($id)) { $id } elseif ($aliasFam.ContainsKey($id)) { $aliasFam[$id] } else { $null }
        if ($null -ne $tgt -and $r.Name_lang) { $locNames[$tgt][$r.Name_lang] = $true }
    }
}

function Esc([string]$s) { return $s.Replace('\', '\\').Replace('"', '\"') }

# ------------------------------------------------------------ output
$nl = "`n"
$lua = "local ADDON_NAME, ns = ...$nl$nl" +
"-- Warlock demon abilities for Classic Era: every rank a demon can learn.$nl" +
"-- Demons train differently from hunter pets: each trainable rank is a$nl" +
"-- GRIMOIRE item sold by Demon Trainer vendors (money cost, required$nl" +
"-- warlock level); rank 1 of a demon's core attack comes with the demon.$nl" +
"-- No training points, no taming. Spell IDs / rank order from the 1.15$nl" +
"-- client DB (SkillLineAbility), costs/levels from the grimoire items$nl" +
"-- (ItemSparse joined via ItemEffect -> SpellEffect LEARN_SPELL).$nl" +
"-- Generated by Generate-WarlockPetData.ps1 - do not hand-edit.$nl" +
"--$nl" +
"-- ability(key, familyId): CreatureFamily ID of the one demon that uses it.$nl" +
"-- rank(spellId, rank, warlockLevel, source, moneyCost, grimoireItemId):$nl" +
"-- source `"g`" = grimoire (demon trainer vendor), `"a`" = automatic.$nl$nl" +
"ns.DEMON_FAMILIES = {$nl"
foreach ($id in ($famOrder | Sort-Object)) { $lua += "    [$id] = `"$(Esc $famName[$id])`",$nl" }
$lua += "}$nl$($nl)" +
"-- Localized UnitCreatureFamily(`"pet`") -> family ID, every client locale.$nl" +
"-- The Incubus (Era's alternate Succubus appearance) aliases to Succubus.$nl" +
"ns.DEMON_FAMILY_BY_NAME = {$nl"
foreach ($id in ($famOrder | Sort-Object)) {
    foreach ($n in $locNames[$id].Keys) { $lua += "    [`"$(Esc $n)`"] = $id,$nl" }
}
$lua += "}$nl$($nl)local ability, rank = ns.NewDemonAbilityDB()$nl$nl" +
"-- DATA_START (generated by Generate-WarlockPetData.ps1; do not hand-edit)$nl" +
(($abilityOut) -join $nl) + $nl +
"-- DATA_END$nl"
[IO.File]::WriteAllText("$out\DemonAbilitiesData.lua", $lua, (New-Object Text.UTF8Encoding($false)))

# ------------------------------------------------------------ report
"===== wrote $out\DemonAbilitiesData.lua ====="
"===== report ($($report.Count)) ====="
$report | ForEach-Object { $_ }
