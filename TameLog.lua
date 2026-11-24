local ADDON_NAME, ns = ...
local L = ns.L
local api = ns.api

-- Tame collector (WoW Forever only). Which beast teaches which rank is
-- server-side data, and for Forever no complete source exists: the shipped
-- list is the Classic Era list marked "unverified" plus a few confirmed
-- beasts (see Data/Forever/TameMobsData.lua). So every successful Tame
-- Beast is recorded - npc ID, family, level, zone and every spell the fresh
-- pet knows - into PetTipsDB.tameLog (account-wide; the SavedVariables file
-- is what tools/ForeverPetData/confirmed_sources.csv gets updated from).
-- The record is compared with the shipped entry (confirmed / new source /
-- differs) and applied on top of it right away, so the hunter's own
-- observations correct their tooltips and lists without waiting for a
-- release.
--
-- Flow: Tame Beast cast start -> remember the target (its GUID is only
-- readable while it is still a wild creature) -> UNIT_PET with a pet out
-- while that memory is fresh = the tame succeeded -> read the pet
-- spellbook a moment later (it fills asynchronously).

local TAME_BEAST = 1515
local PENDING_TTL = 45   -- seconds: 20s channel plus slack
local SCAN_DELAYS = { 1.5, 5 } -- pet spellbook fills late; second pass merges

local pending -- { npc, name, family, level, zone, at }

-- uiMapID of the zone the player is in (negative instanceMapID inside a
-- dungeon) - the same scheme as the zoneIds in the mob data
local function CurrentZoneId()
    if IsInInstance() then
        local instanceId = select(8, GetInstanceInfo())
        return instanceId and -instanceId or nil
    end
    local mapId = C_Map.GetBestMapForUnit("player")
    for _ = 1, 10 do -- guard against parent cycles
        if not mapId or mapId <= 0 then return nil end
        local info = C_Map.GetMapInfo(mapId)
        if not info then return nil end
        if not info.mapType or info.mapType <= 3 then return mapId end -- 3 = zone
        mapId = info.parentMapID
    end
    return nil
end

-- npc ID of the wild beast. Only a creature GUID qualifies: on Forever
-- (Retail engine) every tamed pet is creature 165189 "Generic Hunter Pet",
-- so a pet GUID never tells which beast was tamed.
local function NpcIdFromGuid(guid)
    if not guid or api.IsSecret(guid) then return nil end
    local unitType, _, _, _, _, npcId = strsplit("-", guid)
    if unitType ~= "Creature" then return nil end
    return tonumber(npcId)
end

local function FamilyIdOf(unit)
    local famName = UnitCreatureFamily(unit)
    if not famName or api.IsSecret(famName) then return nil end
    return ns.FAMILY_BY_NAME[famName]
end

local function RememberTarget()
    local name = UnitName("target")
    local level = UnitLevel("target")
    pending = {
        npc = NpcIdFromGuid(UnitGUID("target")),
        name = (name and not api.IsSecret(name)) and name or nil,
        family = FamilyIdOf("target"),
        level = (level and not api.IsSecret(level) and level > 0) and level or nil,
        zone = CurrentZoneId(),
        at = GetTime(),
    }
end

