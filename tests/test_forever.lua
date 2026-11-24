-- WoW Forever flavor: the addon booted through the Retail-shaped API mock
-- (legacy globals removed - a direct GetSpellInfo / GetPetTrainingPoints /
-- CRAFT_SHOW registration fails the boot like it would in game), the list
-- docked into the Retail-engine spellbook, Beast Training via the trainer frame, the
-- "unverified" beast marker and the tame collector (TameLog.lua).
local T = _G.PT_TEST
local test, assertEqual, assertTrue, assertFalse =
    T.test, T.assertEqual, T.assertTrue, T.assertFalse

local function anyContains(lines, needle)
    for _, l in ipairs(lines) do
        if string.find(l, needle, 1, true) then return true end
    end
    return false
end

local function bootForever(class, setup, plainToc)
    return T.boot(class or "HUNTER", setup, "Forever", plainToc)
end

-- ------------------------------------------------------------ boot / data

test("forever: hunter boots on the Retail API shape, Forever data loaded", function()
    local b = bootForever("HUNTER")
    assertTrue(b.ns.isForever, "isForever flag")
    assertFalse(b.ns.isTBC, "not TBC")
    assertEqual(b.ns.PET_FAMILIES[319], "Fox", "Fox family")
    assertEqual(b.ns.PET_FAMILIES[26], "Bird of Prey", "Owl renamed")
    assertEqual(b.ns.FAMILY_BY_NAME["Fuchs"], 319, "deDE Fox name")
    assertTrue(b.ns.ABILITY_BY_SPELL[1310612], "Trickster's Dance rank")
    assertEqual(b.ns.ABILITY_BY_SPELL[1310612].level, 20, "Trickster's Dance pet level")
    assertEqual(next(b.ns.FAMILY_INFO), nil, "no family info on Forever")
end)

test("forever: warlock boots, demon data is the verified Era set", function()
    local b = bootForever("WARLOCK")
    assertTrue(b.ns.isWarlock, "warlock flag")
    assertEqual(b.ns.DEMON_FAMILY_BY_NAME["Imp"], 23)
    assertTrue(b.ns.GRIMOIRE_BY_ITEM and next(b.ns.GRIMOIRE_BY_ITEM), "grimoires present")
end)

test("forever: Era beasts are unverified, beta-confirmed ones are not", function()
    local ns = bootForever("HUNTER").ns
    assertEqual(ns.TAME_MOBS[118].unverified, true, "Prowler carried over")
    assertEqual(ns.TAME_MOBS[250874].unverified, nil, "Vuldren Alpha confirmed")
    assertEqual(ns.TAME_MOBS[250874].family, 319, "Vuldren Alpha is a Fox")
    -- bats and birds of prey lost Screech on Forever: no such teach left
    for npcId, mob in pairs(ns.TAME_MOBS) do
        if mob.family == 24 or mob.family == 26 then
            for _, spellId in ipairs(mob.teaches) do
                assertTrue(ns.ABILITY_BY_SPELL[spellId].ability.key ~= "demoralizingscreech",
                    "mob " .. npcId .. " still teaches Screech")
            end
        end
    end
    local vanilla = T.boot("HUNTER").ns
    for npcId, mob in pairs(vanilla.TAME_MOBS) do
        assertEqual(mob.unverified, nil, "Vanilla mob " .. npcId .. " must be verified")
    end
end)

test("forever: confirmations up to 2026-11-22 (tools/ForeverPetData/confirmed_sources.csv)", function()
    local ns = bootForever("HUNTER").ns
    -- 165189 is "Generic Hunter Pet" (every tamed pet), the wild Galestrider is 251661
    assertEqual(ns.TAME_MOBS[165189], nil, "no beast under the generic pet id")
    -- a later beta patch emptied the low Galestriders' spellbook (beastmaster.io
    -- 2026-10-11) and took Dismember from the Deviate Crocolisk (2026-10-10):
    -- the later report wins over the September one
    assertEqual(ns.TAME_MOBS[251661], nil, "Galestrider: teaches nothing any more")
    local croc = ns.TAME_MOBS[5053]
    assertEqual(table.concat(croc.teaches, ","), "17256", "Deviate Crocolisk: Bite 3 only")
    assertEqual(croc.unverified, nil, "Bite 3 confirmed")
    assertEqual(ns.TAME_MOBS[248299].teaches[1], 16828, "Elmpaw: Claw 2 (was 3)")
    assertEqual(#ns.TAME_MOBS[248299].teaches, 1, "Elmpaw: the Claw 3 entry is gone, not kept with '?'")
    assertEqual(ns.TAME_MOBS[270196].teaches[1], 1265054, "Jai'vhanel: Mine! 1 (empty in September)")
    -- Era beasts confirmed on the beta, and new sources of the family specials
    for _, npcId in ipairs({ 154, 833, 1191, 1778, 3127, 3247, 14266 }) do
        assertEqual(ns.TAME_MOBS[npcId].unverified, nil, "Era beast " .. npcId .. " confirmed")
    end
    assertFalse(ns.IsRankUnverified(ns.TAME_MOBS[1765], 17255), "Worg: Bite 2 seen")
    assertTrue(ns.IsRankUnverified(ns.TAME_MOBS[1765], 24604), "Worg: Furious Howl 1 not yet")
    assertTrue(ns.IsRankUnverified(ns.TAME_MOBS[3653], 17256), "Kresh: Bite 3 not yet")
    -- live-server confirmations (beastmaster.io changelog), npc ids from its data
    -- or Wowhead where its card borrows another beast's model id
    local hound = ns.TAME_MOBS[272386]
    assertEqual(hound.name, "Snickerfang Matriarch"); assertEqual(hound.unverified, nil, "confirmed")
    assertEqual(hound.teaches[1], 1265042, "Tendon Rip 5")
    assertEqual(ns.TAME_MOBS[261786].teaches[1], 1265068, "Ironhide Ravasaur: Savage Rend 4")
    assertEqual(ns.TAME_MOBS[261786].zoneIds[1], -3001, "The Shaper's Terrace (instance)")
    -- Petopia's Forever list: Forever beasts, but unverified ("?")
    assertEqual(ns.TAME_MOBS[266851].unverified, true, "Ukorsbane (Petopia; bm alone stays pending)")
    assertEqual(ns.TAME_MOBS[3246].unverified, true, "Fleeting Plainstrider: Petopia entry")
    assertEqual(table.concat(ns.TAME_MOBS[3246].teaches, ","), "1742,1265899", "Petopia: Cower 1 + Dust Cloud 1")
    assertEqual(ns.TAME_MOBS[1188].teaches[1], 1264494, "Grizzled Black Bear: Swipe 1")
    assertEqual(ns.TAME_MOBS[1184].teaches[1], 1265843, "Cliff Lurker: Web 1")
    assertEqual(ns.TAME_MOBS[2971].teaches[1], 24423, "Taloned Swoop: Demoralizing Screech 1")
    assertEqual(ns.TAME_MOBS[274300].name, "Coldrasp", "npc id found")
    assertEqual(ns.TAME_MOBS[250927].name, "Shadowgale Ursera", "official name")
    -- tamed on the beta and teach nothing: not listed
    assertEqual(ns.TAME_MOBS[3256], nil, "Sunscale Scytheclaw (own tame log)")
    assertEqual(ns.TAME_MOBS[276111], nil, "Ghostfang")
    -- off-family Savage Rend (lost after the tame) is not a source; Mystmane
    -- stays only with Petopia's (unverified) Swipe 1
    assertEqual(ns.TAME_MOBS[259388].unverified, true, "Mystmane (bear) not confirmed")
    assertEqual(table.concat(ns.TAME_MOBS[259388].teaches, ","), "1264494", "Mystmane: Swipe 1 only")
    for _, m in ipairs(ns.MOBS_BY_SPELL[1265065]) do
        assertEqual(m.family, 11, m.name .. " teaches Savage Rend but is no raptor")
    end
end)

