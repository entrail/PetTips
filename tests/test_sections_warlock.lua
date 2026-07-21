-- Warlock BuildSections + the staleness rule. Anchor data (real):
--   Firebolt (Imp 23): 3110 r1 auto lvl 1 | 7799 r2 lvl 8 | 7800 r3 lvl 18
--     | 7801 r4 lvl 28 | 7802 r5 lvl 38 | 11762 r6 lvl 48 | 11763 r7 lvl 58
--   Blood Pact (Imp): 6307 r1 grimoire lvl 4
--   Phase Shift (Imp): 4511 r1 grimoire lvl 12
--   Devour Magic (Felhunter 15): 19505 r1 auto lvl 30
local T = _G.PT_TEST
local test, assertEqual, assertTrue, assertFalse, assertContains, spells =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertContains, T.spells

local function impLock(playerLevel)
    local B = T.boot("WARLOCK")
    B.m.state.petFamily = "Imp"
    B.m.state.playerLevel = playerLevel or 60
    B.m.state.playerSpells[688] = true -- Summon Imp
    return B
end

test("warlock sections: fresh imp - auto rank known, first grimoires split by level", function()
    local B = impLock(10)
    B.m.state.petKnown[3110] = true -- Firebolt 1 comes with the imp
    local sections = B.ns.BuildTrainingSections()
    assertContains(spells(sections.known), 3110, "auto rank known")
    assertContains(spells(sections.now), 6307, "Blood Pact 1 buyable at 10")
    assertContains(spells(sections.now), 7799, "Firebolt 2 buyable at 10")
    assertContains(spells(sections.gated), 4511, "Phase Shift needs level 12")
    assertEqual(#sections.fromPet, 0, "fromPet never used for warlocks")
    assertEqual(#sections.notKnown, 0, "notKnown never used for warlocks")
end)

test("warlock sections: only the highest buyable rank shows - no wasted gold", function()
    local B = impLock(38)
    B.m.state.petKnown[3110] = true
    local sections = B.ns.BuildTrainingSections()
    local now = spells(sections.now)
    assertContains(now, 7802, "Firebolt 5 is the highest buyable at 38")
    for _, s in ipairs(now) do
        assertTrue(s ~= 7799 and s ~= 7800 and s ~= 7801, "lower Firebolt rank leaked into now")
    end
    assertContains(spells(sections.gated), 11762, "rank 6 gated at 38")
    assertContains(spells(sections.gated), 11763, "rank 7 gated at 38")
end)

test("warlock sections: cached ranks of a dismissed demon count as known", function()
    local B = impLock(8)
    B.m.state.petFamily = nil -- nothing summoned
    B.ns.chardb.knownTeach[3110] = true
    B.ns.chardb.knownTeach[7799] = true
    local sections = B.ns.BuildTrainingSections()
    assertContains(spells(sections.known), 7799, "cache-known rank")
    for _, s in ipairs(spells(sections.now)) do
        assertTrue(s ~= 7799, "known rank offered for buying")
    end
end)

test("warlock sections: ranks below a known higher rank vanish entirely", function()
    local B = impLock(60)
    B.ns.chardb.knownTeach[7800] = true -- Firebolt 3 bought directly
    local sections = B.ns.BuildTrainingSections()
    for _, list in pairs(sections) do
        for _, e in ipairs(list) do
            assertTrue(e.spell ~= 7799, "skipped rank 2 must not appear")
            assertTrue(e.spell ~= 3110, "skipped auto rank 1 must not appear")
        end
    end
    assertContains(spells(sections.now), 11763, "best rank at 60")
end)

test("warlock sections: auto ranks of future demons are gated with their level", function()
    local B = impLock(10)
    local sections = B.ns.BuildTrainingSections()
    -- no family filter without the imp? imp IS out - Devour Magic is
    -- felhunter-only, so it must not appear at all
    for _, list in pairs(sections) do
        for _, e in ipairs(list) do
            assertTrue(e.spell ~= 19505, "felhunter rank shown for an imp")
        end
    end
    -- without any pet the full catalogue shows, Devour Magic gated
    B.m.state.petFamily = nil
    sections = B.ns.BuildTrainingSections()
    assertContains(spells(sections.gated), 19505, "auto rank of future demon gated")
end)

test("warlock staleness: only summonable, unsynced, non-current demons warn", function()
    local B = impLock(6) -- knows only Summon Imp
    local ns = B.ns

    -- imp is out: current pet is live-read, nothing else summonable
    assertFalse(ns.DemonListStale(nil), "imp out, all view")
    assertFalse(ns.DemonListStale(23), "imp out, imp view")
    assertFalse(ns.DemonListStale(16), "voidwalker not summonable")

    -- imp dismissed: its recorded state may be missing
    B.m.state.petFamily = nil
    assertTrue(ns.DemonListStale(nil), "no pet, all view includes unsynced imp")
    assertTrue(ns.DemonListStale(23), "no pet, imp view")
    assertFalse(ns.DemonListStale(16), "voidwalker still not summonable")

    -- voidwalker learnable now
    B.m.state.playerSpells[697] = true
    assertTrue(ns.DemonListStale(16), "voidwalker summonable + unsynced")

    -- recorded once -> never stale again
    ns.chardb.syncedDemonFams[23] = true
    ns.chardb.syncedDemonFams[16] = true
    assertFalse(ns.DemonListStale(nil), "everything recorded")
end)
