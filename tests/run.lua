-- Headless test runner for PetTips. Needs Lua 5.1 / LuaJIT (setfenv).
-- Run from anywhere:  luajit tests/run.lua      (paths self-locate)
-- Every boot loads the REAL addon files in .toc order into an isolated
-- environment and fires ADDON_LOADED + PLAYER_LOGIN for the given class,
-- so tests exercise exactly what the game would load - including the full
-- UI creation path (against the live frame mocks in wow_mock.lua).

local base = (arg[0] or ""):match("^(.-)tests[/\\]run%.lua$") or ""

local Loader = dofile(base .. "tests/loader.lua")
local buildMocks = dofile(base .. "tests/wow_mock.lua")

-- .toc load order (locales included: they return early on enUS but must
-- at least parse; a syntax error there fails the boot = a test failure).
-- The data folder is the per-flavor split of the real tocs
-- (PetTips_Vanilla.toc / PetTips_TBC.toc / PetTips_Camelot.toc).
-- plainToc = true mirrors PetTips.toc instead, which lists the Vanilla
-- AND the (self-guarding) Forever data files.
local function tocFiles(flavor, plainToc)
    local files = {
        "Core.lua",
        "Compat.lua",
        "Locales/deDE.lua",
        "Locales/frFR.lua",
        "Locales/esES.lua",
        "Locales/ptBR.lua",
        "Locales/ruRU.lua",
        "Data/" .. flavor .. "/FamilyData.lua",
        "Data/" .. flavor .. "/FamilyInfoData.lua",
        "Data/" .. flavor .. "/PetAbilitiesData.lua",
        "Data/" .. flavor .. "/TameMobsData.lua",
        "Data/" .. flavor .. "/DemonAbilitiesData.lua",
    }
    if plainToc then
        for i, f in ipairs(files) do
            files[i] = (f:gsub("^Data/" .. flavor .. "/", "Data/Vanilla/"))
        end
        for _, f in ipairs({ "FamilyData", "FamilyInfoData", "PetAbilitiesData",
            "TameMobsData", "DemonAbilitiesData" }) do
            files[#files + 1] = "Data/Forever/" .. f .. ".lua"
        end
    end
    for _, f in ipairs({ "KnownTraining.lua", "TameLog.lua", "TrainingList.lua",
        "BeastTooltips.lua", "Options.lua" }) do
        files[#files + 1] = f
        -- the Forever book host: PetTips_Camelot.toc and PetTips.toc only
        -- (self-guarding - inert on the Era/TBC spellbook)
        if f == "TrainingList.lua" and (flavor == "Forever" or plainToc) then
            files[#files + 1] = "ForeverBook.lua"
        end
    end
    return files
end

-- boot("HUNTER"|"WARLOCK", setup?, flavor?) -> { ns, m, env }; setup(m)
-- runs BEFORE the login events so tests can shape the pre-login game
-- state. flavor "Vanilla" (default), "TBC" or "Forever" - picks the data
-- files and the mocked client (WOW_PROJECT_ID + GetBuildInfo; Forever also
-- swaps the whole API shape, see wow_mock ApplyForever), exactly like the
-- game picks the .toc. plainToc = true loads the file list of PetTips.toc instead.
local function boot(class, setup, flavor, plainToc)
    flavor = flavor or "Vanilla"
    local m = buildMocks()
    m.state.class = class
    m.WOW_PROJECT_CLASSIC = 2
    m.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    m.WOW_PROJECT_ID = (flavor == "TBC") and 5 or 2
    if flavor == "TBC" then -- TBC Anniversary 2.5.6 (the mock default is Era)
        m.GetBuildInfo = function() return "2.5.6", "69795", "Sep 1 2026", 20506, "Version 2.5.6", "Release" end
    end
    if flavor == "Forever" then m.ApplyForever() end
    local ns = {}
    local env = Loader.newEnv(m)
    if setup then setup(m) end
    Loader.loadAll(base, tocFiles(flavor, plainToc), ns, env)
    m.Fire("ADDON_LOADED", "PetTips")
    m.Fire("PLAYER_LOGIN")
    return { ns = ns, m = m, env = env }
end

-- --- tiny test framework ---
local tests, currentSuite = {}, nil
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn, suite = currentSuite } end
local function fail(msg) error(msg, 3) end
local function assertEqual(got, want, msg)
    if got ~= want then
        fail((msg or "assertEqual") .. string.format(" (expected %s, got %s)", tostring(want), tostring(got)))
    end
end
local function assertTrue(c, msg) if not c then fail(msg or "assertTrue failed") end end
local function assertFalse(c, msg) if c then fail(msg or "assertFalse failed") end end
local function assertContains(list, value, msg)
    for _, v in ipairs(list) do if v == value then return end end
    fail((msg or "assertContains") .. " (missing " .. tostring(value) .. ")")
end

-- section lists hold rank ENTRIES; match them by spell id
local function spells(sectionList)
    local out = {}
    for _, e in ipairs(sectionList) do out[#out + 1] = e.spell end
    return out
end

_G.PT_TEST = {
    boot = boot, test = test,
    assertEqual = assertEqual, assertTrue = assertTrue,
    assertFalse = assertFalse, assertContains = assertContains,
    spells = spells,
}

local SUITE_FILES = {
    "test_data.lua",
    "test_core.lua",
    "test_sections_hunter.lua",
    "test_sections_warlock.lua",
    "test_knowntraining.lua",
    "test_beasttooltips.lua",
    "test_forever.lua",
    "test_locales.lua",
}
for _, s in ipairs(SUITE_FILES) do
    currentSuite = s
    dofile(base .. "tests/" .. s)
end
currentSuite = nil

-- --- run ---
local passed, failed = 0, 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("  FAIL  [" .. t.suite .. "] " .. t.name .. "\n          " .. tostring(err))
    end
end
print(string.format("%d passed, %d failed, %d total", passed, failed, passed + failed))
os.exit(failed == 0 and 0 or 1)
