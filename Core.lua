local ADDON_NAME, ns = ...

ns.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")

-- Localization: all user-facing text goes through ns.L["English text"].
-- English is the key and the fallback; locale files can override entries.
ns.L = setmetatable({}, { __index = function(_, key) return key end })

-- Account-wide settings: behavior should be identical on every character.
-- What differs per character (known ranks) lives in PetTipsCharDB.
local defaults = {
    enableList = true,         -- spellbook pet tab + training list
    showKnownByPet = true,     -- gray "already known by pet" section
    beastTooltips = true,      -- taught-ability lines on beast tooltips
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

-- ns.OnInit(fn) -> runs at ADDON_LOADED, after ns.db/ns.chardb are ready.
-- ns.OnLogin(fn) -> runs at PLAYER_LOGIN, when player info is reliable.
local initCallbacks, loginCallbacks = {}, {}
function ns.OnInit(fn) table.insert(initCallbacks, fn) end
function ns.OnLogin(fn) table.insert(loginCallbacks, fn) end

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
        ns.chardb = PetTipsCharDB
        for _, fn in ipairs(initCallbacks) do fn() end
    elseif event == "PLAYER_LOGIN" then
        ns.playerClass = select(2, UnitClass("player"))
        for _, fn in ipairs(loginCallbacks) do fn() end
    end
end)

-- Locale-safe family of the current pet (nil without a pet).
function ns.GetPetFamilyId()
    local famName = UnitCreatureFamily("pet")
    return famName and ns.FAMILY_BY_NAME[famName] or nil
end
