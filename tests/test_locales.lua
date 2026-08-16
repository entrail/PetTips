-- Locale files: each one must only load on its own locale, must actually
-- translate every entry it stores, and must keep the same format
-- directives (%s/%d, in the same order) as its English key - a mismatched
-- %d crashes string.format at runtime.
local T = _G.PT_TEST
local test, assertEqual, assertTrue = T.test, T.assertEqual, T.assertTrue

-- esMX has no file of its own: esES.lua serves both locales.
local LOCALES = { "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU" }

-- the .toc has 77 entries per locale; keep a margin so adding a string
-- without translating it everywhere is caught by the per-entry checks
-- rather than by this floor.
local MIN_ENTRIES = 70

local function bootLocale(locale)
    -- setup() runs before the files are loaded, so the locale guard at the
    -- top of each Locales/*.lua sees the mocked value.
    return T.boot("HUNTER", function(m)
        m.GetLocale = function() return locale end
    end)
end

local function directives(s)
    local list = {}
    for d in tostring(s):gmatch("%%[sd]") do list[#list + 1] = d end
    return table.concat(list, " ")
end

for _, locale in ipairs(LOCALES) do
    test("locales: " .. locale .. " translations load and format-match", function()
        local B = bootLocale(locale)
        local entries = 0
        for key, value in pairs(B.ns.L) do
            entries = entries + 1
            assertEqual(type(value), "string", locale .. " non-string entry: " .. tostring(key))
            assertTrue(value ~= key, locale .. " untranslated entry: " .. key)
            assertEqual(directives(value), directives(key),
                locale .. " format mismatch in: " .. key)
        end
        assertTrue(entries >= MIN_ENTRIES,
            locale .. " translation count (" .. entries .. " < " .. MIN_ENTRIES .. ")")
        -- the metatable fallback still serves unknown keys as English
        assertEqual(B.ns.L["Untranslated probe"], "Untranslated probe", "fallback")
    end)
end

test("locales: enUS loads no overrides, English keys pass through", function()
    local B = bootLocale("enUS")
    local entries = 0
    for _ in pairs(B.ns.L) do entries = entries + 1 end
    assertEqual(entries, 0, "no stored entries on enUS")
    assertEqual(B.ns.L["Pet trainer cost: %s"], "Pet trainer cost: %s", "key is fallback")
end)
