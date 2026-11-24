local ADDON_NAME, ns = ...

-- Compat.lua: the one place that knows which client API we are on.
--
-- PetTips runs on Classic Era 1.15, TBC Anniversary 2.5 and WoW Forever
-- 1.60 (ns.isForever, Core.lua). Forever is the Retail engine: the classic
-- globals this addon grew up with are GONE there (GetSpellInfo,
-- GetPetTrainingPoints, GetCoinTextureString, GetItemInfo; IsSpellKnown /
-- IsPlayerSpell only survive as deprecation shims behind a CVar) and live
-- on as C_Spell / C_SpellBook / C_PetInfo / C_CurrencyInfo / C_Item. The
-- trainer globals still exist, but GetTrainerServiceInfo returns its
-- values in the Retail order.
--
-- Feature files never call these APIs directly; everything goes through
-- ns.api. Detection is by FEATURE (does the legacy global exist?), not by
-- flavor, so a Classic client that loses a global later degrades to the
-- C_ path by itself. (Verified against Gethe/wow-ui-source branch
-- "forever", build 1.60.1.69913.)

local api = {}
ns.api = api

------------------------------------------------------------------------
-- Spells
------------------------------------------------------------------------

local legacyGetSpellInfo = GetSpellInfo -- name, rank, icon, ...

if legacyGetSpellInfo then
    -- localized name (nil while the spell data is not cached yet)
    function api.GetSpellName(spellId)
        return (legacyGetSpellInfo(spellId))
    end
    function api.GetSpellIcon(spellId)
        return (select(3, legacyGetSpellInfo(spellId)))
    end
else
    function api.GetSpellName(spellId)
        return C_Spell.GetSpellName(spellId)
    end
    function api.GetSpellIcon(spellId)
        return C_Spell.GetSpellTexture(spellId)
    end
end

-- "Rank 2" / nil - the rank text of a spell (nil until the spell data is cached)
if GetSpellSubtext then
    function api.GetSpellSubtext(spellId)
        return GetSpellSubtext(spellId)
    end
else
    function api.GetSpellSubtext(spellId)
        return C_Spell.GetSpellSubtext(spellId)
    end
end

local PET_BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet

-- Does the summoned/active PET know this spell?
if C_SpellBook and C_SpellBook.IsSpellKnown and PET_BANK then
    function api.IsPetSpellKnown(spellId)
        return C_SpellBook.IsSpellKnown(spellId, PET_BANK) or false
    end
else
    function api.IsPetSpellKnown(spellId)
        return IsSpellKnown(spellId, true) or false
    end
end

-- Does the PLAYER know this spell (Beast Training, demon summons)?
if IsPlayerSpell then
    function api.IsPlayerSpell(spellId)
        return IsPlayerSpell(spellId) or false
    end
else
    function api.IsPlayerSpell(spellId)
        return C_SpellBook.IsSpellKnown(spellId) or false
    end
end

-- Every spell ID in the active pet's spellbook (TameLog: what a freshly
-- tamed beast knows, including spells our data has never heard of). Only
-- implemented on the C_SpellBook path - the collector is Forever-only.
function api.GetPetSpellIds()
    local ids = {}
    if not (C_SpellBook and C_SpellBook.HasPetSpells and C_SpellBook.GetSpellBookItemInfo and PET_BANK) then
        return ids
    end
    local numSpells = C_SpellBook.HasPetSpells() or 0
    for i = 1, numSpells do
        local info = C_SpellBook.GetSpellBookItemInfo(i, PET_BANK)
        -- pet ACTIONS (attack/follow/stay...) carry no spellID
        local spellId = info and info.spellID
        if spellId then ids[#ids + 1] = spellId end
    end
    return ids
end

------------------------------------------------------------------------
-- Pet training points, money, items
------------------------------------------------------------------------

if GetPetTrainingPoints then
    function api.GetPetTrainingPoints()
        return GetPetTrainingPoints()
    end
else
    function api.GetPetTrainingPoints()
        return C_PetInfo.GetPetTrainingPoints()
    end
end

if GetCoinTextureString then
    api.GetCoinTextureString = GetCoinTextureString
else
    function api.GetCoinTextureString(copper)
        return C_CurrencyInfo.GetCoinTextureString(copper)
    end
end

if GetItemInfo then
    function api.GetItemName(itemId)
        return (GetItemInfo(itemId))
    end
else
    function api.GetItemName(itemId)
        return C_Item.GetItemNameByID(itemId)
    end
end

------------------------------------------------------------------------
-- Trainer window
------------------------------------------------------------------------

-- Classic:  name, rankText, category            = GetTrainerServiceInfo(i)
-- Forever:  name, category, texture, reqLevel, rankText
-- -> always name, rankText, category ("available" / "unavailable" / "used")
-- Told apart by VALUE: the second return is a category token only in the
-- Forever order (a rank text is localized and never equals one).
local SERVICE_CATEGORY = { available = true, unavailable = true, used = true, header = true }

function api.GetTrainerService(index)
    local name, second, third, _, fifth = GetTrainerServiceInfo(index)
    if SERVICE_CATEGORY[second] then
        return name, fifth, second
    end
    return name, second, third
end

-- The spell behind a trainer service. Retail engine: the service tooltip
-- data carries it (C_TooltipInfo.GetTrainerService -> data.id; for pet
-- training that is the HUNTER-side teach spell). Classic has no API for
-- it (GetTrainerServiceSpellLink does not exist on Era) -> nil. Needed on
-- Forever because the pet-training services come WITHOUT a rank text
-- (seen 2026-09-22: "Growl" listed twice, subtext nil).
function api.GetTrainerServiceSpell(index)
    if not (C_TooltipInfo and C_TooltipInfo.GetTrainerService) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
    if not ok or type(data) ~= "table" then return nil end
    local id = data.id
    if type(id) == "number" and not api.IsSecret(id) then return id end
    return nil
end

-- Forever has no craft window: Beast Training opens the TRAINER frame in
-- pet mode (C_Trainer.GetTrainerType() == Enum.TrainerType.Pet, costs are
-- training points). Always false on Classic, where it is a craft window.
function api.IsBeastTrainingTrainer()
    local petType = Enum and Enum.TrainerType and Enum.TrainerType.Pet
    if not (petType and C_Trainer and C_Trainer.GetTrainerType) then return false end
    return C_Trainer.GetTrainerType() == petType
end

------------------------------------------------------------------------
-- Events / secret values
------------------------------------------------------------------------

-- Registering an event the client does not know THROWS on the newer
-- engines (CRAFT_SHOW on Forever, LEARNED_SPELL_IN_TAB on 2.5.6 / 1.15.9).
function api.SafeRegisterEvent(frame, event)
    return (pcall(frame.RegisterEvent, frame, event))
end

-- Forever hands addons "secret" values in combat (unit GUIDs among them);
-- any comparison or string operation on one throws. Check before use.
function api.IsSecret(value)
    return (issecretvalue and issecretvalue(value)) or false
end
