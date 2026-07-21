-- Data integrity for both generated catalogues, on BOTH flavors.
-- Regenerating the data files must keep every invariant here - they are
-- what the list/scan code silently relies on. The count pins are REAL
-- counts (see AGENTS.md); a regen that changes them must update them
-- here consciously.
local T = _G.PT_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

local boots = {
    Vanilla = { H = T.boot("HUNTER"), W = T.boot("WARLOCK") },
    TBC     = { H = T.boot("HUNTER", nil, "TBC"), W = T.boot("WARLOCK", nil, "TBC") },
}

-- flavor -> pinned real counts
local PINS = {
    -- 106 ranks, not Petopia's 111: the five phantom rank-5 resistances
    -- are TBC bleed-in and were confirmed absent on Era (see AGENTS.md).
    Vanilla = { abilities = 21, ranks = 106, mobs = 297,
                demonAbilities = 16, demonRanks = 63, grimoires = 59, autos = 4 },
    TBC     = { abilities = 27, ranks = 137, mobs = 363,
                demonAbilities = 21, demonRanks = 87, grimoires = 83, autos = 4 },
}

for flavor, B in pairs(boots) do
    local pins = PINS[flavor]

    test(flavor .. " hunter data: ability/rank counts, valid entries", function()
        local ns = B.H.ns
        assertEqual(#ns.PET_ABILITIES, pins.abilities, "ability count")
        local ranks = 0
        for _, ability in ipairs(ns.PET_ABILITIES) do
            local prevLevel = 0
            for i, r in ipairs(ability.ranks) do
                ranks = ranks + 1
                assertEqual(r.rank, i, ability.key .. " rank order")
                assertTrue(r.level >= prevLevel, ability.key .. " level order")
                prevLevel = r.level
                assertTrue(r.src == "t" or r.src == "w" or r.src == "tw" or r.src == "n",
                    ability.key .. " src")
                assertEqual(ns.ABILITY_BY_SPELL[r.spell], r, ability.key .. " bySpell")
                if r.src == "w" or r.src == "n" then
                    assertEqual(r.money, 0, ability.key .. " taming rank with money")
                end
            end
        end
        assertEqual(ranks, pins.ranks, "rank count")
    end)

    test(flavor .. " hunter data: ability families exist in PET_FAMILIES", function()
        local ns = B.H.ns
        for _, ability in ipairs(ns.PET_ABILITIES) do
            if ability.families then
                for id in pairs(ability.families) do
                    assertTrue(ns.PET_FAMILIES[id], ability.key .. " family " .. id)
                end
            end
        end
    end)

    test(flavor .. " hunter data: FAMILY_BY_NAME values resolve", function()
        local ns = B.H.ns
        for name, id in pairs(ns.FAMILY_BY_NAME) do
            assertTrue(ns.PET_FAMILIES[id], "family name " .. name)
        end
    end)

    test(flavor .. " hunter data: mobs teach existing spells, valid families/levels/zones", function()
        local ns = B.H.ns
        local count = 0
        for npcId, mob in pairs(ns.TAME_MOBS) do
            count = count + 1
            assertTrue(ns.PET_FAMILIES[mob.family], "mob " .. npcId .. " family")
            assertTrue(mob.minLevel <= mob.maxLevel, "mob " .. npcId .. " levels")
            assertTrue(mob.zoneIds and #mob.zoneIds > 0, "mob " .. npcId .. " zoneIds")
            for _, z in ipairs(mob.zoneIds) do
                assertTrue(type(z) == "number" and z ~= 0, "mob " .. npcId .. " zone id")
            end
            assertTrue(#mob.teaches > 0, "mob " .. npcId .. " teaches nothing")
            for _, spellId in ipairs(mob.teaches) do
                assertTrue(ns.ABILITY_BY_SPELL[spellId], "mob " .. npcId .. " unknown spell " .. spellId)
            end
        end
        assertEqual(count, pins.mobs, "mob count")
        -- back-link: every MOBS_BY_SPELL list entry teaches that spell
        for spellId, mobs in pairs(ns.MOBS_BY_SPELL) do
            for _, mob in ipairs(mobs) do
                local found = false
                for _, s in ipairs(mob.teaches) do if s == spellId then found = true end end
                assertTrue(found, "MOBS_BY_SPELL back-link " .. spellId)
            end
        end
    end)

    test(flavor .. " warlock data: ability/rank/grimoire counts, valid entries", function()
        local ns = B.W.ns
        assertEqual(#ns.DEMON_ABILITIES, pins.demonAbilities, "ability count")
        local ranks, grims, autos = 0, 0, 0
        for _, ability in ipairs(ns.DEMON_ABILITIES) do
            local famId = next(ability.families)
            assertTrue(ns.DEMON_FAMILIES[famId], ability.key .. " family")
            assertEqual(next(ability.families, famId), nil, ability.key .. " single family")
            local prevLevel = 0
            for i, r in ipairs(ability.ranks) do
                ranks = ranks + 1
                assertEqual(r.rank, i, ability.key .. " rank order")
                assertTrue(r.level >= prevLevel, ability.key .. " level order")
                prevLevel = r.level
                assertEqual(ns.DEMON_ABILITY_BY_SPELL[r.spell], r, ability.key .. " bySpell")
                if r.src == "g" then
                    grims = grims + 1
                    assertTrue(r.item and r.money > 0, ability.key .. " grimoire fields")
                    assertEqual(ns.GRIMOIRE_BY_ITEM[r.item], r, ability.key .. " byItem")
                elseif r.src == "a" then
                    autos = autos + 1
                    assertEqual(r.rank, 1, ability.key .. " auto rank must be rank 1")
                    assertEqual(r.money, 0, ability.key .. " auto rank with money")
                else
                    assertTrue(false, ability.key .. " bad src " .. tostring(r.src))
                end
            end
        end
        assertEqual(ranks, pins.demonRanks, "rank count")
        assertEqual(grims, pins.grimoires, "grimoire count")
        assertEqual(autos, pins.autos, "auto count")
    end)

    test(flavor .. " warlock data: family name map incl. Incubus alias", function()
        local ns = B.W.ns
        for name, id in pairs(ns.DEMON_FAMILY_BY_NAME) do
            assertTrue(ns.DEMON_FAMILIES[id], "demon family name " .. name)
        end
        assertEqual(ns.DEMON_FAMILY_BY_NAME["Incubus"], 17, "Incubus alias")
        assertEqual(ns.DEMON_FAMILY_BY_NAME["Imp"], 23)
        assertEqual(ns.DEMON_FAMILY_BY_NAME["Voidwalker"], 16)
        assertEqual(ns.DEMON_FAMILY_BY_NAME["Felhunter"], 15)
    end)
end

test("flavor split: isTBC flag and TBC-only content", function()
    assertTrue(not boots.Vanilla.H.ns.isTBC, "vanilla boot is not TBC")
    assertTrue(boots.TBC.H.ns.isTBC, "TBC boot flag")
    -- TBC-only hunter families: Sporebat has no family ability but must
    -- still resolve (family-filtered list shows only generic abilities)
    assertEqual(boots.TBC.H.ns.PET_FAMILIES[33], "Sporebat", "Sporebat present on TBC")
    assertEqual(boots.Vanilla.H.ns.PET_FAMILIES[33], nil, "no Sporebat on Vanilla")
    -- TBC-only demon: Felguard
    assertEqual(boots.TBC.W.ns.DEMON_FAMILY_BY_NAME["Felguard"], 29, "Felguard on TBC")
    assertEqual(boots.Vanilla.W.ns.DEMON_FAMILIES[29], nil, "no Felguard on Vanilla")
end)
