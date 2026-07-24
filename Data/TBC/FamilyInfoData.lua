local ADDON_NAME, ns = ...

-- Per-family combat classification for beast tooltips (US-51).
-- HAND-MAINTAINED - this file is NOT generator output. Source
-- (fetched 2026-07-22): Petopia BC family pages
-- (wow-petopia.com/classic_bc/family.php?id=<family>). The 17 Vanilla
-- families carry the same spec + modifiers as on Era; TBC adds
-- Dragonhawk/Ravager/Warp Stalker/Sporebat/Nether Ray/Serpent.
-- TIER IS NIL THROUGHOUT: no verified TBC tier list source yet (the
-- Vanilla tiers come from Wowhead's Classic tier list, which does not
-- cover TBC) - the tooltip simply omits the tier part.
-- Keys are the CreatureFamily IDs from FamilyData.lua.
--
-- info(familyId, spec, tier, health, armor, damage)

ns.FAMILY_INFO = {}
local function info(familyId, spec, tier, health, armor, damage)
    ns.FAMILY_INFO[familyId] = {
        spec = spec, tier = tier,
        health = health, armor = armor, damage = damage,
    }
end

info(1,  "general", nil, 1.00, 1.05, 1.00) -- Wolf
info(2,  "offense", nil, 0.98, 1.00, 1.10) -- Cat
info(3,  "offense", nil, 1.00, 1.00, 1.07) -- Spider
info(4,  "defense", nil, 1.08, 1.05, 0.91) -- Bear
info(5,  "defense", nil, 1.04, 1.09, 0.90) -- Boar
info(6,  "defense", nil, 0.95, 1.10, 1.00) -- Crocolisk
info(7,  "general", nil, 1.00, 1.05, 1.00) -- Carrion Bird
info(8,  "defense", nil, 0.96, 1.13, 0.95) -- Crab
info(9,  "defense", nil, 1.04, 1.00, 1.02) -- Gorilla
info(11, "offense", nil, 0.95, 1.03, 1.10) -- Raptor
info(12, "defense", nil, 1.05, 1.00, 1.00) -- Tallstrider
info(20, "defense", nil, 1.00, 1.10, 0.94) -- Scorpid
info(21, "defense", nil, 1.00, 1.13, 0.90) -- Turtle
info(24, "offense", nil, 1.00, 1.00, 1.07) -- Bat
info(25, "general", nil, 1.00, 1.05, 1.00) -- Hyena
info(26, "offense", nil, 1.00, 1.00, 1.07) -- Owl
info(27, "offense", nil, 1.00, 1.00, 1.07) -- Wind Serpent
info(30, "general", nil, 1.00, 1.00, 1.00) -- Dragonhawk
info(31, "offense", nil, 0.93, 1.05, 1.10) -- Ravager
info(32, "defense", nil, 1.00, 1.05, 0.94) -- Warp Stalker
info(33, "general", nil, 1.00, 1.00, 1.00) -- Sporebat
info(34, "defense", nil, 1.10, 0.90, 1.03) -- Nether Ray
info(35, "general", nil, 1.00, 1.00, 1.00) -- Serpent
