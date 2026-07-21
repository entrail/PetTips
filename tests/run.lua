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
-- at least parse; a syntax error there fails the boot = a test failure)
local FILES = {
    "Core.lua",
    "Locales/deDE.lua",
    "Locales/frFR.lua",
    "Locales/esES.lua",
    "Locales/ptBR.lua",
    "Data/Vanilla/FamilyData.lua",
    "Data/Vanilla/PetAbilitiesData.lua",
    "Data/Vanilla/TameMobsData.lua",
    "Data/Vanilla/DemonAbilitiesData.lua",
    "KnownTraining.lua",
    "TrainingList.lua",
    "BeastTooltips.lua",
    "Options.lua",
}

-- boot("HUNTER"|"WARLOCK", setup?) -> { ns, m, env }; setup(m) runs
-- BEFORE the login events so tests can shape the pre-login game state.
local function boot(class, setup)
    local m = buildMocks()
    m.state.class = class
    local ns = {}
    local env = Loader.newEnv(m)
    if setup then setup(m) end
    Loader.loadAll(base, FILES, ns, env)
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
