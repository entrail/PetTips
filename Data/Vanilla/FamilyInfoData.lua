local ADDON_NAME, ns = ...

-- Per-family combat classification for beast tooltips (US-51).
-- HAND-MAINTAINED - this file is NOT generator output. Sources
-- (fetched 2026-07-22):
--  - spec + stat modifiers: Petopia Classic family pages
--    (wow-petopia.com/classic/family.php?id=<family>), cross-checked
--    against Wowhead's Classic Hunter Pets guide - identical.
--  - tier: Wowhead's Classic hunter pet tier list (S/A/B/C), as also
--    shipped by the ClassicHunterPetInfo addon; Gorilla is unrated
--    there (tier nil).
-- Keys are the CreatureFamily IDs from FamilyData.lua. Stat modifiers
-- are the family's multipliers on the base pet stats (kept for future
-- display; the tooltip line shows spec + tier only).
--
-- info(familyId, spec, tier, health, armor, damage)

ns.FAMILY_INFO = {}
local function info(familyId, spec, tier, health, armor, damage)
    ns.FAMILY_INFO[familyId] = {
        spec = spec, tier = tier,
        health = health, armor = armor, damage = damage,
    }
end

info(1,  "general", "A",  1.00, 1.05, 1.00) -- Wolf
info(2,  "offense", "S",  0.98, 1.00, 1.10) -- Cat
info(3,  "offense", "B",  1.00, 1.00, 1.07) -- Spider
info(4,  "defense", "C",  1.08, 1.05, 0.91) -- Bear
info(5,  "defense", "A",  1.04, 1.09, 0.90) -- Boar
info(6,  "defense", "B",  0.95, 1.10, 1.00) -- Crocolisk
info(7,  "general", "B",  1.00, 1.05, 1.00) -- Carrion Bird
info(8,  "defense", "C",  0.96, 1.13, 0.95) -- Crab
info(9,  "defense", nil,  1.04, 1.00, 1.02) -- Gorilla (unrated on Wowhead)
info(11, "offense", "S",  0.95, 1.03, 1.10) -- Raptor
info(12, "defense", "B",  1.05, 1.00, 1.00) -- Tallstrider
info(20, "defense", "A",  1.00, 1.10, 0.94) -- Scorpid
info(21, "defense", "C",  1.00, 1.13, 0.90) -- Turtle
info(24, "offense", "B",  1.00, 1.00, 1.07) -- Bat
info(25, "general", "B",  1.00, 1.05, 1.00) -- Hyena
info(26, "offense", "B",  1.00, 1.00, 1.07) -- Owl
info(27, "offense", "A",  1.00, 1.00, 1.07) -- Wind Serpent