-- "Bite 2, Trickster's Dance" for chat lines
local function RankList(spellIds)
    if #spellIds == 0 then return L["nothing"] end
    local parts = {}
    for _, spellId in ipairs(spellIds) do
        local entry = ns.ABILITY_BY_SPELL[spellId]
        local name = api.GetSpellName(spellId) or ("spell " .. spellId)
        if entry and #entry.ability.ranks > 1 then
            name = string.format("%s %d", name, entry.rank)
        end
        parts[#parts + 1] = name
    end
    return table.concat(parts, ", ")
end

local function SameSet(a, b)
    if #a ~= #b then return false end
    local set = {}
    for _, v in ipairs(a) do set[v] = true end
    for _, v in ipairs(b) do
        if not set[v] then return false end
    end
    return true
end

local function Union(into, from)
    local set = {}
    for _, v in ipairs(into) do set[v] = true end
    for _, v in ipairs(from) do
        if not set[v] then
            set[v] = true
            into[#into + 1] = v
        end
    end
    table.sort(into)
    return into
end

-- ------------------------------------------------- applying the log
-- The shipped data as loaded from the data file, before any log entry
-- touched it - what a new record is compared against.
local shipped = {} -- npcId -> { teaches = copy, unverified = true / rank set / nil } / false

local function RebuildMobsBySpell()
    local bySpell = ns.MOBS_BY_SPELL
    wipe(bySpell)
    for _, m in pairs(ns.TAME_MOBS) do
        for _, spellId in ipairs(m.teaches) do
            local list = bySpell[spellId]
            if not list then list = {}; bySpell[spellId] = list end
            list[#list + 1] = m
        end
    end
end

local function ApplyRecord(npcId, rec)
    if shipped[npcId] == nil then
        local m = ns.TAME_MOBS[npcId]
        shipped[npcId] = m and { teaches = { unpack(m.teaches) }, unverified = m.unverified } or false
    end
    if not rec.family or not ns.PET_FAMILIES[rec.family] then return end
    -- only ranks our data knows (a data update may have dropped one)
    local teaches = {}
    for _, spellId in ipairs(rec.teaches or {}) do
        if ns.ABILITY_BY_SPELL[spellId] then teaches[#teaches + 1] = spellId end
    end
    if #teaches == 0 then
        ns.TAME_MOBS[npcId] = nil -- seen to teach nothing
        return
    end
    local m = ns.TAME_MOBS[npcId]
    if not m then
        m = { npc = npcId, name = rec.name or ("npc " .. npcId), zone = "?",
              zoneIds = rec.zone and { rec.zone } or {} }
        ns.TAME_MOBS[npcId] = m
    end
    m.family = rec.family
    m.minLevel = math.min(m.minLevel or rec.minLevel or 1, rec.minLevel or m.minLevel or 1)
    m.maxLevel = math.max(m.maxLevel or rec.maxLevel or 1, rec.maxLevel or m.maxLevel or 1)
    m.teaches = teaches
    m.unverified = nil
end

function ns.ApplyTameLog()
    if not (ns.isForever and ns.TAME_MOBS and ns.db and ns.db.tameLog) then return end
    for npcId, rec in pairs(ns.db.tameLog) do
        if type(npcId) == "number" and type(rec) == "table" then
            ApplyRecord(npcId, rec)
        end
    end
    RebuildMobsBySpell()
end

-- ------------------------------------------------- recording

-- Ranks a hunter learns BY TAMING are what the mob data lists; trainer-only
-- ranks a beast happens to know (Growl) are logged but never compared.
local function IsTamingRank(spellId)
    local entry = ns.ABILITY_BY_SPELL[spellId]
    return entry and (entry.src == "w" or entry.src == "tw" or entry.src == "n") or false
end

local function ScanPet(tame, final)
    if not UnitExists("pet") then return end
    local spellIds = api.GetPetSpellIds()
    if #spellIds == 0 then
        -- no spellbook API (or not filled yet): probe the ranks we know
        for spellId in pairs(ns.ABILITY_BY_SPELL) do
            if api.IsPetSpellKnown(spellId) then spellIds[#spellIds + 1] = spellId end
        end
    end
    local npcId = tame.npc -- the target's, see NpcIdFromGuid
    if not npcId then
        if final then print(L["PetTips: could not identify the tamed beast - not recorded."]) end
        return
    end

    local teaches, other = {}, {}
    for _, spellId in ipairs(spellIds) do
        if IsTamingRank(spellId) then
            teaches[#teaches + 1] = spellId
        else
            other[#other + 1] = spellId
        end
    end

    local log = ns.db.tameLog
    local rec = log[npcId]
    if not rec then
        rec = { teaches = {}, other = {}, count = 0 }
        log[npcId] = rec
    end
    rec.name = tame.name or rec.name or UnitName("pet")
    rec.family = tame.family or FamilyIdOf("pet") or rec.family
    local level = tame.level or UnitLevel("pet")
    if level and level > 0 then
        rec.minLevel = math.min(rec.minLevel or level, level)
        rec.maxLevel = math.max(rec.maxLevel or level, level)
    end
    rec.zone = tame.zone or rec.zone
    Union(rec.teaches, teaches)
    Union(rec.other, other)
    rec.build = select(2, GetBuildInfo())
    rec.last = time()
    if not tame.counted then
        tame.counted = true
        rec.count = (rec.count or 0) + 1
    end
    if not final then return end

    -- verdict against the SHIPPED entry, then apply
    if shipped[npcId] == nil then
        local m = ns.TAME_MOBS[npcId]
        shipped[npcId] = m and { teaches = { unpack(m.teaches) }, unverified = m.unverified } or false
    end
    local was = shipped[npcId]
    local label = rec.name or ("npc " .. npcId)
    if was and SameSet(was.teaches, rec.teaches) then
        print(string.format(L["PetTips: recorded %s - matches the data (%s)."], label, RankList(rec.teaches)))
    elseif was then
        print(string.format(L["PetTips: recorded %s - differs from the data: knows %s, expected %s."],
            label, RankList(rec.teaches), RankList(was.teaches)))
    elseif #rec.teaches > 0 then
        print(string.format(L["PetTips: recorded %s - NEW taming source (%s)."], label, RankList(rec.teaches)))
    else
        print(string.format(L["PetTips: recorded %s - teaches nothing the list tracks."], label))
    end
    ApplyRecord(npcId, rec)
    RebuildMobsBySpell()
    if ns.RefreshTrainingList then ns.RefreshTrainingList() end
end

-- /pettips tamelog: what has been recorded so far
function ns.TameLogDebug()
    local log = ns.db and ns.db.tameLog or {}
    local ids = {}
    for npcId in pairs(log) do ids[#ids + 1] = npcId end
    table.sort(ids)
    print(string.format("PetTips tame log: %d beasts recorded%s", #ids,
        ns.isForever and "" or " (the collector only runs on WoW Forever)"))
    for _, npcId in ipairs(ids) do
        local rec = log[npcId]
        print(string.format("  %d %s | family %s | level %s-%s | zone %s | x%d | teaches: %s | other spells: %s",
            npcId, tostring(rec.name), tostring(rec.family and ns.PET_FAMILIES[rec.family] or rec.family),
            tostring(rec.minLevel), tostring(rec.maxLevel), tostring(rec.zone), rec.count or 0,
            RankList(rec.teaches or {}), table.concat(rec.other or {}, " ")))
    end
end

ns.OnInit(function()
    if type(ns.db.tameLog) ~= "table" then ns.db.tameLog = {} end
end)

ns.OnLogin(function()
    if ns.playerClass ~= "HUNTER" or not ns.isForever then return end
    ns.ApplyTameLog()

    local watcher = CreateFrame("Frame")
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    watcher:RegisterUnitEvent("UNIT_PET", "player")
    watcher:SetScript("OnEvent", function(_, event, _, _, spellId)
        if event == "UNIT_PET" then
            local tame = pending
            if not tame or GetTime() - tame.at > PENDING_TTL or not UnitExists("pet") then return end
            pending = nil
            for i, delay in ipairs(SCAN_DELAYS) do
                C_Timer.After(delay, function() ScanPet(tame, i == #SCAN_DELAYS) end)
            end
        elseif not api.IsSecret(spellId) and spellId == TAME_BEAST then
            RememberTarget()
        end
    end)
end)