test("forever: Sonic Blast - bat special granted server-side, sources known up to rank 4", function()
    local ns = bootForever("HUNTER").ns
    local r1 = ns.ABILITY_BY_SPELL[1264478]
    assertTrue(r1, "Sonic Blast rank 1")
    assertTrue(r1.ability.families[24], "bats")
    assertFalse(r1.ability.families[26], "not birds of prey")
    assertEqual(#r1.ability.ranks, 5, "five ranks")
    assertEqual(r1.src, "w", "learned by taming")
    assertEqual(ns.ABILITY_BY_TEACH[1264483], r1, "teach spell of rank 1")
    assertEqual(ns.ABILITY_BY_SPELL[1264482].level, 60, "rank 5 pet level")
    local names = {}
    for _, m in ipairs(ns.MOBS_BY_SPELL[1264478]) do names[m.name] = m end
    assertTrue(names["Vile Bat"] and names["Blood Seeker"], "rank 1: the Shadowfang Keep bats")
    assertEqual(names["Vile Bat"].unverified, nil, "confirmed in game")
    assertTrue(ns.MOBS_BY_SPELL[1264481], "rank 4 has a source (Plaguebat)")
    assertEqual(ns.MOBS_BY_SPELL[1264482], nil, "rank 5: no source beast yet")
end)

test("forever: pet trainer prices are the ones seen on the beta", function()
    local ns = bootForever("HUNTER").ns
    assertEqual(ns.ABILITY_BY_SPELL[24488].money, 440, "Shadow Resistance 1 (Era data: 40)")
    assertEqual(ns.ABILITY_BY_SPELL[4190].money, 1400, "Great Stamina 4 (Era data: 1260)")
    assertEqual(ns.ABILITY_BY_SPELL[14921].money, 10000, "Growl 7 (Era data: 9000)")
    assertEqual(ns.ABILITY_BY_SPELL[4188].money, 120, "Great Stamina 2 - below level 20 unchanged")
end)

test("forever: plain .toc file list - Forever data wins there, is inert on Vanilla", function()
    local f = bootForever("HUNTER", nil, true).ns
    assertEqual(f.PET_FAMILIES[319], "Fox", "Forever data replaced the Vanilla tables")
    assertTrue(f.TAME_MOBS[250874], "Forever beast list")
    assertEqual(next(f.FAMILY_INFO), nil, "Forever family info (empty) replaced Vanilla's")

    local v = T.boot("HUNTER", nil, "Vanilla", true).ns
    assertEqual(v.PET_FAMILIES[319], nil, "no Fox on Vanilla")
    assertEqual(v.PET_FAMILIES[26], "Owl", "Vanilla family names intact")
    assertEqual(v.TAME_MOBS[250874], nil, "no Forever beasts on Vanilla")
    assertTrue(v.FAMILY_INFO[1], "Vanilla family info intact")
    local w = T.boot("WARLOCK", nil, "Vanilla", true).ns
    assertTrue(next(w.GRIMOIRE_BY_ITEM), "Vanilla demon data intact")
end)

-- ------------------------------------------------------------ list in the book

-- snapshot of the KEYS of Blizzard's frames: the modern host must never
-- write into them (taint = dead spell buttons), only post-hook methods
local function keysOf(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    return table.concat(keys, ",")
end

local function blizzardFrames(m)
    local psf = m.PlayerSpellsFrame
    local book = psf.SpellBookFrame
    local frames = { psf, book, book.CategoryTabSystem }
    for _, t in ipairs(book.CategoryTabSystem.tabs) do frames[#frames + 1] = t end
    return frames
end

local function click(frame) frame:GetScript("OnClick")(frame) end

test("forever: own icon tab beside Blizzard's tabs, list drawn inside the book", function()
    local before
    local b = bootForever("HUNTER", function(m)
        m.state.petFamily = "Fox"
        m.state.petLevel = 20
        before = {}
        for i, f in ipairs(blizzardFrames(m)) do before[i] = keysOf(f) end
    end)
    local book = b.m.PlayerSpellsFrame.SpellBookFrame
    local tabSystem = book.CategoryTabSystem
    local tab, overlay = b.env.PetTipsSpellbookTab, b.env.PetTipsTrainingFrame
    assertTrue(tab and overlay, "tab + overlay created")
    -- WhatsTraining-style: both live on the spellbook WINDOW (below its
    -- border), never inside the book or their tab system
    assertEqual(tab:GetParent(), b.m.PlayerSpellsFrame, "tab lives on the window, not in their tab system")
    assertEqual(overlay:GetParent(), b.m.PlayerSpellsFrame, "list is part of the window")
    assertFalse(overlay:IsShown(), "their page until our tab is clicked")
    assertFalse(tab:IsShown(), "no tab while the book is closed")

    book:Show()
    click(tab)
    assertTrue(tab:GetChecked() and overlay:IsShown(), "tab click opens the list")
    b.ns.TrainingListDebug()
    assertTrue(anyContains(b.m.__prints, "family=319"), "list sees the Fox family")

    -- same tab re-selected = a spell data refresh: the list stays
    tabSystem:SetTabVisuallySelected(1)
    assertTrue(overlay:IsShown(), "data refresh keeps the list open")
    -- another tab = the player wants that page
    tabSystem:SetTabVisuallySelected(2)
    assertFalse(overlay:IsShown(), "their tab click closes the list")
    assertFalse(tab:GetChecked(), "our tab deselected")

    -- closing the book resets to their page
    click(tab)
    book:Hide()
    book:Show()
    assertFalse(overlay:IsShown(), "reopened book shows their page")

    -- options toggle
    b.ns.db.enableList = false
    b.ns.UpdateTrainingTab()
    assertFalse(tab:IsShown(), "tab hidden with the feature off")

    -- nothing was written into Blizzard's frames
    for i, f in ipairs(blizzardFrames(b.m)) do
        assertEqual(keysOf(f), before[i], "Blizzard frame " .. i .. " got foreign keys")
    end
    assertEqual(#tabSystem.tabs, 3, "their tab list untouched")
end)

test("forever: stand-in covers their still-selected tab; clicking it returns to that page", function()
    local b = bootForever("HUNTER")
    local book = b.m.PlayerSpellsFrame.SpellBookFrame
    local tabSystem = book.CategoryTabSystem
    tabSystem:SetTabVisuallySelected(2)
    book:Show()
    click(b.env.PetTipsSpellbookTab)

    local cover = b.env.PetTipsTrainingFrame.returnTab
    assertTrue(cover and cover:IsShown(), "cover shown while the list is open")
    assertEqual(cover.tooltip, "Tab2", "cover mirrors their selected tab")
    click(cover)
    assertFalse(b.env.PetTipsTrainingFrame:IsShown(), "back on their page")
    assertFalse(cover:IsShown(), "cover gone")
    assertEqual(tabSystem.selectedTabID, 2, "their selection never changed")
end)

test("forever: the book is load-on-demand - docks when Blizzard_PlayerSpells arrives", function()
    local parked
    local b = bootForever("HUNTER", function(m)
        parked = m.PlayerSpellsFrame
        m.PlayerSpellsFrame = nil
    end)
    assertEqual(b.env.PetTipsSpellbookTab, nil, "nothing to dock into yet")
    b.ns.RefreshTrainingList() -- must be harmless without UI
    b.ns.UpdateTrainingTab()
    b.m.PlayerSpellsFrame = parked
    b.m.Fire("ADDON_LOADED", "Blizzard_PlayerSpells")
    assertTrue(b.env.PetTipsSpellbookTab, "docked after the load")
end)

test("forever: /pettips show opens the list, or arms it for the next book open", function()
    local b = bootForever("HUNTER")
    local book = b.m.PlayerSpellsFrame.SpellBookFrame
    b.env.SlashCmdList.PETTIPS("show") -- book closed: the addon never opens it itself
    assertFalse(b.env.PetTipsTrainingFrame:IsShown(), "not opened behind the player's back")
    assertTrue(anyContains(b.m.__prints, "open your spellbook"), "hint printed")
    book:Show()
    assertTrue(b.env.PetTipsTrainingFrame:IsShown(), "armed: opens with the book")

    book:Hide(); book:Show()
    assertFalse(b.env.PetTipsTrainingFrame:IsShown(), "armed once only")
    b.env.SlashCmdList.PETTIPS("show")
    assertTrue(b.env.PetTipsTrainingFrame:IsShown(), "book open: straight to the list")

    local v = T.boot("HUNTER")
    local opened = false
    v.m.Settings.OpenToCategory = function() opened = true end
    v.env.SlashCmdList.PETTIPS("show")
    assertTrue(opened, "Era/TBC: the list is a spellbook tab - the command opens the settings")
end)

-- ------------------------------------------------------------ WhatsTraining-style page

local function shownItems(pool)
    local out = {}
    for _, f in ipairs(pool) do
        if f:IsShown() and f.item then out[#out + 1] = f.item end
    end
    return out
end

-- a click the way the game delivers it: the script, then HookScript hooks
local function press(frame)
    frame:GetScript("OnClick")(frame)
    for _, fn in ipairs(frame.__hooks.OnClick or {}) do fn(frame) end
end

local function wolf(m)
    m.state.petFamily = "Wolf"
    m.state.petLevel = 20
    m.state.playerLevel = 30
end

test("forever book: the ledger draws the display list - one band per section, one row per rank", function()
    local b = bootForever("HUNTER", wolf)
    b.m.PlayerSpellsFrame.SpellBookFrame:Show()
    click(b.env.PetTipsSpellbookTab)
    local headers, ranks = 0, 0
    for _, item in ipairs(b.ns.TL.BuildDisplayList()) do
        assertTrue(item.kind ~= "family", "the family selector sits in the page header on Forever")
        if item.kind == "header" then
            headers = headers + 1
            assertTrue(item.key and item.count and item.count > 0, "band knows its section and size")
        elseif item.kind == "rank" then
            ranks = ranks + 1
        end
    end
    assertTrue(ranks > 0, "a level-20 wolf has something to show")
    local t = b.ns.ForeverBook._test
    assertEqual(#shownItems(t.pages[1].headings), headers, "one band per section")
    assertEqual(#shownItems(t.pages[1].rows), ranks, "one row per rank")
    assertFalse(t.pages[2]:IsShown(), "minimized book: a single page")
end)

test("forever book: warlock ledger - grimoire prices, no source filters in the menu", function()
    local generators = {}
    local b = bootForever("WARLOCK", function(m)
        m.state.petFamily = "Imp"
        m.state.playerLevel = 30
        m.state.money = 100000
        m.MenuUtil = { CreateContextMenu = function(_, generator) generators[#generators + 1] = generator end }
    end)
    b.m.PlayerSpellsFrame.SpellBookFrame:Show()
    click(b.env.PetTipsSpellbookTab)
    local main = b.ns.ForeverBook._test.pages[1]
    assertTrue(#shownItems(main.rows) > 0, "imp ranks listed")
    assertTrue(b.ns.TL.StatusText():find("Grimoires to buy", 1, true), "what the next vendor trip costs")
    click(main.settings)
    local titles = {}
    generators[1](main.settings, {
        CreateTitle = function(_, t) titles[#titles + 1] = t end,
        CreateDivider = function() end,
        CreateCheckbox = function(_, t) titles[#titles + 1] = t end,
        CreateButton = function(self, t) titles[#titles + 1] = t; return self end,
    })
    for _, t in ipairs(titles) do assertTrue(t ~= "Taming", "no taming filter for demons") end
end)

test("forever book: the maximized book flows the ledger over both pages", function()
    local b = bootForever("HUNTER", wolf)
    local book = b.m.PlayerSpellsFrame.SpellBookFrame
    book.isMinimized = false
    book:Show()
    click(b.env.PetTipsSpellbookTab)
    local t = b.ns.ForeverBook._test
    assertTrue(t.pages[2]:IsShown(), "right page in use")

    local items = b.ns.TL.BuildDisplayList()
    local ranks = 0
    for _, item in ipairs(items) do if item.kind == "rank" then ranks = ranks + 1 end end
    local halves = t.Paginate(items, 200)
    assertTrue(#halves > 1, "a 200px page cannot hold it all")
    local seen = 0
    for _, half in ipairs(halves) do
        assertTrue(half[1].kind ~= "rank", "a page never starts with a row without its band")
        for i, item in ipairs(half) do
            if item.kind == "rank" then seen = seen + 1 end
            if i == 1 and item.label then
                assertTrue(item.label:find("continued", 1, true), "a cut section repeats its band")
            end
        end
    end
    assertEqual(seen, ranks, "every rank on exactly one page")
end)

test("forever book: one list at a time next to WhatsTraining's own tab", function()
    local wtLauncher, wtRoot
    local b = bootForever("HUNTER", function(m)
        wolf(m)
        wtRoot = m.CreateFrame("Frame", "WhatsTrainingOverlay", m.UIParent)
        wtRoot:Hide()
        wtLauncher = m.CreateFrame("Button", "WhatsTrainingLauncher", m.UIParent)
        wtLauncher:SetScript("OnClick", function() wtRoot:SetShown(not wtRoot:IsShown()) end)
        wtLauncher.Click = press
    end)
    local tab, overlay = b.env.PetTipsSpellbookTab, b.env.PetTipsTrainingFrame
    b.m.PlayerSpellsFrame.SpellBookFrame:Show()

    press(wtLauncher)
    assertTrue(wtRoot:IsShown(), "WhatsTraining open")
    press(tab)
    assertFalse(wtRoot:IsShown(), "our tab closes WhatsTraining through its own tab")
    assertTrue(overlay:IsShown() and tab:GetChecked(), "ours open")

    press(wtLauncher)
    assertTrue(wtRoot:IsShown(), "their tab opens theirs")
    assertFalse(overlay:IsShown(), "ours steps aside")
    assertFalse(tab:GetChecked(), "our tab deselected")
end)

-- narrow book with WhatsTraining loaded (seen in game 2026-11-23): our tab
-- hung UNDER theirs. Now: beside theirs when gap + one tab fits up to the
-- search box (WT's own rule), else hanging from the strip right of theirs.
local function placement(searchLeft)
    local points = {}
    local b = bootForever("HUNTER", function(m)
        local book = m.PlayerSpellsFrame.SpellBookFrame
        local tabs = book.CategoryTabSystem
        tabs.GetRight = function() return 300 end
        tabs.GetEffectiveScale = function() return 1 end
        local search = m.CreateFrame("EditBox", nil, book)
        search.GetLeft = function() return searchLeft end
        search.GetEffectiveScale = function() return 1 end
        book.SearchBox = search
        local wtRoot = m.CreateFrame("Frame", "WhatsTrainingOverlay", m.UIParent)
        wtRoot:Hide()
        local wt = m.CreateFrame("Button", "WhatsTrainingLauncher", m.UIParent)
        wt.GetRight = function() return 352 end -- 300 + 8 + 44
        wt.GetEffectiveScale = function() return 1 end
    end)
    local tab = b.env.PetTipsSpellbookTab
    tab.SetPoint = function(_, point, rel, relPoint, x, y)
        points[#points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
    end
    b.m.PlayerSpellsFrame.SpellBookFrame:Show()
    return points[#points], b
end

test("forever book: our tab sits beside WhatsTraining's when one tab fits", function()
    local p, b = placement(352 + 44) -- exactly enough: flush, no gap
    assertEqual(p.point, "LEFT", "beside, not hanging")
    assertEqual(p.rel, b.env.WhatsTrainingLauncher, "right of their tab")
    assertEqual(p.x, 0)
end)

test("forever book: no room - ours hangs from the strip RIGHT of WhatsTraining's tab, not under it", function()
    local p, b = placement(352 + 30)
    assertEqual(p.point, "TOPLEFT", "hanging")
    assertEqual(p.rel, b.m.PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem, "from the tab strip")
    assertEqual(p.x, 52 + 2, "x offset clears their tab")
end)

test("forever book: the settings menu holds the source and ability filters", function()
    local generators = {}
    local b = bootForever("HUNTER", function(m)
        wolf(m)
        m.MenuUtil = { CreateContextMenu = function(_, generator) generators[#generators + 1] = generator end }
    end)
    b.m.PlayerSpellsFrame.SpellBookFrame:Show()
    click(b.env.PetTipsSpellbookTab)
    local main = b.ns.ForeverBook._test.pages[1]
    click(main.settings)
    assertEqual(#generators, 1, "settings button opens a menu")

    local Description
    Description = function()
        local d = { entries = {} }
        function d:CreateTitle(text) self.entries[#self.entries + 1] = { text = text } end
        function d:CreateDivider() end
        function d:CreateCheckbox(text, isSelected, setSelected, data)
            local e = { text = text, isSelected = isSelected, set = setSelected, data = data }
            self.entries[#self.entries + 1] = e
            return e
        end
        function d:CreateButton(text)
            local sub = Description()
            sub.text = text
            self.entries[#self.entries + 1] = sub
            return sub
        end
        return d
    end
    local root = Description()
    generators[1](main.settings, root)
    local function find(desc, text)
        for _, e in ipairs(desc.entries) do if e.text == text then return e end end
    end

    local taming = find(root, "Taming")
    assertTrue(taming and taming.isSelected(), "taming shown by default")
    taming.set()
    assertFalse(b.ns.TL.sourceFilter.taming, "unticked")
    for _, item in ipairs(b.ns.TL.BuildDisplayList()) do
        if item.kind == "rank" then
            assertTrue(item.entry.src ~= "w", "no taming-only rank left: " .. item.entry.spell)
        end
    end

    local shown = find(root, "Shown abilities")
    assertTrue(shown and #shown.entries > 0, "one checkbox per ability")
    local first = shown.entries[1]
    first.set(first.data)
    assertTrue(b.ns.db.hiddenAbilities[first.data], "ability hidden")
    assertFalse(first.isSelected(first.data), "checkbox follows")
end)

-- ------------------------------------------------------------ settings

-- Forever builds the category inside its secure settings delegate with a
-- generated NUMERIC id: Options.lua leaves it alone (no taint), and the
-- plain /pettips opens the category by that number
test("forever: settings keep the generated numeric category id - /pettips opens it", function()
    local opened = {}
    local b = bootForever("HUNTER", function(m)
        m.Settings.RegisterVerticalLayoutCategory = function()
            local category = { ID = 42 }
            function category:GetID() return self.ID end
            return category, { AddInitializer = function() end }
        end
        m.Settings.OpenToCategory = function(id)
            assertEqual(type(id), "number", "OpenToCategory gets the numeric id")
            opened[#opened + 1] = id
        end
    end)
    assertEqual(b.ns.settingsCategory.ID, 42, "generated id left alone")
    b.env.SlashCmdList.PETTIPS("")
    assertEqual(#opened, 1, "plain /pettips opens the settings")
    assertEqual(opened[1], 42, "our category")
end)

-- ------------------------------------------------------------ known ranks

test("forever: Beast Training is the trainer frame in pet mode - listed = known", function()
    local b = bootForever("HUNTER")
    b.m.state.trainerType = 3
    b.m.state.services = {
        { name = "Spell17253", rank = "Rank 2", category = "available" },   -- Bite 2
        { name = "Spell1310612", rank = "Rank 1", category = "unavailable" }, -- Trickster's Dance
        { name = "Something else", rank = "Rank 1", category = "available" },
    }
    b.m.state.services[2].cost = 10
    b.m.Fire("TRAINER_SHOW")
    assertTrue(b.ns.chardb.knownTeach[17255], "Bite 2 known")
    assertTrue(b.ns.chardb.knownTeach[1310612], "Trickster's Dance known")
    assertTrue(b.ns.chardb.scannedBeastTraining, "counts as the Beast Training sync")
    -- raw listing for offline verification (SavedVariables)
    local dump = b.ns.chardb.lastBeastTraining
    assertTrue(dump and dump.beastTraining, "raw Beast Training listing kept")
    assertEqual(dump.build, "70205", "build recorded")
    assertEqual(#dump.services, 3, "every service dumped")
    assertEqual(dump.services[1], "Spell17253|Rank 2|available|0|17255|nil", "name|rank|category|cost|spell|tooltip spell")
    assertEqual(dump.services[2], "Spell1310612|Rank 1|unavailable|10|1310612|nil", "TP cost recorded")
    assertEqual(b.ns.chardb.lastPetTrainer, nil, "not an NPC trainer listing")
end)

test("forever: NPC pet trainer - only 'used' services are known (Retail return order)", function()
    local b = bootForever("HUNTER")
    b.m.state.trainerType = 0
    b.m.state.services = {
        { name = "Spell2649", rank = "Rank 1", category = "used" },      -- Growl 1
        { name = "Spell2649", rank = "Rank 2", category = "available" }, -- Growl 2
    }
    b.m.Fire("TRAINER_SHOW")
    assertTrue(b.ns.chardb.knownTeach[2649], "Growl 1 bought")
    assertEqual(b.ns.chardb.knownTeach[14916], nil, "Growl 2 not bought")
    assertFalse(b.ns.chardb.scannedBeastTraining, "an NPC trainer is not the Beast Training sync")
end)

-- ------------------------------------------------------------ tooltips

local function hover(b, guid)
    local m = b.m
    m.GameTooltip.GetUnit = function() return "SomeMob", "mouseover" end
    m.UnitGUID = function() return guid end
    m.FireHooks(m.GameTooltip, "OnTooltipCleared", m.GameTooltip)
    m.GameTooltip.__lines = {}
    m.FireHooks(m.GameTooltip, "OnTooltipSetUnit", m.GameTooltip)
    return m.GameTooltip.__lines
end

test("forever: beast tooltip marks unverified beasts with '?', confirmed ones not", function()
    local b = bootForever("HUNTER")
    local lines = hover(b, "Creature-0-4170-1-160-118-0000232C09") -- Prowler (Era list)
    assertTrue(anyContains(lines, "Spell17255"), "rank line")
    assertTrue(anyContains(lines, "|cff909090?|r"), "unverified mark")

    lines = hover(b, "Creature-0-4170-1-160-250874-0000232C09") -- Vuldren Alpha
    assertTrue(anyContains(lines, "Spell17255"), "Bite 2 line")
    assertFalse(anyContains(lines, "Spell1310612"), "no Trickster's Dance since a beta patch")
    assertFalse(anyContains(lines, "|cff909090?|r"), "confirmed beast has no mark")
end)

test("forever: the '?' is per rank - a confirmed beast marks only its Era-only rank", function()
    local b = bootForever("HUNTER")
    local lines = hover(b, "Creature-0-4170-1-160-1765-0000232C09") -- Worg: Bite 2 seen, Howl not
    local bite, howl
    for _, l in ipairs(lines) do
        if l:find("Spell17255", 1, true) then bite = l end
        if l:find("Spell24604", 1, true) then howl = l end
    end
    assertTrue(bite and not bite:find("|cff909090?|r", 1, true), "Bite 2 line without '?'")
    assertTrue(howl and howl:find("|cff909090?|r", 1, true), "Furious Howl 1 line with '?'")
    -- the list's rank tooltip: the sources of Furious Howl 1
    b.ns.db.mobLines = 99
    b.ns.ShowRankTooltip(b.ns.ABILITY_BY_SPELL[24604], b.m.UIParent)
    local worg, coldrasp
    for _, l in ipairs(b.m.GameTooltip.__lines) do
        if l:sub(1, 7) == "Worg  (" then worg = l end
        if l:sub(1, 11) == "Coldrasp  (" then coldrasp = l end
    end
    assertTrue(worg and worg:find("|cff909090?|r", 1, true), "Worg listed with '?' for Howl")
    assertTrue(coldrasp and not coldrasp:find("|cff909090?|r", 1, true), "Coldrasp confirmed")
end)

test("forever: a secret GUID (combat) leaves the tooltip alone", function()
    local b = bootForever("HUNTER")
    local guid = "Creature-0-4170-1-160-118-0000232C09"
    b.m.state.secrets[guid] = true
    assertEqual(#hover(b, guid), 0, "no lines, no error")
end)

-- ------------------------------------------------------------ tame collector

-- Tame Beast on <npcId>, then the pet appears knowing petSpells
local function tame(b, npcId, name, level, famName, petSpells)
    local s = b.m.state
    s.targetGUID = "Creature-0-4170-1-160-" .. npcId .. "-0000232C09"
    s.targetName, s.targetLevel, s.targetFamily = name, level, famName
    b.m.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-3-0-0-0-1515-0", 1515)
    s.petFamily, s.petLevel = famName, level
    s.petKnown = {}
    for _, id in ipairs(petSpells) do s.petKnown[id] = true end
    s.petSpellbook = petSpells
    b.m.Fire("UNIT_PET", "player")
    b.m.FlushTimers()
end

test("tamelog: a tame matching the data is recorded and confirmed", function()
    local b = bootForever("HUNTER")
    b.m.state.mapId = 2521
    b.m.state.mapInfo[2521] = { name = "Zephras Isle", mapType = 3, parentMapID = 947 }
    tame(b, 250874, "Vuldren Alpha", 10, "Fox", { 17255, 2649 })
    local rec = b.ns.db.tameLog[250874]
    assertTrue(rec, "recorded")
    assertEqual(table.concat(rec.teaches, ","), "17255", "taming ranks")
    assertEqual(table.concat(rec.other, ","), "2649", "trainer-only Growl is logged, not compared")
    assertEqual(rec.family, 319); assertEqual(rec.zone, 2521); assertEqual(rec.count, 1)
    assertEqual(rec.minLevel, 10); assertEqual(rec.build, "70205")
    assertTrue(anyContains(b.m.__prints, "matches the data"), "verdict printed")
end)

test("tamelog: unknown beast = new taming source, usable right away", function()
    local b = bootForever("HUNTER")
    b.m.state.mapId = 1420
    b.m.state.mapInfo[1420] = { name = "Tirisfal Glades", mapType = 3 }
    tame(b, 999001, "Coldrasp", 12, "Wolf", { 24604 }) -- Furious Howl 1
    assertTrue(anyContains(b.m.__prints, "NEW taming source"), "verdict printed")
    local mob = b.ns.TAME_MOBS[999001]
    assertTrue(mob, "added to the beast list")
    assertEqual(mob.family, 1); assertEqual(mob.unverified, nil); assertEqual(mob.zoneIds[1], 1420)
    local found = false
    for _, m in ipairs(b.ns.MOBS_BY_SPELL[24604]) do if m == mob then found = true end end
    assertTrue(found, "linked from the rank")
end)

test("tamelog: a tame that differs corrects the carried-over Era entry", function()
    local b = bootForever("HUNTER")
    assertEqual(b.ns.TAME_MOBS[118].teaches[1], 17255, "Era says Bite 2")
    tame(b, 118, "Prowler", 9, "Wolf", { 17253 }) -- knows Bite 1 instead
    assertTrue(anyContains(b.m.__prints, "differs from the data"), "verdict printed")
    assertEqual(table.concat(b.ns.TAME_MOBS[118].teaches, ","), "17253", "observation wins")
    assertEqual(b.ns.TAME_MOBS[118].unverified, nil, "now verified")
    for _, m in ipairs(b.ns.MOBS_BY_SPELL[17255] or {}) do
        assertTrue(m.npc ~= 118, "old link removed")
    end
end)

test("tamelog: a saved log is applied at login", function()
    local b = bootForever("HUNTER", function(m)
        m.PetTipsDB = { tameLog = { [118] = { name = "Prowler", family = 1, minLevel = 9,
            maxLevel = 10, teaches = { 17253 }, other = {}, count = 2 } } }
    end)
    assertEqual(table.concat(b.ns.TAME_MOBS[118].teaches, ","), "17253", "log applied")
    assertEqual(b.ns.TAME_MOBS[118].unverified, nil)
end)

test("tamelog: the pet GUID never names the beast (165189 on Forever)", function()
    local b = bootForever("HUNTER")
    local s = b.m.state
    s.targetGUID = nil -- target GUID unreadable when the cast started
    s.targetName, s.targetLevel, s.targetFamily = "Prowler", 9, "Wolf"
    b.m.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-3", 1515)
    s.petGUID = "Pet-0-4234-0-6610-165189-0202F859E9"
    s.petFamily, s.petLevel = "Wolf", 9
    s.petKnown, s.petSpellbook = { [17255] = true }, { 17255 }
    b.m.Fire("UNIT_PET", "player")
    b.m.FlushTimers()
    assertEqual(next(b.ns.db.tameLog), nil, "nothing recorded under the generic pet id")
    assertTrue(anyContains(b.m.__prints, "could not identify the tamed beast"), "hint printed")
end)

test("tamelog: no pet after the cast (failed tame) records nothing", function()
    local b = bootForever("HUNTER")
    local s = b.m.state
    s.targetGUID, s.targetName, s.targetLevel, s.targetFamily =
        "Creature-0-4170-1-160-118-0000232C09", "Prowler", 9, "Wolf"
    b.m.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-3", 1515)
    s.now = 100 -- a Call Pet minutes later must not count as that tame
    s.petFamily = "Wolf"
    b.m.Fire("UNIT_PET", "player")
    b.m.FlushTimers()
    assertEqual(next(b.ns.db.tameLog), nil, "nothing recorded")
end)

test("tamelog: inactive on Classic Era", function()
    local b = T.boot("HUNTER")
    local s = b.m.state
    s.targetGUID, s.targetName, s.targetLevel, s.targetFamily =
        "Creature-0-4170-1-160-118-0000232C09", "Prowler", 9, "Wolf"
    b.m.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-3", 1515)
    s.petFamily = "Wolf"
    b.m.Fire("UNIT_PET", "player")
    b.m.FlushTimers()
    assertEqual(next(b.ns.db.tameLog), nil, "collector is Forever-only")
end)

-- ------------------------------------------------------------ teach spells

test("forever: the learned-spell event carries the hunter-side teach spell", function()
    local b = bootForever("HUNTER")
    b.m.Fire("LEARNED_SPELL_IN_SKILL_LINE", 7370, 3, false) -- Charge Rank 1 (teach id)
    assertTrue(b.ns.chardb.knownTeach[7371], "pet spell Charge 1 marked known")
    assertTrue(anyContains(b.m.__prints, "learned to teach Spell7371 (rank 1)"), "chat line")
    b.m.Fire("LEARNED_SPELL_IN_SKILL_LINE", 1499, 1, false) -- Freezing Trap: not a pet ability
    assertEqual(b.ns.chardb.knownTeach[1499], nil, "class spell ignored")
end)

test("forever: teach spells known in the spellbook sync the known ranks - no window needed", function()
    local b = bootForever("HUNTER", function(m)
        m.state.playerLevel = 10
        m.state.playerSpells[7370] = true -- Charge 1
        m.state.playerSpells[1853] = true -- Growl 1
    end)
    assertFalse(b.ns.chardb.scannedBeastTraining, "nothing before the spell data settles")
    b.m.FlushTimers() -- the 3 s login probe
    assertTrue(b.ns.chardb.knownTeach[7371] and b.ns.chardb.knownTeach[2649], "both ranks known")
    assertTrue(b.ns.chardb.scannedBeastTraining, "counts as synced")
    assertEqual(b.ns.chardb.teachProbe.known, 2, "probe result stored")
    assertEqual(b.ns.chardb.teachProbe.total, 153, "probe covers every rank")
    assertTrue(anyContains(b.m.__prints, "synced 2 teachable ranks from your spellbook"), "announced once")
    -- a later learn shows up through SPELLS_CHANGED
    b.m.state.playerSpells[14922] = true -- Growl 2
    b.m.Fire("SPELLS_CHANGED")
    assertTrue(b.ns.chardb.knownTeach[14916], "Growl 2 picked up")
end)

test("forever: a probe claiming every teach spell is known is ignored", function()
    local b = bootForever("HUNTER", function(m)
        m.state.playerLevel = 10
        m.IsPlayerSpell = nil
        m.C_SpellBook = m.C_SpellBook -- (placeholder: replaced below)
    end)
    b.m.C_SpellBook.IsSpellKnown = function() return true end
    b.m.FlushTimers()
    assertEqual(next(b.ns.chardb.knownTeach), nil, "nothing applied")
    assertFalse(b.ns.chardb.scannedBeastTraining, "not marked synced")
    assertTrue(b.ns.chardb.teachProbe.suspicious, "flagged for the SavedVariables")
end)

test("vanilla: learned teach spell resolved by name + rank text (no teach ids in the data)", function()
    local b = T.boot("HUNTER", function(m)
        local orig = m.GetSpellInfo
        m.GetSpellInfo = function(id)
            if id == 7370 then return "Spell7371", nil, "icon" end -- teach spell shares the pet spell name
            return orig(id)
        end
        m.state.spellSubtext[7370] = "Rank 1"
    end)
    assertEqual(next(b.ns.ABILITY_BY_TEACH), nil, "Vanilla data has no teach ids")
    b.m.Fire("LEARNED_SPELL_IN_TAB", 7370)
    assertTrue(b.ns.chardb.knownTeach[7371], "resolved through name + rank")
end)

test("forever: Beast Training services without rank text resolve through their tooltip spell", function()
    -- the real 2026-09-22 listing at hunter level 10: no subtext at all,
    -- "Growl" twice, TP as the cost - only the tooltip spell id (the
    -- hunter-side teach spell) tells the rows apart
    local b = bootForever("HUNTER")
    b.m.state.trainerType = 3
    b.m.state.services = {
        { name = "Spell4187", category = "available", cost = 5, spellId = 4195 },   -- Great Stamina 1
        { name = "Spell2649", category = "available", cost = 0, spellId = 1853 },   -- Growl 1
        { name = "Spell24545", category = "available", cost = 1, spellId = 24547 }, -- Natural Armor 1
        { name = "Spell2649", category = "available", cost = 0, spellId = 14922 },  -- Growl 2
        { name = "Spell2649", category = "available", cost = 0 },                   -- no tooltip, no rank: unresolvable
    }
    b.m.Fire("TRAINER_SHOW")
    local known = b.ns.chardb.knownTeach
    assertTrue(known[4187] and known[2649] and known[24545] and known[14916], "all four resolved by teach id")
    assertEqual(b.ns.chardb.lastBeastTraining.services[4], "Spell2649|nil|available|0|14916|14922", "dump carries the tooltip spell")
    assertEqual(b.ns.chardb.lastBeastTraining.services[5], "Spell2649|nil|available|0|nil|nil", "unresolvable row stays nil")
    assertTrue(b.ns.chardb.scannedBeastTraining, "counts as synced")
end)

-- ------------------------------------------------------------ detection
-- Build 1.60.1.70170 moved Forever's WOW_PROJECT_ID from 1 (MAINLINE) to
-- 18 (WOW_PROJECT_CAMELOT). The old MAINLINE test turned isForever off,
-- every Data/Forever file skipped itself and the first pet tooltip threw
-- (BeastTooltips.lua:63, nil FAMILY_BY_NAME). Now the Interface band
-- (16000-19999) OR the project id 18 decides; the rule table at the end
-- pins each half on its own.

local function hoverOwnPet(b)
    local m = b.m
    m.state.petFamily = "Raptor"
    m.GameTooltip.GetUnit = function() return "Raptor", "pet" end
    m.UnitGUID = function() return "Pet-0-4621-1-60191-165189-01002A24FD" end
    m.FireHooks(m.GameTooltip, "OnTooltipCleared", m.GameTooltip)
    m.GameTooltip.__lines = {}
    m.FireHooks(m.GameTooltip, "OnTooltipSetUnit", m.GameTooltip)
    return m.GameTooltip.__lines
end

-- full Forever boots (Interface 16001, inside the band) per project-id shape:
-- { label, WOW_PROJECT_ID, WOW_PROJECT_CAMELOT, WOW_PROJECT_MAINLINE }
for _, case in ipairs({
    { "70170+: ID = CAMELOT = 18", 18, 18, 1 },
    { "up to 70124: ID = MAINLINE = 1", 1, nil, 1 },
    { "constant renamed: ID 18, no CAMELOT", 18, nil, 1 },
    { "unknown future ID", 99, nil, 1 },
    { "no project constants at all", nil, nil, nil },
}) do
    test("forever detection (" .. case[1] .. "): Forever data loads, pet tooltip works", function()
        local b = bootForever("HUNTER", function(m)
            m.WOW_PROJECT_ID, m.WOW_PROJECT_CAMELOT, m.WOW_PROJECT_MAINLINE = case[2], case[3], case[4]
        end)
        assertTrue(b.ns.isForever, "isForever")
        assertFalse(b.ns.isTBC, "not TBC")
        assertEqual(b.ns.FAMILY_BY_NAME["Raptor"], 11, "Forever family map loaded")
        assertEqual(b.ns.PET_FAMILIES[319], "Fox", "Forever data, not Era")
        assertEqual(#hoverOwnPet(b), 0, "own pet: no error, no family line (no Forever tiers)")
        assertTrue(anyContains(hover(b, "Creature-0-4170-1-160-118-0000232C09"), "Spell17255"), "beast rank line")
    end)
end

test("forever detection: Classic Era, TBC Anniversary and Retail are never Forever", function()
    local era = T.boot("HUNTER")
    assertFalse(era.ns.isForever, "Era (Interface 11509, ID 2)")
    assertEqual(era.ns.PET_FAMILIES[319], nil, "Era data (no Fox)")
    local tbc = T.boot("HUNTER", nil, "TBC")
    assertFalse(tbc.ns.isForever, "TBC Anniversary (Interface 20506, ID 5)")
    assertTrue(tbc.ns.isTBC, "TBC flag")
    -- the MAINLINE id is no Forever signal any more
    local retail = T.boot("HUNTER", function(m)
        m.WOW_PROJECT_MAINLINE, m.WOW_PROJECT_ID = 1, 1
        m.GetBuildInfo = function() return "12.1.0", "69933", "Sep 1 2026", 120100, "Version 12.1.0", "Release" end
    end)
    assertFalse(retail.ns.isForever, "Retail (Interface 120100, ID 1)")
end)

-- mock fidelity: each flavor boot answers GetBuildInfo like its real
-- client - all six values, its own Interface number (TBC is no Era clone)
test("forever detection: every flavor boot reports its client's GetBuildInfo", function()
    for _, case in ipairs({ { "Vanilla", 11509 }, { "TBC", 20506 }, { "Forever", 16001 } }) do
        local m = T.boot("HUNTER", nil, case[1]).m
        assertEqual(select("#", m.GetBuildInfo()), 6, case[1] .. ": six values")
        assertEqual(select(4, m.GetBuildInfo()), case[2], case[1] .. ": Interface")
    end
end)

-- The rule row by row: Interface band 16000-19999 OR project id 18
-- (WOW_PROJECT_CAMELOT, the literal 18 once that constant is renamed) -
-- each half also alone, outside the other. Every row boots the Forever API
-- with the plain .toc list (Vanilla + self-guarding Forever data): a false
-- row loads the Era data instead of nothing, so its boot cannot crash for
-- lack of data, and each row proves the data set follows the flag.
-- MAINLINE stays 1 (Blizzard defines it on every game type).
-- { Interface, WOW_PROJECT_ID, WOW_PROJECT_CAMELOT, expected isForever }
for _, row in ipairs({
    { 16001, 18, 18, true },    -- live client (build 70170+)
    { 16001, 1, nil, true },    -- builds up to 70124
    { 16000, 1, nil, true },    -- lower band edge (inclusive)
    { 19999, 1, nil, true },    -- upper band edge
    { 15999, 1, nil, false },
    { 20000, 1, nil, false },   -- upper bound exclusive
    { 26001, 18, 18, true },    -- project id alone, outside the band
    { 26001, 18, nil, true },   -- literal 18: constant renamed
    { 26001, 1, nil, false },   -- MAINLINE is no signal
    { 26001, nil, nil, false }, -- no project id, no CAMELOT constant
    { 11509, 2, nil, false },   -- Classic Era 1.15.9
    { 20506, 5, nil, false },   -- TBC Anniversary 2.5.6
    { 120100, 1, nil, false },  -- Retail 12.1
}) do
    local interface, id, camelot, want = row[1], row[2], row[3], row[4] -- (nil holes: no unpack)
    test(string.format("forever detection rule: Interface %d, ID %s, CAMELOT %s -> %s",
        interface, tostring(id), tostring(camelot), tostring(want)), function()
        local b = bootForever("HUNTER", function(m)
            m.GetBuildInfo = function() return "1.60.1", "70205", "Oct 2 2026", interface, "Version 1.60.1", "Release" end
            m.WOW_PROJECT_ID, m.WOW_PROJECT_CAMELOT = id, camelot
        end, true)
        assertEqual(not not b.ns.isForever, want, "isForever")
        assertEqual(b.ns.PET_FAMILIES[319], want and "Fox" or nil, "Forever data (Fox) iff Forever")
        assertEqual(b.ns.PET_FAMILIES[26], want and "Bird of Prey" or "Owl", "Forever vs Era family names")
    end)
end
