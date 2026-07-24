-- Beast tooltip lines (US-30 rank lines + US-51 family type/tier line),
-- driven through the real OnTooltipSetUnit hook against the mock tooltip.
local T = _G.PT_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

-- Simulate mousing over npc <npcId> on the LEGACY script path: clear the
-- tooltip (resets the once-per-tooltip guard, like the game), point the
-- mock tooltip/GUID APIs at the npc, fire the hook, return the lines.
local function hover(b, npcId)
    local m = b.m
    m.GameTooltip.GetUnit = function() return "SomeMob", "mouseover" end
    m.UnitGUID = function() return "Creature-0-4170-1-160-" .. npcId .. "-0000232C09" end
    m.FireHooks(m.GameTooltip, "OnTooltipCleared", m.GameTooltip)
    m.GameTooltip.__lines = {}
    m.FireHooks(m.GameTooltip, "OnTooltipSetUnit", m.GameTooltip)
    return m.GameTooltip.__lines
end

-- Simulate mousing over a hunter PET unit (Pet-... guid): famName drives
-- the mock's UnitCreatureFamily, npcId is the tamed creature's npc id.
local function hoverPet(b, npcId, famName)
    local m = b.m
    m.state.petFamily = famName
    m.GameTooltip.GetUnit = function() return "SomePet", "mouseover" end
    m.UnitGUID = function() return "Pet-0-4170-1-160-" .. npcId .. "-0000232C09" end
    m.FireHooks(m.GameTooltip, "OnTooltipCleared", m.GameTooltip)
    m.GameTooltip.__lines = {}
    m.FireHooks(m.GameTooltip, "OnTooltipSetUnit", m.GameTooltip)
    return m.GameTooltip.__lines
end

local function anyContains(lines, needle)
    for _, l in ipairs(lines) do
        if string.find(l, needle, 1, true) then return true end
    end
    return false
end

