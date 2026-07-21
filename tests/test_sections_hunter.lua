-- Hunter BuildSections: the section rules the whole list stands on.
-- Real data is used; the anchor ability is Bite (Cat-usable, taming):
--   17253 rank 1 (pet lvl 1, 1 TP), 17255 rank 2 (lvl 8, 4 TP),
--   17256 rank 3 (lvl 16, 7 TP)
-- and Arcane Resistance (all families, trainer): 24493 rank 1 (lvl 20, 5 TP).
local T = _G.PT_TEST
local test, assertEqual, assertTrue, assertFalse, assertContains, spells =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse, T.assertContains, T.spells

local function catHunter()
    local B = T.boot("HUNTER")
    B.m.state.petFamily = "Cat"
    B.m.state.petLevel = 60
    B.m.state.playerLevel = 60
    B.m.state.tpTotal = 100
    return B
end

test("hunter sections: nothing known -> everything is 'not learned by you'", function()
    local B = catHunter()
    local sections = B.ns.BuildTrainingSections()
    assertEqual(#sections.now, 0, "now empty")
    assertEqual(#sections.fromPet, 0, "fromPet empty")
    assertEqual(#sections.known, 0, "known empty")
    assertContains(spells(sections.notKnown), 17253, "Bite 1 not learned")
    assertContains(spells(sections.notKnown), 24493, "Arcane Res 1 not learned")
end)

test("hunter sections: teachable rank with level+TP lands in 'available now'", function()
    local B = catHunter()
    B.ns.chardb.knownTeach[17253] = true
    local sections = B.ns.BuildTrainingSections()
    assertContains(spells(sections.now), 17253)
end)

test("hunter sections: only the highest teachable rank shows, lower ones are skipped", function()
    local B = catHunter()
    B.ns.chardb.knownTeach[17253] = true
    B.ns.chardb.knownTeach[17255] = true
    local sections = B.ns.BuildTrainingSections()
    local now = spells(sections.now)
    assertContains(now, 17255, "highest teachable rank")
    for _, s in ipairs(now) do assertTrue(s ~= 17253, "rank 1 must be superseded") end
    -- rank 1 is in NO section at all (teaching it would waste points)
    for _, list in pairs(sections) do
        for _, e in ipairs(list) do assertTrue(e.spell ~= 17253, "rank 1 leaked") end
    end
end)

test("hunter sections: not enough TP gates every known rank", function()
    local B = catHunter()
    B.m.state.tpTotal = 0
    B.ns.chardb.knownTeach[17253] = true
    B.ns.chardb.knownTeach[17255] = true
    local sections = B.ns.BuildTrainingSections()
    assertEqual(#sections.now, 0, "nothing affordable")
    assertContains(spells(sections.gated), 17253)
    assertContains(spells(sections.gated), 17255)
end)

test("hunter sections: pet level gates, hunter level colors are not the gate", function()
    local B = catHunter()
    B.m.state.petLevel = 4 -- below Bite 2's pet level 8
    B.ns.chardb.knownTeach[17253] = true
    B.ns.chardb.knownTeach[17255] = true
    local sections = B.ns.BuildTrainingSections()
    assertContains(spells(sections.now), 17253, "rank 1 teachable at pet level 4")
    assertContains(spells(sections.gated), 17255, "rank 2 needs pet level 8")
end)

test("hunter sections: pet-known but not teachable-by-you -> 'from your current pet'", function()
    local B = catHunter()
    B.m.state.petKnown[17253] = true
    local sections = B.ns.BuildTrainingSections()
    assertContains(spells(sections.fromPet), 17253)
    -- once the hunter learned it too, it moves to the gray known section
    B.ns.chardb.knownTeach[17253] = true
    sections = B.ns.BuildTrainingSections()
    assertContains(spells(sections.known), 17253)
    assertEqual(#sections.fromPet, 0)
end)

test("hunter sections: family filter excludes foreign-family abilities", function()
    local B = catHunter() -- Charge is Boar-only (7371 rank 1)
    local sections = B.ns.BuildTrainingSections()
    for _, list in pairs(sections) do
        for _, e in ipairs(list) do
            assertTrue(e.spell ~= 7371, "Boar Charge visible for a Cat")
        end
    end
end)

test("hunter sections: no pet -> all families shown (browse mode)", function()
    local B = catHunter()
    B.m.state.petFamily = nil
    local sections = B.ns.BuildTrainingSections()
    assertContains(spells(sections.notKnown), 7371, "Charge visible without a pet")
end)

test("hunter sections: hidden ability disappears from every section", function()
    local B = catHunter()
    B.ns.chardb.knownTeach[17253] = true
    B.ns.db.hiddenAbilities["bite"] = true
    local sections = B.ns.BuildTrainingSections()
    for _, list in pairs(sections) do
        for _, e in ipairs(list) do
            assertTrue(e.ability.key ~= "bite", "hidden ability leaked")
        end
    end
end)
