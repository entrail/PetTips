-- KnownTraining: the craft/trainer scans (hunter), the demon spellbook
-- sync (warlock) and the grimoire classification - driven through the
-- same events the game fires. Craft/service names resolve by localized
-- spell name, which the mocks render as "Spell<id>".
local T = _G.PT_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

test("hunter scan: Beast Training craft window fills the cache", function()
    local B = T.boot("HUNTER")
    B.m.state.crafts = {
        { name = "Spell17253", rank = "Rank 1" }, -- Bite 1
        { name = "Spell17253", rank = "Rank 2" }, -- Bite 2 (name is rank 1's)
        { name = "Spell1742",  rank = "Rank 1" }, -- Cower 1
    }
    B.m.Fire("CRAFT_SHOW")
    assertTrue(B.ns.chardb.knownTeach[17253], "Bite 1 cached")
    assertTrue(B.ns.chardb.knownTeach[17255], "Bite 2 cached")
    assertTrue(B.ns.chardb.knownTeach[1742], "Cower 1 cached")
    assertTrue(B.ns.chardb.scannedBeastTraining, "sync flag set")
    assertTrue(#B.m.__prints > 0, "sync announced")
end)

test("hunter scan: a foreign craft window (enchanting) is ignored", function()
    local B = T.boot("HUNTER")
    B.m.state.crafts = { { name = "Enchant Bracer - Minor Health", rank = "" } }
    B.m.Fire("CRAFT_SHOW")
    assertFalse(B.ns.chardb.scannedBeastTraining or false, "no sync flag from enchanting")
    local count = 0
    for _ in pairs(B.ns.chardb.knownTeach) do count = count + 1 end
    assertEqual(count, 0, "nothing cached")
end)

test("hunter scan: NPC trainer records only 'used' services", function()
    local B = T.boot("HUNTER")
    B.m.state.services = {
        { name = "Spell24493", rank = "Rank 1", category = "used" },      -- Arcane Res 1
        { name = "Spell24493", rank = "Rank 2", category = "available" }, -- buyable, not learned
        { name = "Beast Training", rank = "", category = "header" },      -- header row
    }
    B.m.Fire("TRAINER_SHOW")
    assertTrue(B.ns.chardb.knownTeach[24493], "used rank cached")
    assertFalse(B.ns.chardb.knownTeach[24497] or false, "available rank must not be cached")
end)

test("hunter scan: LEARNED_SPELL_IN_TAB caches a taming-learned rank", function()
    local B = T.boot("HUNTER")
    B.m.Fire("LEARNED_SPELL_IN_TAB", 17256) -- Bite 3
    assertTrue(B.ns.chardb.knownTeach[17256])
    B.m.Fire("LEARNED_SPELL_IN_TAB", 133) -- some class spell: ignored
    assertFalse(B.ns.chardb.knownTeach[133] or false)
end)

test("warlock sync: a summoned demon's ranks are recorded", function()
    local B = T.boot("WARLOCK")
    B.m.state.petFamily = "Imp"
    B.m.state.petKnown[3110] = true -- Firebolt 1
    B.m.state.petKnown[7799] = true -- Firebolt 2 (bought earlier)
    B.m.Fire("UNIT_PET", "player")
    assertTrue(B.ns.chardb.knownTeach[3110], "auto rank recorded")
    assertTrue(B.ns.chardb.knownTeach[7799], "bought rank recorded")
    assertTrue(B.ns.chardb.syncedDemonFams[23], "imp marked synced")
    assertFalse(B.ns.chardb.syncedDemonFams[16] or false, "voidwalker untouched")
end)

test("warlock sync: login timer syncs the already-summoned demon", function()
    local B = T.boot("WARLOCK", function(m)
        m.state.petFamily = "Voidwalker"
        m.state.petKnown[3716] = true -- Torment 1
    end)
    B.m.FlushTimers() -- the C_Timer.After(3, ...) initial sync
    assertTrue(B.ns.chardb.knownTeach[3716])
    assertTrue(B.ns.chardb.syncedDemonFams[16])
end)

test("warlock sync: no demon out -> nothing marked", function()
    local B = T.boot("WARLOCK")
    B.m.Fire("UNIT_PET", "player")
    B.m.FlushTimers()
    local count = 0
    for _ in pairs(B.ns.chardb.syncedDemonFams) do count = count + 1 end
    assertEqual(count, 0)
end)

test("grimoire classification: missing / known / obsolete", function()
    local B = T.boot("WARLOCK")
    local ns = B.ns
    local entry = ns.GRIMOIRE_BY_ITEM[16302] -- Grimoire of Firebolt (Rank 2) -> 7799
    assertTrue(entry, "grimoire item mapped")

    local state, famName = ns.ClassifyGrimoire(entry)
    assertEqual(state, "missing")
    assertEqual(famName, "Imp")

    ns.chardb.knownTeach[7799] = true
    assertEqual((ns.ClassifyGrimoire(entry)), "known")

    ns.chardb.knownTeach[7799] = nil
    ns.chardb.knownTeach[7800] = true -- Firebolt 3 known instead
    assertEqual((ns.ClassifyGrimoire(entry)), "obsolete")

    -- live pet spellbook counts too (imp out, nothing cached)
    ns.chardb.knownTeach[7800] = nil
    B.m.state.petFamily = "Imp"
    B.m.state.petKnown[7799] = true
    assertEqual((ns.ClassifyGrimoire(entry)), "known")
end)

test("grimoire tooltip: hook adds the PetTips line for grimoire items only", function()
    local B = T.boot("WARLOCK")
    local tip = B.m.GameTooltip
    B.m.state.petFamily = "Imp"

    tip:SetOwner() -- clears lines
    tip.__item = { "Item16302", "item:16302" }
    B.m.FireHooks(tip, "OnTooltipSetItem", tip)
    assertEqual(#tip.__lines, 1, "one PetTips line")
    assertTrue(tip.__lines[1]:find("not yet known by your Imp") ~= nil, tip.__lines[1])

    -- guard: second fire on the same tooltip must not duplicate
    B.m.FireHooks(tip, "OnTooltipSetItem", tip)
    assertEqual(#tip.__lines, 1, "no duplicate line")
    -- cleared -> next item tooltip renders again
    B.m.FireHooks(tip, "OnTooltipCleared", tip)
    tip:SetOwner()
    tip.__item = { "Item999", "item:999" } -- not a grimoire
    B.m.FireHooks(tip, "OnTooltipSetItem", tip)
    assertEqual(#tip.__lines, 0, "non-grimoire item untouched")

    -- option off -> silent
    B.m.FireHooks(tip, "OnTooltipCleared", tip)
    tip:SetOwner()
    tip.__item = { "Item16302", "item:16302" }
    B.ns.db.grimoireTooltips = false
    B.m.FireHooks(tip, "OnTooltipSetItem", tip)
    assertEqual(#tip.__lines, 0, "disabled option")
end)

test("rank tooltip: warlock rows show level + grimoire cost", function()
    local B = T.boot("WARLOCK")
    local ns = B.ns
    local tip = B.m.GameTooltip
    local entry = ns.ABILITY_BY_SPELL[7799] -- Firebolt 2, 100c, level 8
    ns.ShowRankTooltip(entry, B.m.UIParent)
    local text = table.concat(tip.__lines, "\n")
    assertTrue(text:find("warlock level 8") ~= nil, "level line: " .. text)
    assertTrue(text:find("100c") ~= nil, "cost line: " .. text)
    assertTrue(text:find("Grimoire:") ~= nil, "grimoire line: " .. text)

    local auto = ns.ABILITY_BY_SPELL[3110] -- Firebolt 1, automatic
    ns.ShowRankTooltip(auto, B.m.UIParent)
    text = table.concat(tip.__lines, "\n")
    assertTrue(text:find("from the start") ~= nil, "auto line: " .. text)
end)