test("hunter Vanilla: family line first (spec + tier), then rank lines", function()
    local b = T.boot("HUNTER")
    -- npc 118 Prowler: Wolf (family 1) = general / tier A, teaches 17255
    local lines = hover(b, 118)
    assertTrue(#lines >= 2, "expected family + rank lines")
    assertTrue(string.find(lines[1], "|cff159908General|r", 1, true), "spec colored general")
    assertTrue(string.find(lines[1], "|cffa335eeA|r", 1, true), "tier colored A")
    assertTrue(anyContains(lines, "Spell17255"), "rank line present")
end)

test("hunter Vanilla: offense/S-tier mob (Cat)", function()
    local b = T.boot("HUNTER")
    -- npc 681 Young Stranglethorn Tiger: Cat (family 2) = offense / S
    local lines = hover(b, 681)
    assertTrue(string.find(lines[1], "|cffa40000Offense|r", 1, true), "spec colored offense")
    assertTrue(string.find(lines[1], "|cffff8000S|r", 1, true), "tier colored S")
end)

test("hunter Vanilla: unrated family shows spec without tier", function()
    local b = T.boot("HUNTER")
    b.ns.FAMILY_INFO[1].tier = nil -- pretend Wolf were unrated
    local lines = hover(b, 118)
    assertTrue(string.find(lines[1], "|cff159908General|r", 1, true), "spec still shown")
    assertFalse(string.find(lines[1], "Tier", 1, true) ~= nil, "no tier part")
end)

test("hunter Vanilla: tooltipFamilyInfo=false drops only the family line", function()
    local b = T.boot("HUNTER")
    b.ns.db.tooltipFamilyInfo = false
    local lines = hover(b, 118)
    assertTrue(anyContains(lines, "Spell17255"), "rank lines stay")
    assertFalse(anyContains(lines, "General"), "no family line")
end)

test("hunter Vanilla: beastTooltips=false drops everything", function()
    local b = T.boot("HUNTER")
    b.ns.db.beastTooltips = false
    local lines = hover(b, 118)
    assertEqual(#lines, 0, "no lines with module off")
end)

test("hunter Vanilla: non-tame npc gets no lines", function()
    local b = T.boot("HUNTER")
    local lines = hover(b, 999999)
    assertEqual(#lines, 0)
end)

test("hunter Vanilla: non-teaching beast still gets the family line", function()
    local b = T.boot("HUNTER")
    -- a Barrens raptor: no Vanilla raptor teaches anything, so the npc
    -- is not in TAME_MOBS - the family resolves via UnitCreatureFamily
    b.m.state.petFamily = "Raptor"
    local lines = hover(b, 3254) -- Sunscale Screecher
    assertEqual(#lines, 1, "exactly the family line")
    assertTrue(string.find(lines[1], "|cffa40000Offense|r", 1, true), "raptor spec")
    assertTrue(string.find(lines[1], "|cffff8000S|r", 1, true), "raptor tier S")
    assertFalse(anyContains(lines, "Spell"), "no rank lines")
    -- with the family option off, nothing at all
    b.ns.db.tooltipFamilyInfo = false
    assertEqual(#hover(b, 3254), 0, "option off = no line")
end)

test("hunter TBC: family line shows spec but no tier (untiered data)", function()
    local b = T.boot("HUNTER", nil, "TBC")
    local lines = hover(b, 118) -- Prowler exists on TBC too
    assertTrue(string.find(lines[1], "|cff159908General|r", 1, true), "spec shown on TBC")
    assertFalse(string.find(lines[1], "Tier", 1, true) ~= nil, "no tier on TBC")
end)

test("hunter: pet unit shows family line only, resolved by localized name", function()
    local b = T.boot("HUNTER")
    -- a tamed Prowler (Wolf): family comes from UnitCreatureFamily, and
    -- NO teach lines may appear on an active pet
    local lines = hoverPet(b, 118, "Wolf")
    assertEqual(#lines, 1, "exactly the family line")
    assertTrue(string.find(lines[1], "|cff159908General|r", 1, true), "wolf spec")
    assertTrue(string.find(lines[1], "|cffa335eeA|r", 1, true), "wolf tier")
    assertFalse(anyContains(lines, "Spell17255"), "no teach lines on a pet")
    -- localized client: ruRU cat name resolves via FAMILY_BY_NAME
    lines = hoverPet(b, 118, "Кошка")
    assertTrue(string.find(lines[1], "|cffa40000Offense|r", 1, true), "ruRU cat spec")
end)

test("hunter: pet family falls back to the tamed npc id", function()
    local b = T.boot("HUNTER")
    -- UnitCreatureFamily unavailable/unknown -> npc 118 is a Wolf mob
    local lines = hoverPet(b, 118, nil)
    assertEqual(#lines, 1, "family line via npc fallback")
    assertTrue(string.find(lines[1], "|cff159908General|r", 1, true), "wolf spec")
end)

test("hunter: pet line respects tooltipFamilyInfo, ignores demons", function()
    local b = T.boot("HUNTER")
    b.ns.db.tooltipFamilyInfo = false
    assertEqual(#hoverPet(b, 118, "Wolf"), 0, "option off = no pet line")
    b.ns.db.tooltipFamilyInfo = true
    -- a warlock's Imp: not a hunter family, npc not tameable -> nothing
    assertEqual(#hoverPet(b, 416, "Imp"), 0, "no line on demons")
end)

test("hunter: modern TooltipDataProcessor path renders once, guarded", function()
    local b = T.boot("HUNTER", function(m)
        m.Enum = { TooltipDataType = { Unit = 2 } }
        m.TooltipDataProcessor = {
            AddTooltipPostCall = function(dataType, fn)
                m.__tdpType, m.__tdp = dataType, fn
            end,
        }
    end)
    assertEqual(b.m.__tdpType, 2, "registered for unit tooltips")
    local tip = b.m.GameTooltip
    tip.__lines = {}
    b.m.__tdp(tip, { guid = "Creature-0-4170-1-160-118-0000232C09" }) -- Prowler
    assertTrue(#tip.__lines >= 2, "modern path renders family + rank lines")
    assertTrue(string.find(tip.__lines[1], "|cff159908General|r", 1, true), "family line")
    -- the legacy hook is registered too: on a client firing both, the
    -- once-per-tooltip guard must prevent a double render
    local count = #tip.__lines
    b.m.FireHooks(tip, "OnTooltipSetUnit", tip)
    assertEqual(#tip.__lines, count, "guard blocks the second path")
    -- next tooltip: OnTooltipCleared resets the guard
    b.m.FireHooks(tip, "OnTooltipCleared", tip)
    tip.__lines = {}
    b.m.__tdp(tip, { guid = "Creature-0-4170-1-160-118-0000232C09" })
    assertTrue(#tip.__lines >= 2, "renders again after clear")
end)

test("warlock: no beast tooltip hook at all", function()
    local b = T.boot("WARLOCK")
    local lines = hover(b, 118)
    assertEqual(#lines, 0, "hook must not be installed for non-hunters")
end)
