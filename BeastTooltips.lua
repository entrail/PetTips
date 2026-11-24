local ADDON_NAME, ns = ...
local L = ns.L
local api = ns.api

-- Tooltip lines on tameable beasts that teach pet ability ranks, in the
-- style of the Tamed addon (moody/Tamed, MIT; re-implemented against our
-- own data): an addon-name header in hunter green, then one indented line
-- per taught rank - green when the hunter already knows how to teach it,
-- red-orange when it is still to be learned (worth taming!).

local function RankLabel(entry)
    local name = api.GetSpellName(entry.spell) or ("spell " .. entry.spell)
    if #entry.ability.ranks > 1 then
        return string.format("%s %d", name, entry.rank)
    end
    return name
end

-- Family type + tier line (US-51). Colors follow the item-quality-style
-- scheme established by ClassicHunterPetInfo: Offense red, Defense blue,
-- General green; tier S legendary-orange, A epic, B rare, C uncommon.
local SPEC_LABEL = {
    offense = { key = "Offense", color = "a40000" },
    defense = { key = "Defense", color = "1070ff" },
    general = { key = "General", color = "159908" },
}
local TIER_COLOR = { S = "ff8000", A = "a335ee", B = "0070dd", C = "1eff00" }

local function FamilyInfoLine(fam)
    local spec = SPEC_LABEL[fam.spec]
    if not spec then return nil end
    local text = ("|cff%s%s|r"):format(spec.color, L[spec.key])
    local tierColor = fam.tier and TIER_COLOR[fam.tier]
    if tierColor then
        text = text .. " - " .. string.format(L["Tier %s"],
            ("|cff%s%s|r"):format(tierColor, fam.tier))
    end
    return text
end

ns.OnLogin(function()
    if ns.playerClass ~= "HUNTER" then return end

    local function HandleUnitTooltip(self, data)
        if not ns.db.beastTooltips then return end
        -- modern path hands us the guid in the tooltip data; legacy path
        -- (and any modern client without it) resolves via GetUnit
        local _, unit = self:GetUnit()
        -- Forever hands out "secret" unit tokens/GUIDs in combat - nothing
        -- can be read from those, so the tooltip stays untouched
        if api.IsSecret(unit) then return end
        local guid = (data and data.guid) or (unit and UnitGUID(unit))
        if not guid or api.IsSecret(guid) then return end
        local unitType, _, _, _, _, npcId = strsplit("-", guid)

        if unitType == "Pet" then
            -- own or other hunters' pets: family type/tier line only -
            -- there is nothing to tame or learn from an active pet.
            -- Family via the localized name (locale-safe map), with the
            -- tamed creature's npc ID as fallback.
            if not ns.db.tooltipFamilyInfo then return end
            local famName = unit and UnitCreatureFamily(unit)
            local famId = famName and ns.FAMILY_BY_NAME[famName]
            if not famId and npcId then
                local mob = ns.TAME_MOBS[tonumber(npcId)]
                famId = mob and mob.family
            end
            local fam = famId and ns.FAMILY_INFO and ns.FAMILY_INFO[famId]
            local line = fam and FamilyInfoLine(fam)
            if line then
                self:AddLine(line, 0.8, 0.8, 0.8)
            end
            return
        end

        if not (npcId and unitType == "Creature") then return end
        local mob = ns.TAME_MOBS[tonumber(npcId)]

        -- family type/tier line on EVERY beast of a known pet family, not
        -- just teaching mobs (most beasts - e.g. all Vanilla raptors -
        -- teach nothing but still deserve the family info). The mob entry
        -- is authoritative when present; otherwise the family resolves
        -- from the localized UnitCreatureFamily string.
        if ns.db.tooltipFamilyInfo then
            local famId = mob and mob.family
            if not famId then
                local famName = unit and UnitCreatureFamily(unit)
                famId = famName and ns.FAMILY_BY_NAME[famName]
            end
            local fam = famId and ns.FAMILY_INFO and ns.FAMILY_INFO[famId]
            local line = fam and FamilyInfoLine(fam)
            if line then
                self:AddLine(line, 0.8, 0.8, 0.8)
            end
        end

        if not mob then return end

        -- Forever: a rank nobody has confirmed on this client yet (the beast
        -- is carried over from the Era list, or the rank was kept from it on
        -- a confirmed beast) gets a gray "?" (see TameLog.lua)
        for _, spellId in ipairs(mob.teaches) do
            local entry = ns.ABILITY_BY_SPELL[spellId]
            if entry then
                local mark = ns.IsRankUnverified(mob, spellId) and " |cff909090?|r" or ""
                if ns.chardb.knownTeach[spellId] then
                    self:AddLine(RankLabel(entry) .. " " .. L["(known)"] .. mark, 0.4, 0.9, 0.4)
                else
                    self:AddLine(RankLabel(entry) .. " " .. L["(new)"] .. mark, 1, 0.45, 0.35)
                end
            end
        end
    end

    -- Both tooltip API paths with a once-per-tooltip guard (same pattern
    -- as KnownTraining's grimoire tooltips / ProfessionTips): the modern
    -- TooltipDataProcessor where the client has it, plus the legacy
    -- OnTooltipSetUnit script - whichever fires first renders, the
    -- other no-ops, so a client firing both never double-renders.
    GameTooltip:HookScript("OnTooltipCleared", function(tooltip)
        tooltip.petTipsBeastDone = nil
    end)
    local function GuardedHandle(tooltip, data)
        if tooltip ~= GameTooltip then return end
        if tooltip.petTipsBeastDone then return end
        tooltip.petTipsBeastDone = true
        HandleUnitTooltip(tooltip, data)
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, GuardedHandle)
    end
    pcall(function()
        GameTooltip:HookScript("OnTooltipSetUnit", GuardedHandle)
    end)
end)
