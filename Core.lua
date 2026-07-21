local ADDON_NAME, ns = ...

ns.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")

-- Client flavor: the right Data/<flavor> files are picked by the per-
-- flavor .toc; this flag is for the few runtime differences beyond data.
ns.isTBC = WOW_PROJECT_ID == (WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5)

-- Localization: all user-facing text goes through ns.L["English text"].
-- English is the key and the fallback; locale files can override entries.
ns.L = setmetatable({}, { __index = function(_, key) return key end })

-- Account-wide settings: behavior should be identical on every character.
-- What differs per character (known ranks) lives in PetTipsCharDB.
local defaults = {
    enableList = true,         -- spellbook pet tab + training list
    showKnownByPet = true,     -- gray "already known by pet" section
    beastTooltips = true,      -- taught-ability lines on beast tooltips
    grimoireTooltips = true,   -- known/missing hints on grimoire item tooltips
    mobLines = 10,             -- teaching mobs listed per ability tooltip
    craftPanel = false,        -- missing-ranks panel next to Beast Training
    hiddenAbilities = {},      -- abilityKey -> true: hidden from all lists
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Factory for Data/<flavor>/PetAbilitiesData.lua. Builds ns.PET_ABILITIES
-- (ordered list of abilities with their rank entries) and
-- ns.ABILITY_BY_SPELL (spellId -> rank entry).
function ns.NewPetAbilityDB()
    local abilities, bySpell = {}, {}
    ns.PET_ABILITIES = abilities
    ns.ABILITY_BY_SPELL = bySpell
    local current
    local function ability(key, families)
        local famSet
        if families then
            famSet = {}
            for _, famId in ipairs(families) do famSet[famId] = true end
        end
        current = { key = key, families = famSet, ranks = {} }
        abilities[#abilities + 1] = current
    end
    local function rank(spellId, rankNo, petLevel, tp, src, money)
        local entry = {
            spell = spellId, rank = rankNo, level = petLevel,
            tp = tp, src = src, money = money or 0, ability = current,
        }
        current.ranks[rankNo] = entry
        bySpell[spellId] = entry
    end
    return ability, rank
end

-- Factory for Data/<flavor>/DemonAbilitiesData.lua. Builds
-- ns.DEMON_ABILITIES / ns.DEMON_ABILITY_BY_SPELL (same entry shape as the
-- hunter DB, so the list code can share most paths) and
-- ns.GRIMOIRE_BY_ITEM (grimoire itemId -> rank entry, for item tooltips).
-- Demon entries: level = required WARLOCK level, tp = 0 (demons have no
-- training points), src "g" = grimoire item at a demon trainer vendor,
-- "a" = automatic (rank 1 comes with the demon), money = grimoire price.
function ns.NewDemonAbilityDB()
    local abilities, bySpell, byItem = {}, {}, {}
    ns.DEMON_ABILITIES = abilities
    ns.DEMON_ABILITY_BY_SPELL = bySpell
    ns.GRIMOIRE_BY_ITEM = byItem
    local current
    local function ability(key, familyId)
        current = { key = key, families = { [familyId] = true }, ranks = {} }
        abilities[#abilities + 1] = current
    end
    local function rank(spellId, rankNo, level, src, money, itemId)
        local entry = {
            spell = spellId, rank = rankNo, level = level,
            tp = 0, src = src, money = money or 0, item = itemId, ability = current,
        }
        current.ranks[rankNo] = entry
        bySpell[spellId] = entry
        if itemId then byItem[itemId] = entry end
    end
    return ability, rank
end

-- Which demons this warlock can have at all: the summon spells are the
-- exact, locale-safe signal (same IDs on Era and TBC; 713 = Summon Incubus
-- on realms that have it, same family data as the Succubus). A demon
-- that cannot be summoned cannot have learned any grimoire either -
-- using one requires that demon to be out - so "can't summon" always
-- means "nothing to sync".
local DEMON_SUMMON_SPELLS = {
    [23] = { 688 },      -- Imp
    [16] = { 697 },      -- Voidwalker
    [17] = { 712, 713 }, -- Succubus / Incubus
    [15] = { 691 },      -- Felhunter
    [29] = { 30146 },    -- Felguard (TBC only: 41-point Demonology talent)
}

function ns.CanSummonDemonFamily(famId)
    local spells = DEMON_SUMMON_SPELLS[famId]
    if not spells then return false end
    for _, spellId in ipairs(spells) do
        if IsPlayerSpell(spellId) then return true end
    end
    return false
end

-- Factory for Data/<flavor>/TameMobsData.lua. Builds ns.TAME_MOBS
-- (npcId -> mob) and ns.MOBS_BY_SPELL (spellId -> list of mobs that
-- teach that rank), the link between an ability rank and where to tame it.
function ns.NewTameMobDB()
    local mobs, bySpell = {}, {}
    ns.TAME_MOBS = mobs
    ns.MOBS_BY_SPELL = bySpell
    return function(npcId, name, familyId, minLevel, maxLevel, zone, zoneIds, teaches)
        local m = {
            npc = npcId, name = name, family = familyId,
            minLevel = minLevel, maxLevel = maxLevel, zone = zone,
            zoneIds = zoneIds, teaches = teaches,
        }
        mobs[npcId] = m
        for _, spellId in ipairs(teaches) do
            local list = bySpell[spellId]
            if not list then list = {}; bySpell[spellId] = list end
            list[#list + 1] = m
        end
    end
end

-- Zone IDs in the mob data are locale-safe: positive = uiMapID of an
-- outdoor zone, negative = -instanceMapID of a dungeon/raid.

-- Localized name for one zone ID (nil if the client can't resolve it).
function ns.GetZoneName(zoneId)
    if zoneId < 0 then
        local name = GetRealZoneText(-zoneId)
        if name and name ~= "" then return name end
    else
        local info = C_Map.GetMapInfo(zoneId)
        if info and info.name then return info.name end
    end
    return nil
end

-- Localized "Zone A; Zone B" display string for a mob; falls back to the
-- English string from the data if any ID fails to resolve.
function ns.GetMobZoneText(m)
    local ids = m.zoneIds
    if ids and #ids > 0 then
        local names = {}
        for i, id in ipairs(ids) do
            names[i] = ns.GetZoneName(id)
            if not names[i] then return m.zone end
        end
        return table.concat(names, "; ")
    end
    return m.zone
end

-- Set of zone IDs the player is in right now: -instanceMapID inside a
-- dungeon/raid, otherwise the player's uiMapID plus parents up to (not
-- including) the continent - matches mob zoneIds on every client locale.
function ns.GetPlayerZoneKeys()
    local keys = {}
    if IsInInstance() then
        local instanceId = select(8, GetInstanceInfo())
        if instanceId then keys[-instanceId] = true end
    else
        local mapId = C_Map.GetBestMapForUnit("player")
        for _ = 1, 10 do -- guard against parent cycles
            if not mapId or mapId <= 0 then break end
            local info = C_Map.GetMapInfo(mapId)
            if not info or (info.mapType and info.mapType <= 2) then break end
            keys[mapId] = true
            mapId = info.parentMapID
        end
    end
    return keys
end

-- Localized mob names: the data ships English names (Petopia has no
-- translations), but the server knows the localized name of every
-- creature - a creature query through a unit tooltip hyperlink returns
-- it. The query is async: the first lookup may come back empty (English
-- fallback is shown), the reply is cached account-wide per locale in
-- PetTipsDB.mobNames, so names fill in as tooltips are shown. English
-- clients skip all of this - the data already matches the server.
local wantMobNames = GetLocale() ~= "enUS" and GetLocale() ~= "enGB"
local scanTip
local function QueryMobName(npcId)
    local link = string.format("unit:Creature-0-0-0-0-%d-0000000000", npcId)
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local data = C_TooltipInfo.GetHyperlink(link)
        local line = data and data.lines and data.lines[1]
        return line and line.leftText
    end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "PetTipsScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:SetHyperlink(link)
    local left = _G["PetTipsScanTooltipTextLeft1"]
    return left and left:GetText()
end

function ns.GetMobName(m)
    if not wantMobNames or not ns.db then return m.name end
    local cache = ns.db.mobNames
    if not cache or cache.locale ~= GetLocale() then
        cache = { locale = GetLocale() }
        ns.db.mobNames = cache
    end
    local name = cache[m.npc]
    if not name then
        name = QueryMobName(m.npc)
        if name and name ~= "" and name ~= UNKNOWN then
            cache[m.npc] = name
        else
            return m.name
        end
    end
    return name
end

-- ns.OnInit(fn) -> runs at ADDON_LOADED, after ns.db/ns.chardb are ready.
-- ns.OnLogin(fn) -> runs at PLAYER_LOGIN, when player info is reliable.
local initCallbacks, loginCallbacks = {}, {}
function ns.OnInit(fn) table.insert(initCallbacks, fn) end
function ns.OnLogin(fn) table.insert(loginCallbacks, fn) end

-- One failing module must not keep the ones after it from loading (a
-- KnownTraining error would otherwise silently eat the whole training
-- list UI). Errors still reach the default error handler, so BugSack /
-- scriptErrors show them. In the headless tests CallErrorHandler does
-- not exist - rethrow so a callback error still fails the test loudly.
local function RunCallbacks(list)
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn)
        if not ok then
            if CallErrorHandler then CallErrorHandler(err) else error(err, 0) end
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        PetTipsDB = PetTipsDB or {}
        CopyDefaults(defaults, PetTipsDB)
        ns.db = PetTipsDB
        PetTipsCharDB = PetTipsCharDB or {}
        if type(PetTipsCharDB.knownTeach) ~= "table" then PetTipsCharDB.knownTeach = {} end
        if type(PetTipsCharDB.syncedDemonFams) ~= "table" then PetTipsCharDB.syncedDemonFams = {} end
        ns.chardb = PetTipsCharDB
        RunCallbacks(initCallbacks)
    elseif event == "PLAYER_LOGIN" then
        ns.playerClass = select(2, UnitClass("player"))
        -- Warlocks reuse the hunter list code: point the generic tables at
        -- the demon data before any login callback builds UI on top of them.
        if ns.playerClass == "WARLOCK" then
            ns.isWarlock = true
            ns.PET_ABILITIES = ns.DEMON_ABILITIES
            ns.ABILITY_BY_SPELL = ns.DEMON_ABILITY_BY_SPELL
            ns.PET_FAMILIES = ns.DEMON_FAMILIES
            ns.FAMILY_BY_NAME = ns.DEMON_FAMILY_BY_NAME
        end
        RunCallbacks(loginCallbacks)
    end
end)

-- Locale-safe family of the current pet (nil without a pet).
function ns.GetPetFamilyId()
    local famName = UnitCreatureFamily("pet")
    return famName and ns.FAMILY_BY_NAME[famName] or nil
end
