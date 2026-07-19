local ADDON_NAME, ns = ...
local L = ns.L

-- Tooltip lines on tameable beasts that teach pet ability ranks, in the
-- style of the Tamed addon (moody/Tamed, MIT; re-implemented against our
-- own data): an addon-name header in hunter green, then one indented line
-- per taught rank - green when the hunter already knows how to teach it,
-- red-orange when it is still to be learned (worth taming!).

local function RankLabel(entry)
    local name = GetSpellInfo(entry.spell) or ("spell " .. entry.spell)
    if #entry.ability.ranks > 1 then
        return string.format("%s %d", name, entry.rank)
    end
    return name
end

ns.OnLogin(function()
    if ns.playerClass ~= "HUNTER" then return end

    GameTooltip:HookScript("OnTooltipSetUnit", function(self)
        if not ns.db.beastTooltips then return end
        local _, unit = self:GetUnit()
        if not unit then return end
        local guid = UnitGUID(unit) or ""
        local unitType, _, _, _, _, npcId = strsplit("-", guid)
        if not (npcId and unitType == "Creature") then return end
        local mob = ns.TAME_MOBS[tonumber(npcId)]
        if not mob then return end

        for _, spellId in ipairs(mob.teaches) do
            local entry = ns.ABILITY_BY_SPELL[spellId]
            if entry then
                if ns.chardb.knownTeach[spellId] then
                    self:AddLine(RankLabel(entry) .. " " .. L["(known)"], 0.4, 0.9, 0.4)
                else
                    self:AddLine(RankLabel(entry) .. " " .. L["(new)"], 1, 0.45, 0.35)
                end
            end
        end
    end)
end)
