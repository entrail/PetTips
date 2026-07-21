-- Core.lua: bootstrap, class aliasing, family detection, zone helpers.
local T = _G.PT_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

test("boot: defaults land in ns.db, chardb tables initialized", function()
    local B = T.boot("HUNTER")
    assertEqual(B.ns.db.enableList, true)
    assertEqual(B.ns.db.showKnownByPet, true)
    assertEqual(B.ns.db.grimoireTooltips, true)
    assertEqual(type(B.ns.db.hiddenAbilities), "table")
    assertEqual(type(B.ns.chardb.knownTeach), "table")
    assertEqual(type(B.ns.chardb.syncedDemonFams), "table")
end)

test("boot: warlock gets the demon tables aliased, hunter does not", function()
    local W = T.boot("WARLOCK")
    assertTrue(W.ns.isWarlock)
    assertTrue(W.ns.PET_ABILITIES == W.ns.DEMON_ABILITIES, "abilities alias")
    assertTrue(W.ns.ABILITY_BY_SPELL == W.ns.DEMON_ABILITY_BY_SPELL, "bySpell alias")
    assertTrue(W.ns.PET_FAMILIES == W.ns.DEMON_FAMILIES, "families alias")
    assertTrue(W.ns.FAMILY_BY_NAME == W.ns.DEMON_FAMILY_BY_NAME, "famByName alias")

    local H = T.boot("HUNTER")
    assertFalse(H.ns.isWarlock or false)
    assertTrue(H.ns.PET_ABILITIES ~= H.ns.DEMON_ABILITIES, "hunter not aliased")
    -- other classes: no list UI is created, but data stays intact
    local M = T.boot("MAGE")
    assertTrue(M.ns.PET_ABILITIES ~= M.ns.DEMON_ABILITIES)
end)

test("GetPetFamilyId resolves the localized family name per class", function()
    local H = T.boot("HUNTER")
    H.m.state.petFamily = "Cat"
    assertEqual(H.ns.GetPetFamilyId(), 2)
    H.m.state.petFamily = "Крылатый змей" -- ruRU Wind Serpent
    assertEqual(H.ns.GetPetFamilyId(), 27)
    H.m.state.petFamily = "NotAFamily"
    assertEqual(H.ns.GetPetFamilyId(), nil)
    H.m.state.petFamily = nil
    assertEqual(H.ns.GetPetFamilyId(), nil)

    local W = T.boot("WARLOCK")
    W.m.state.petFamily = "Voidwalker"
    assertEqual(W.ns.GetPetFamilyId(), 16)
    W.m.state.petFamily = "Incubus"
    assertEqual(W.ns.GetPetFamilyId(), 17, "Incubus resolves to Succubus family")
    W.m.state.petFamily = "Wichtel" -- deDE Imp
    assertEqual(W.ns.GetPetFamilyId(), 23)
end)

test("CanSummonDemonFamily follows the known summon spells", function()
    local W = T.boot("WARLOCK")
    assertFalse(W.ns.CanSummonDemonFamily(23), "no summon spells known")
    W.m.state.playerSpells[688] = true
    assertTrue(W.ns.CanSummonDemonFamily(23), "Summon Imp known")
    assertFalse(W.ns.CanSummonDemonFamily(16))
    assertFalse(W.ns.CanSummonDemonFamily(17))
    W.m.state.playerSpells[713] = true -- Summon Incubus only
    assertTrue(W.ns.CanSummonDemonFamily(17), "Incubus summon counts for Succubus family")
    assertFalse(W.ns.CanSummonDemonFamily(1), "hunter family is never summonable")
end)

test("zone helpers: localized names, fallback, player zone keys", function()
    local H = T.boot("HUNTER")
    local m, ns = H.m, H.ns
    m.state.mapInfo[1429] = { name = "Elwynnwald", mapType = 3, parentMapID = 13 }
    m.state.realZones[36] = "Der Flammenschlund"

    local mob = { zone = "Elwynn Forest", zoneIds = { 1429 } }
    assertEqual(ns.GetMobZoneText(mob), "Elwynnwald", "uiMapID resolves localized")
    local dungeonMob = { zone = "Ragefire Chasm (Dungeon)", zoneIds = { -36 } }
    assertEqual(ns.GetMobZoneText(dungeonMob), "Der Flammenschlund", "instance id resolves")
    local unknownMob = { zone = "English Fallback", zoneIds = { 9999 } }
    assertEqual(ns.GetMobZoneText(unknownMob), "English Fallback", "unresolvable -> fallback")

    -- outdoor: player map walks up to (not including) the continent
    m.state.mapId = 1429
    m.state.mapInfo[13] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 0 }
    local keys = ns.GetPlayerZoneKeys()
    assertTrue(keys[1429], "own zone key")
    assertFalse(keys[13] or false, "continent excluded")

    -- instance: the negative instance id is the only key
    m.state.inInstance = true
    m.state.instanceId = 36
    keys = ns.GetPlayerZoneKeys()
    assertTrue(keys[-36], "instance key")
    assertFalse(keys[1429] or false, "no outdoor key in instance")
end)
