local ADDON_NAME, ns = ...
if not ns.isForever then return end -- plain .toc lists both data sets

-- Per-family combat classification for beast tooltips (US-51).
-- HAND-MAINTAINED - this file is NOT generator output.
--
-- WoW: Forever: deliberately EMPTY. The Classic Era table (Petopia's
-- offense/defense/general split from the family stat modifiers, Wowhead's
-- S-C tiers) does not carry over: Forever pets scale off the hunter's
-- stats, most families gained a new special ability, and no verified
-- Forever source for either the modifiers or a tier list exists yet
-- (checked 2026-09-21). Without an entry the tooltip simply shows no
-- family line - better than a wrong one.
--
-- info(familyId, spec, tier, health, armor, damage) - same shape as the
-- Vanilla/TBC files once data exists.

ns.FAMILY_INFO = {}
