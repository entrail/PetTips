local ADDON_NAME, ns = ...
local L = ns.L

-- WhatsTraining-style training list inside the spellbook's PET tab.
-- A side tab (own CheckButton, SpellBookSkillLineTabTemplate) appears on
-- the right edge of the spellbook while the Pet tab is active - Blizzard
-- hides all real skill-line tabs in pet mode, so that edge is free. When
-- checked, the 12 SpellButtons + page controls are hidden and the list is
-- shown on the book's parchment instead.
--
-- Sections (per current pet):
--  * Available now      - highest rank per ability you can teach right now
--  * From your current pet - pet knows it, you haven't learned it yet
--  * Needs level/points - you know it, pet can't take it yet
--  * Not learned yet    - tagged (trainer) / (taming); taming rows list
--                         teaching mobs in their tooltip
--  * Known by pet       - gray reference section (optional)

local ROW_HEIGHT = 21
local BEAST_TRAINING_SPELL = 5149

local COLORS = {
    header    = { 0.95, 0.95, 0.95 },
    now       = { 0.10, 1.00, 0.10 },
    fromPet   = { 0.40, 0.75, 1.00 },
    gated     = { 1.00, 1.00, 1.00 },
    notKnown  = { 1.00, 0.45, 0.35 },
    known     = { 0.55, 0.55, 0.55 },
    note      = { 0.80, 0.80, 0.80 },
    tag       = { 0.65, 0.65, 0.65 },
}

local tab, overlay, scrollFrame, scrollContent, tpText
local rows = {} -- row pool inside scrollContent, grows as needed
local displayList = {}
local searchFilter = "" -- lowercased text of the search box
local sourceFilter = { taming = true, trainer = true } -- both on by default

-- US-13 family selector: nil = default (current pet, or all families
-- without a pet), "all" = all families, number = a specific family ID.
-- Lives only while the view is open (reset on hide and on pet change).
local familySelection = nil

-- effective family for the list: returns famId (nil = all families) and
-- whether we are BROWSING a family other than the actual pet's (then
-- pet level/points don't apply - a future pet can be up to hunter level)
local function EffectiveFamily()
    local curFam = ns.GetPetFamilyId()
    if familySelection == "all" then return nil, curFam ~= nil end
    if familySelection then
        return familySelection, familySelection ~= curFam
    end
    return curFam, false
end

local function SetFamilySelection(sel)
    familySelection = sel
    ns.RefreshTrainingList()
end

-- ---------------------------------------------------------------- data

local function RankDisplayName(entry)
    local name = GetSpellInfo(entry.spell) or ("spell " .. entry.spell)
    if #entry.ability.ranks > 1 then
        return string.format("%s %d", name, entry.rank)
    end
    return name
end

local function SourceTag(entry)
    if entry.src == "t" then return L["(trainer)"]
    elseif entry.src == "w" then return L["(taming)"]
    elseif entry.src == "tw" then return L["(trainer or taming)"]
    elseif entry.src == "g" then return L["(grimoire)"]
    elseif entry.src == "a" then return L["(with the demon)"]
    else return L["(no known source)"] end
end

-- WhatsTraining-style right column: "5 TP | Level 8". TP is white while
-- the pet has enough unspent points, red otherwise. Level is white when
-- the pet meets it, orange while only the hunter does (pet just has to
-- catch up), red when even the hunter is below the requirement.
local function LevelText(entry)
    -- warlock: grimoire price (red while you can't afford it) | required
    -- WARLOCK level (red while below it) - demons have no TP or pet level
    if ns.isWarlock then
        local playerLevel = UnitLevel("player") or 0
        local lvlColor = (playerLevel >= entry.level) and "|cffffffff" or "|cffff2020"
        local left
        if entry.src == "g" then
            if GetMoney() >= (entry.money or 0) then
                left = GetCoinTextureString(entry.money or 0)
            else
                left = "|cffff2020" .. GetCoinTextureString(entry.money or 0) .. "|r"
            end
        else
            left = L["auto"]
        end
        return string.format("%s || %s%s|r", left,
            lvlColor, string.format(L["Level %d"], entry.level))
    end
    local _, browsing = EffectiveFamily()
    -- browsing another family: no pet level to compare, key off hunter level
    local petLevel = browsing and 0 or (UnitLevel("pet") or 0)
    local playerLevel = UnitLevel("player") or 0
    local totalTP, spentTP = GetPetTrainingPoints()
    local freeTP = (totalTP or 0) - (spentTP or 0)

    local tpColor = (freeTP >= entry.tp) and "|cffffffff" or "|cffff2020"
    local lvlColor
    if petLevel >= entry.level then
        lvlColor = "|cffffffff"
    elseif playerLevel >= entry.level then
        lvlColor = "|cffff8000"
    else
        lvlColor = "|cffff2020"
    end
    -- "||" renders as a literal | in WoW font strings
    return string.format("%s%s|r || %s%s|r",
        tpColor, string.format(L["%d TP"], entry.tp),
        lvlColor, string.format(L["Level %d"], entry.level))
end

-- WhatsTraining-style ordering: by required pet level, then name, then rank
local function SortByLevel(list)
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        local an = GetSpellInfo(a.spell) or ""
        local bn = GetSpellInfo(b.spell) or ""
        if an ~= bn then return an < bn end
        return a.rank < b.rank
    end)
end

-- Warlock sections: a demon rank is either known (bought grimoire / came
-- with the demon), buyable right now (highest rank whose warlock level is
-- met - lower unbought ranks would only waste gold), or level-gated.
-- Known-state: live pet spellbook for the summoned demon, plus the
-- per-character cache (ns.chardb.knownTeach) filled whenever a demon is
-- summoned (KnownTraining.lua) - that covers browsing the other demons.
local function BuildSectionsWarlock()
    local sections = { now = {}, fromPet = {}, gated = {}, notKnown = {}, known = {} }
    local famId = EffectiveFamily()
    local playerLevel = UnitLevel("player") or 0
    local knownTeach = ns.chardb.knownTeach
    local curFam = ns.GetPetFamilyId()

    for _, ability in ipairs(ns.PET_ABILITIES) do
        if ns.db.hiddenAbilities[ability.key] then
            -- hidden via the ability filter popup (all ranks)
        elseif not famId or ability.families[famId] then
            local isCurrent = curFam and ability.families[curFam]
            local function rankKnown(r)
                return knownTeach[r.spell] or (isCurrent and IsSpellKnown(r.spell, true))
            end
            local petRank = 0
            for _, r in ipairs(ability.ranks) do
                if rankKnown(r) then petRank = r.rank end
            end
            local best
            for _, r in ipairs(ability.ranks) do
                if r.rank > petRank and r.src == "g" and playerLevel >= r.level then
                    best = r
                end
            end
            for _, r in ipairs(ability.ranks) do
                if rankKnown(r) then
                    table.insert(sections.known, r)
                elseif r.rank < petRank then
                    -- skipped rank below the known one: forever pointless
                elseif best and r.rank < best.rank then
                    -- superseded by a higher buyable rank
                elseif r == best then
                    table.insert(sections.now, r)
                else
                    table.insert(sections.gated, r)
                end
            end
        end
    end
    for _, list in pairs(sections) do SortByLevel(list) end
    return sections, famId, playerLevel, 0
end

local function BuildSections()
    if ns.isWarlock then return BuildSectionsWarlock() end
    local sections = { now = {}, fromPet = {}, gated = {}, notKnown = {}, known = {} }
    local famId, browsing = EffectiveFamily()
    -- browsing another family: a freshly tamed pet can reach hunter level,
    -- and its points are unknown - so gate by hunter level only
    local petLevel, freeTP
    if browsing then
        petLevel = UnitLevel("player") or 0
        freeTP = math.huge
    else
        petLevel = UnitLevel("pet") or 0
        local totalTP, spentTP = GetPetTrainingPoints()
        freeTP = (totalTP or 0) - (spentTP or 0)
    end
    local knownTeach = ns.chardb.knownTeach

    for _, ability in ipairs(ns.PET_ABILITIES) do
        if ns.db.hiddenAbilities[ability.key] then
            -- hidden via the ability filter popup (all ranks)
        elseif not ability.families or not famId or ability.families[famId] then
            local petRank = 0
            for _, r in ipairs(ability.ranks) do
                if IsSpellKnown(r.spell, true) then petRank = r.rank end
            end
            -- highest rank teachable right now; lower teachable ranks are
            -- skipped (teaching them first would only waste points)
            local best
            for _, r in ipairs(ability.ranks) do
                if r.rank > petRank and knownTeach[r.spell]
                    and petLevel >= r.level and freeTP >= r.tp then
                    best = r
                end
            end
            for _, r in ipairs(ability.ranks) do
                if r.rank <= petRank then
                    if IsSpellKnown(r.spell, true) then
                        if knownTeach[r.spell] then
                            table.insert(sections.known, r)
                        else
                            table.insert(sections.fromPet, r)
                        end
                    end
                elseif best and r.rank < best.rank then
                    -- superseded by a higher teachable rank
                elseif r == best then
                    table.insert(sections.now, r)
                elseif knownTeach[r.spell] then
                    table.insert(sections.gated, r)
                else
                    table.insert(sections.notKnown, r)
                end
            end
        end
    end
    for _, list in pairs(sections) do SortByLevel(list) end
    return sections, famId, petLevel, freeTP
end
ns.BuildTrainingSections = BuildSections -- shared with the Beast Training side panel

local function BuildDisplayList()
    wipe(displayList)
    local sections, famId, petLevel, freeTP = BuildSections()

    -- family selector is always the first row (US-13)
    table.insert(displayList, { kind = "family" })
    if ns.isWarlock then
        -- bought grimoires are only visible while that demon is summoned;
        -- warn whenever the view includes a demon whose known-state was
        -- never recorded (also with NO pet out - that list is stale too).
        -- Demons the warlock can't even summon yet are never stale: no
        -- summon = no grimoire could ever have been used = nothing missing.
        local selFam = EffectiveFamily()
        local synced = ns.chardb.syncedDemonFams or {}
        local curFam = ns.GetPetFamilyId()
        local function needsSync(id)
            return id ~= curFam and not synced[id] and ns.CanSummonDemonFamily(id)
        end
        local stale = false
        if selFam then
            stale = needsSync(selFam)
        else
            for id in pairs(ns.PET_FAMILIES) do
                if needsSync(id) then stale = true end
            end
        end
        if stale then
            table.insert(displayList, { kind = "note",
                text = L["Bought grimoires are recorded while that demon is summoned."] })
        end
    elseif not ns.chardb.scannedBeastTraining then
        table.insert(displayList, { kind = "note", beastSync = true,
            text = L["Open Beast Training once to sync what you know."] })
    end
    if UnitExists("pet") and not ns.GetPetFamilyId() then
        table.insert(displayList, { kind = "note",
            text = L["Unknown pet family - showing all abilities."] })
    end

    local function Matches(r)
        -- both on = everything (incl. the two "no known source" ranks);
        -- exactly one on = that source only; both off = nothing
        -- (warlocks have no source filter buttons - everything is grimoires)
        if not ns.isWarlock and not (sourceFilter.taming and sourceFilter.trainer) then
            local fromTaming = r.src == "w" or r.src == "tw"
            local fromTrainer = r.src == "t" or r.src == "tw"
            if not ((sourceFilter.taming and fromTaming)
                or (sourceFilter.trainer and fromTrainer)) then
                return false
            end
        end
        if searchFilter == "" then return true end
        local name = GetSpellInfo(r.spell)
        return name and strlower(name):find(searchFilter, 1, true) ~= nil
    end

    local function AddSection(headerText, list, color, rightFn, tagFn)
        local matched = {}
        for _, r in ipairs(list) do
            if Matches(r) then matched[#matched + 1] = r end
        end
        if #matched == 0 then return end
        table.insert(displayList, { kind = "header", text = headerText })
        for _, r in ipairs(matched) do
            table.insert(displayList, { kind = "rank", entry = r, color = color,
                right = rightFn and rightFn(r) or nil,
                tag = tagFn and tagFn(r) or nil })
        end
    end

    -- right column is always the required pet level (WhatsTraining look);
    -- TP / money costs and mob lists live in the row tooltip
    if ns.isWarlock then
        AddSection(L["Available now"], sections.now, COLORS.now, LevelText)
        AddSection(L["Needs your level"], sections.gated, COLORS.gated, LevelText, SourceTag)
    else
        AddSection(L["Available now"], sections.now, COLORS.now, LevelText)
        AddSection(L["From your current pet"], sections.fromPet, COLORS.fromPet, LevelText)
        AddSection(L["Needs pet level / points"], sections.gated, COLORS.gated, LevelText)
        AddSection(L["Not learned by you yet"], sections.notKnown, COLORS.notKnown, LevelText, SourceTag)
    end
    if ns.db.showKnownByPet then
        AddSection(L["Known by pet"], sections.known, COLORS.known, function()
            return L["known"]
        end)
    end

    if #displayList == 0 then
        table.insert(displayList, { kind = "note", text = L["Nothing to show - summon a pet."] })
    end
end

-- ---------------------------------------------------------------- rows

-- shared with the Beast Training side panel (KnownTraining.lua)
function ns.ShowRankTooltip(entry, owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(entry.spell)
    GameTooltip:AddLine(" ")
    if ns.isWarlock then
        GameTooltip:AddLine(string.format(L["Requires warlock level %d."], entry.level),
            0.9, 0.9, 0.9, true)
    else
        GameTooltip:AddLine(string.format(L["Requires pet level %d, costs %d training points."],
            entry.level, entry.tp), 0.9, 0.9, 0.9, true)
    end
    local fams = entry.ability.families
    if fams then
        local famId = ns.GetPetFamilyId()
        if not famId or not fams[famId] then
            local names = {}
            for id in pairs(fams) do names[#names + 1] = ns.PET_FAMILIES[id] end
            table.sort(names)
            GameTooltip:AddLine(string.format(L["Usable by: %s"], table.concat(names, ", ")),
                0.7, 0.6, 0.9, true)
        end
    end
    if ns.isWarlock then
        if entry.src == "g" then
            -- GetItemInfo is async on the first query; the name fills in
            -- on the next hover (the call itself triggers the request)
            local iname = entry.item and GetItemInfo(entry.item)
            GameTooltip:AddLine(string.format(L["Grimoire: %s"], iname or "..."),
                0.6, 0.9, 0.6, true)
            GameTooltip:AddLine(string.format(L["Costs %s at a demon trainer."],
                GetCoinTextureString(entry.money or 0)), 0.6, 0.9, 0.6, true)
        else
            GameTooltip:AddLine(L["Your demon knows this from the start."], 0.6, 0.9, 0.6, true)
        end
        GameTooltip:Show()
        return
    end
    if entry.src == "t" or entry.src == "tw" then
        if entry.money and entry.money > 0 then
            GameTooltip:AddLine(string.format(L["Pet trainer cost: %s"],
                GetCoinTextureString(entry.money)), 0.6, 0.9, 0.6)
        else
            GameTooltip:AddLine(L["Taught by pet trainers (learned for money)."], 0.6, 0.9, 0.6, true)
        end
    end
    if entry.src == "w" or entry.src == "tw" then
        local mobs = ns.MOBS_BY_SPELL[entry.spell]
        if mobs then
            GameTooltip:AddLine(L["Learn by taming, then let the pet use it:"], 0.6, 0.9, 0.6, true)
            -- mobs in the zone the player is standing in come first, in
            -- green (matched by zone ID, so it works on every locale)
            local zoneKeys = ns.GetPlayerZoneKeys()
            local function inZone(m)
                if m.zoneIds then
                    for _, id in ipairs(m.zoneIds) do
                        if zoneKeys[id] then return true end
                    end
                end
                return false
            end
            local sorted = {}
            for i, m in ipairs(mobs) do sorted[i] = m end
            table.sort(sorted, function(a, b)
                local az, bz = inZone(a), inZone(b)
                if az ~= bz then return az end
                return a.minLevel < b.minLevel
            end)
            local max = ns.db.mobLines or 10
            for i = 1, math.min(#sorted, max) do
                local m = sorted[i]
                local lvl = (m.minLevel == m.maxLevel) and tostring(m.minLevel)
                    or (m.minLevel .. "-" .. m.maxLevel)
                if inZone(m) then
                    GameTooltip:AddLine(string.format("%s  (%s, %s)", ns.GetMobName(m), ns.GetMobZoneText(m), lvl),
                        0.2, 1.0, 0.2)
                else
                    GameTooltip:AddLine(string.format("%s  (%s, %s)", ns.GetMobName(m), ns.GetMobZoneText(m), lvl),
                        0.8, 0.8, 0.8)
                end
            end
            if #sorted > max then
                GameTooltip:AddLine(string.format(L["+%d more"], #sorted - max), 0.6, 0.6, 0.6)
            end
        end
    end
    GameTooltip:Show()
end

local function Row_OnEnter(self)
    local item = self.item
    if not item or item.kind ~= "rank" then return end
    ns.ShowRankTooltip(item.entry, self)
end

-- family dropdown on the selector row (modern menu API - present on Era,
-- WhatsTraining uses it too)
local function OpenFamilyMenu(row)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(row, function(_, rootDescription)
        rootDescription:CreateTitle(L["Pet family"])
        local curFam = ns.GetPetFamilyId()
        if curFam then
            rootDescription:CreateRadio(
                string.format(L["Current pet (%s)"], ns.PET_FAMILIES[curFam] or "?"),
                function() return familySelection == nil end,
                function() SetFamilySelection(nil) end)
        end
        rootDescription:CreateRadio(L["All families"],
            function() return familySelection == "all" or (familySelection == nil and not curFam) end,
            function() SetFamilySelection(curFam and "all" or nil) end)
        local fams = {}
        for id, name in pairs(ns.PET_FAMILIES) do
            fams[#fams + 1] = { id = id, name = name }
        end
        table.sort(fams, function(a, b) return a.name < b.name end)
        for _, f in ipairs(fams) do
            rootDescription:CreateRadio(f.name,
                function(id) return familySelection == id end,
                function(id) SetFamilySelection(id) end, f.id)
        end
    end)
end

local function FamilyRowLabel()
    local label
    if familySelection == "all" then
        label = L["All families"]
    elseif familySelection then
        label = ns.PET_FAMILIES[familySelection] or "?"
    else
        local curFam = ns.GetPetFamilyId()
        if curFam then
            label = string.format(L["Current pet (%s)"], ns.PET_FAMILIES[curFam] or "?")
        else
            label = L["All families"]
        end
    end
    return string.format("%s %s |TInterface\\ChatFrame\\ChatFrameExpandArrow:12|t",
        L["Family:"], label)
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, scrollContent)
    row:SetSize(scrollContent:GetWidth() - 4, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 2, -(index - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\AddOns\\PetTips\\Textures\\highlight")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(17, 17)
    row.icon:SetPoint("LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.text:SetJustifyH("LEFT")

    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.right:SetPoint("RIGHT", -2, 0)
    row.right:SetJustifyH("RIGHT")
    row.text:SetPoint("RIGHT", row.right, "LEFT", -4, 0)

    row:SetScript("OnEnter", Row_OnEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.item and self.item.kind == "family" then
            OpenFamilyMenu(self)
        elseif self.item and self.item.kind == "note" and self.item.beastSync then
            if ns.ShowBeastSyncPopup then ns.ShowBeastSyncPopup() end
        end
    end)
    return row
end

local function RefreshRows()
    for i = 1, #displayList do
        local row = rows[i]
        if not row then
            row = CreateRow(i)
            rows[i] = row
        end
        local item = displayList[i]
        row.item = item
        do
            row:Show()
            if item.kind == "header" then
                -- WhatsTraining-style separator: centered white text
                row.icon:SetTexture(nil)
                row.text:SetJustifyH("CENTER")
                row.text:SetText(item.text)
                row.text:SetTextColor(unpack(COLORS.header))
                row.right:SetText("")
            elseif item.kind == "family" then
                row.icon:SetTexture(nil)
                row.text:SetJustifyH("LEFT")
                row.text:SetText(FamilyRowLabel())
                row.text:SetTextColor(1, 0.82, 0)
                row.right:SetText("")
            elseif item.kind == "note" then
                row.icon:SetTexture(nil)
                row.text:SetJustifyH("LEFT")
                row.text:SetText(item.text)
                row.text:SetTextColor(unpack(COLORS.note))
                row.right:SetText("")
            else
                local entry = item.entry
                local _, _, icon = GetSpellInfo(entry.spell)
                row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local name = RankDisplayName(entry)
                if item.tag then
                    name = name .. " |cff909090" .. item.tag .. "|r"
                end
                row.text:SetJustifyH("LEFT")
                row.text:SetText(name)
                row.text:SetTextColor(unpack(item.color or COLORS.gated))
                row.right:SetText(item.right or "")
                row.right:SetTextColor(0.8, 0.8, 0.8)
            end
        end
    end
    for i = #displayList + 1, #rows do
        rows[i]:Hide()
        rows[i].item = nil
    end
    scrollContent:SetHeight(math.max(1, #displayList * ROW_HEIGHT))

    if ns.isWarlock then
        -- what a trip to the demon trainer costs right now
        local total = 0
        for _, item in ipairs(displayList) do
            if item.kind == "rank" and item.color == COLORS.now then
                total = total + (item.entry.money or 0)
            end
        end
        if total > 0 then
            tpText:SetText(string.format(L["Grimoires to buy: %s"], GetCoinTextureString(total)))
        else
            tpText:SetText("")
        end
    else
        local totalTP, spentTP = GetPetTrainingPoints()
        tpText:SetText(string.format(L["%d TP unspent"], (totalTP or 0) - (spentTP or 0)))
    end
end

function ns.RefreshTrainingList()
    if overlay and overlay:IsShown() then
        BuildDisplayList()
        RefreshRows()
    end
end

-- /pettips list: dump what the list computation sees (family, levels,
-- section sizes), to diagnose "why is X not shown".
function ns.TrainingListDebug()
    local sections, famId, petLevel, freeTP = BuildSections()
    local knownCount = 0
    for _ in pairs(ns.chardb.knownTeach) do knownCount = knownCount + 1 end
    print(string.format("PetTips list (%s): family=%s (%s), gate level %d, %d TP free, known ranks=%d, synced=%s",
        tostring(ns.playerClass), tostring(famId), tostring(UnitCreatureFamily("pet")), petLevel, freeTP,
        knownCount, tostring(ns.chardb.scannedBeastTraining)))
    print(string.format("  sections: available=%d fromPet=%d needsLevel/TP=%d notLearned=%d knownByPet=%d",
        #sections.now, #sections.fromPet, #sections.gated, #sections.notKnown, #sections.known))
    BuildDisplayList()
    print(string.format("  total display rows: %d", #displayList))
end

-- ------------------------------------------------- first-run sync popup
-- Until Beast Training was scanned once, the list can only guess - so on
-- opening the view a centered dialog offers a one-click way to the sync:
-- a SecureActionButton that casts Beast Training (5149) directly (allowed
-- on a hardware click, out of combat). The popup hides itself the moment
-- the craft window opens (CRAFT_SHOW - ScanCraft does the actual sync),
-- with the spellbook, or via "Later" (for the rest of the session; the
-- note row in the list brings it back). Hunters below the level-10 taming
-- quests don't know the spell yet - no popup for them, the note suffices.

local syncPopup, syncPopupDismissed

local function ShowSyncPopup()
    if InCombatLockdown() or not IsPlayerSpell(BEAST_TRAINING_SPELL) then return end
    if not syncPopup then
        -- docked to the right edge of the book (clear of the side tabs),
        -- same dark backdrop as the addon's other panels - present but
        -- not a modal in the middle of the screen. Parented to the
        -- overlay, so it comes and goes with the training view.
        syncPopup = CreateFrame("Frame", "PetTipsSyncPopup", overlay, "BackdropTemplate")
        syncPopup:SetSize(240, 136)
        syncPopup:SetPoint("TOPLEFT", overlay, "TOPRIGHT", 8, -45)
        syncPopup:SetFrameStrata("DIALOG")
        syncPopup:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        syncPopup:SetBackdropColor(0, 0, 0, 0.9)

        local title = syncPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetText("PetTips")

        -- why (the game only reveals known ranks in that window) and
        -- what to do (one click, everything else is automatic)
        local text = syncPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", 10, -26)
        text:SetPoint("TOPRIGHT", -10, -26)
        text:SetJustifyH("LEFT")
        text:SetText(L["PetTips can't see which ranks you can already teach - the game only reveals that in the Beast Training window. Click the button; the list fills in by itself."])

        local spellName = GetSpellInfo(BEAST_TRAINING_SPELL)
        local cast = CreateFrame("Button", "PetTipsSyncCastButton", syncPopup,
            "SecureActionButtonTemplate,UIPanelButtonTemplate")
        cast:SetSize(146, 22)
        cast:SetPoint("BOTTOMLEFT", 10, 10)
        cast:SetText(spellName or "?")
        cast:SetAttribute("type", "spell")
        cast:SetAttribute("spell", spellName)
        cast:RegisterForClicks("AnyUp")

        local later = CreateFrame("Button", nil, syncPopup, "UIPanelButtonTemplate")
        later:SetSize(70, 22)
        later:SetPoint("BOTTOMRIGHT", -10, 10)
        later:SetText(L["Later"])
        later:SetScript("OnClick", function()
            syncPopupDismissed = true
            syncPopup:Hide()
        end)

        -- craft window opening = mission accomplished; the popup's own
        -- frame is insecure, so hiding it is legal even in combat
        syncPopup:RegisterEvent("CRAFT_SHOW")
        syncPopup:SetScript("OnEvent", function(self) self:Hide() end)
    end
    syncPopup:Show()
end

local function MaybeShowSyncPopup()
    if not ns.isWarlock and not ns.chardb.scannedBeastTraining
        and not syncPopupDismissed then
        ShowSyncPopup()
    end
end

-- clicking the sync note row re-opens the popup even after "Later"
ns.ShowBeastSyncPopup = function()
    syncPopupDismissed = false
    ShowSyncPopup()
end

-- ---------------------------------------------------------------- overlay

local hiddenByUs = false

-- The list is reachable from the Pet tab AND always from the Spellbook
-- tab (one slot below WhatsTraining's "?") - so a stabled/dismissed pet
-- never locks you out and the tab doesn't come and go.
local function ListBookMode()
    return SpellBookFrame.bookType == BOOKTYPE_PET
        or SpellBookFrame.bookType == BOOKTYPE_SPELL
end

local function OverlayActive()
    return ns.db.enableList
        and tab and tab:GetChecked()
        and SpellBookFrame:IsShown()
        and ListBookMode()
end

local function ApplyOverlay()
    if OverlayActive() then
        if not InCombatLockdown() then -- SpellButtons inherit SecureFrameTemplate
            for i = 1, SPELLS_PER_PAGE do _G["SpellButton" .. i]:Hide() end
            SpellBookPrevPageButton:Hide()
            SpellBookNextPageButton:Hide()
            SpellBookPageText:Hide()
            if ShowAllSpellRanksCheckbox then ShowAllSpellRanksCheckbox:Hide() end
            hiddenByUs = true
        end
        BuildDisplayList()
        overlay:Show()
        RefreshRows()
        MaybeShowSyncPopup()
    else
        overlay:Hide()
        if hiddenByUs and not InCombatLockdown() then
            hiddenByUs = false
            SpellBookPrevPageButton:Show()
            SpellBookNextPageButton:Show()
            SpellBookPageText:Show()
            if SpellBookFrame:IsShown() then
                SpellBookFrame:Update() -- re-shows the spell buttons
            end
        end
    end
end

local function CreateUI()
    tab = CreateFrame("CheckButton", "PetTipsSpellbookTab", SpellBookFrame,
        "SpellBookSkillLineTabTemplate")
    -- fixed slot 6, directly above WhatsTraining's "?" (slot 7, spell mode
    -- only) - the SAME position in both book modes, so the tab never jumps
    -- when switching between the spellbook and the pet book
    tab:SetPoint("TOPLEFT", _G["SpellBookSkillLineTab" .. (MAX_SKILLLINE_TABS - 2)], "TOPLEFT", 0, 0)
    -- warlocks get the Summon Imp icon (there is no Beast Training spell)
    local icon = select(3, GetSpellInfo(ns.isWarlock and 688 or BEAST_TRAINING_SPELL))
    tab:SetNormalTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    tab.tooltip = ns.isWarlock and L["Demon Training"] or L["Pet Training"]
    tab:Hide()
    -- replaces the template's skill-line OnClick
    tab:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
        -- WhatsTraining's page occupies the book the same way we do; it is
        -- driven by SpellBookFrame.selectedSkillLine, so deselecting its
        -- tab closes it before our list opens
        if self:GetChecked() and SpellBookFrame.bookType == BOOKTYPE_SPELL then
            local wtFrame = _G["WhatsTrainingFrame"]
            if wtFrame and wtFrame:IsShown()
                and SpellBookFrame.selectedSkillLine == MAX_SKILLLINE_TABS - 1 then
                SpellBookFrame.selectedSkillLine = 2
                SpellBookFrame:Update()
                self:SetChecked(true) -- Update unchecks nothing of ours, but be safe
            end
        end
        ApplyOverlay()
    end)

    -- clicking ANY skill-line tab (the class tabs or WhatsTraining's "?")
    -- closes our list - Blizzard's and WhatsTraining's pages take over
    if type(SpellBookSkillLineTab_OnClick) == "function" then
        hooksecurefunc("SpellBookSkillLineTab_OnClick", function()
            if tab:GetChecked() then
                tab:SetChecked(false)
                ApplyOverlay()
            end
        end)
    end

    -- full-book overlay with WhatsTraining's dark art (MIT-licensed
    -- textures from fusionpit/WhatsTraining, see AGENTS.md)
    overlay = CreateFrame("Frame", "PetTipsTrainingFrame", SpellBookFrame)
    overlay:SetAllPoints(SpellBookFrame)
    overlay:SetFrameStrata("HIGH")
    overlay:Hide()

    local leftBG = overlay:CreateTexture(nil, "ARTWORK")
    leftBG:SetTexture("Interface\\AddOns\\PetTips\\Textures\\left")
    leftBG:SetSize(256, 512)
    leftBG:SetPoint("TOPLEFT", overlay)
    local rightBG = overlay:CreateTexture(nil, "ARTWORK")
    rightBG:SetTexture("Interface\\AddOns\\PetTips\\Textures\\right")
    rightBG:SetSize(128, 512)
    rightBG:SetPoint("TOPRIGHT", overlay)

    -- search box, same spot as WhatsTraining's
    local search = CreateFrame("EditBox", "PetTipsSearchBox", overlay, "SearchBoxTemplate")
    search:SetSize(124, 32)
    search:SetPoint("TOPLEFT", overlay, "TOPLEFT", 81, -34)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        SearchBoxTemplate_OnTextChanged(self)
        local text = strlower(strtrim(self:GetText() or ""))
        if text ~= searchFilter then
            searchFilter = text
            BuildDisplayList()
            RefreshRows()
        end
    end)

    -- source filter toggles right of the search box; active = held down
    local function CreateFilterButton(key, label, anchorTo, gap)
        local btn = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
        btn:SetSize(58, 22)
        btn:SetPoint("LEFT", anchorTo, "RIGHT", gap, 0)
        btn:SetText(label)
        if sourceFilter[key] then btn:LockHighlight() end
        btn:SetScript("OnClick", function(self)
            sourceFilter[key] = not sourceFilter[key]
            if sourceFilter[key] then self:LockHighlight() else self:UnlockHighlight() end
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            BuildDisplayList()
            RefreshRows()
        end)
        return btn
    end
    -- warlock demons learn everything from grimoires - no source split
    local filterAnchor = search
    if not ns.isWarlock then
        local tamingButton = CreateFilterButton("taming", L["Taming"], search, 1)
        filterAnchor = CreateFilterButton("trainer", L["Trainer"], tamingButton, 2)
    end

    -- ability filter: gear button opening a checklist with one entry per
    -- ability (no ranks); unticked abilities disappear from every list.
    -- Persisted account-wide in PetTipsDB.hiddenAbilities.
    local hidePopup, popupChecks, hideButton
    local function BuildHidePopup()
        hidePopup = CreateFrame("Frame", "PetTipsAbilityFilter", overlay, "BackdropTemplate")
        hidePopup:SetFrameStrata("DIALOG")
        hidePopup:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        hidePopup:SetBackdropColor(0, 0, 0, 0.95)

        local title = hidePopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetText(L["Shown abilities"])

        local entries = {}
        for _, ability in ipairs(ns.PET_ABILITIES) do
            entries[#entries + 1] = ability
        end
        table.sort(entries, function(a, b)
            return (GetSpellInfo(a.ranks[1].spell) or a.key)
                < (GetSpellInfo(b.ranks[1].spell) or b.key)
        end)

        local rowH, colW, perCol = 21, 150, math.ceil(#entries / 2)
        popupChecks = {}
        for i, ability in ipairs(entries) do
            local col = (i > perCol) and 1 or 0
            local rowIdx = (i - 1) % perCol
            local cb = CreateFrame("CheckButton", nil, hidePopup, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", 8 + col * colW, -24 - rowIdx * rowH)
            cb.abilityKey = ability.key

            local icon = hidePopup:CreateTexture(nil, "ARTWORK")
            icon:SetSize(15, 15)
            icon:SetPoint("LEFT", cb, "RIGHT", 1, 0)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            icon:SetTexture(select(3, GetSpellInfo(ability.ranks[1].spell))
                or "Interface\\Icons\\INV_Misc_QuestionMark")

            local label = hidePopup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", icon, "RIGHT", 3, 0)
            label:SetText(GetSpellInfo(ability.ranks[1].spell) or ability.key)
            label:SetTextColor(0.9, 0.9, 0.9)

            cb:SetScript("OnClick", function(self)
                ns.db.hiddenAbilities[self.abilityKey] = (not self:GetChecked()) or nil
                BuildDisplayList()
                RefreshRows()
                if ns.RefreshCraftSidePanel then ns.RefreshCraftSidePanel() end
            end)
            popupChecks[#popupChecks + 1] = cb
        end
        hidePopup:SetSize(8 + 2 * colW + 8, 24 + perCol * rowH + 10)
        -- anchored to the overlay, not the cog button: the cog sits far
        -- left on warlocks (no filter buttons), which would push a
        -- right-anchored popup out of the book's left edge
        hidePopup:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -39, -60)
        hidePopup:Hide()
    end

    hideButton = CreateFrame("Button", nil, overlay)
    hideButton:SetSize(22, 22)
    hideButton:SetPoint("LEFT", filterAnchor, "RIGHT", 2, 0)
    hideButton:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    hideButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    hideButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Choose which abilities are shown"], 1, 1, 1)
        GameTooltip:AddLine(L["Untick an ability to hide all of its ranks from the list (e.g. the resistances)."], nil, nil, nil, true)
        GameTooltip:Show()
    end)
    hideButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hideButton:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        if not hidePopup then BuildHidePopup() end
        if hidePopup:IsShown() then
            hidePopup:Hide()
        else
            for _, cb in ipairs(popupChecks) do
                cb:SetChecked(not ns.db.hiddenAbilities[cb.abilityKey])
            end
            hidePopup:Show()
        end
    end)

    tpText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tpText:SetPoint("TOPRIGHT", -70, -64)
    tpText:SetTextColor(1, 0.82, 0)

    -- smooth-scrolling list (real ScrollFrame, no paging), inset exactly
    -- like WhatsTraining: 26px left, 65px right margin - the template's
    -- scrollbar lands inside the dark right margin of the art
    scrollFrame = CreateFrame("ScrollFrame", "PetTipsTrainingScrollFrame", overlay,
        "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 26, -75)
    scrollFrame:SetPoint("BOTTOMRIGHT", -65, 81)

    scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(293, 1)
    scrollFrame:SetScrollChild(scrollContent)

    overlay:SetScript("OnShow", function(self)
        self:RegisterEvent("SPELLS_CHANGED")
        self:RegisterUnitEvent("UNIT_PET", "player")
        self:RegisterEvent("PET_BAR_UPDATE")
    end)
    overlay:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        -- leaving the view always closes the ability-filter popup, or it
        -- would silently reappear with the overlay (it is a child frame)
        if hidePopup then hidePopup:Hide() end
        -- the sync popup belongs to the view too - don't leave it floating
        if syncPopup then syncPopup:Hide() end
        -- US-13: the family selection lives only while the view is open
        familySelection = nil
    end)
    overlay:SetScript("OnEvent", function(_, event)
        if event == "UNIT_PET" then
            -- pet changed: a sticky family filter would silently hide the
            -- new pet's list - snap back to the default
            familySelection = nil
        end
        BuildDisplayList()
        RefreshRows()
    end)

    -- runs after every book update (open, tab switch, page flip, pet change)
    -- switching between the Spellbook and Pet tabs closes our list (like
    -- WhatsTraining does): the reader asked for the page they clicked, not
    -- for our overlay to follow them there
    local lastBookType
    hooksecurefunc(SpellBookFrame, "Update", function()
        local bookType = SpellBookFrame.bookType
        if lastBookType and bookType ~= lastBookType and tab:GetChecked() then
            tab:SetChecked(false)
        end
        lastBookType = bookType
        tab:SetShown(ns.db.enableList and ListBookMode())
        ApplyOverlay()
    end)
    -- UpdateSpells force-shows all 12 buttons; re-hide while we are active
    hooksecurefunc(SpellBookFrame, "UpdateSpells", function()
        if OverlayActive() and hiddenByUs and not InCombatLockdown() then
            for i = 1, SPELLS_PER_PAGE do _G["SpellButton" .. i]:Hide() end
        end
    end)
end

-- Options toggle: hide everything immediately when disabled.
function ns.UpdateTrainingTab()
    if not tab then return end
    if not ns.db.enableList then
        tab:SetChecked(false)
        tab:Hide()
    elseif SpellBookFrame:IsShown() and SpellBookFrame.bookType == BOOKTYPE_PET then
        tab:Show()
    end
    ApplyOverlay()
end

ns.OnLogin(function()
    if ns.playerClass ~= "HUNTER" and ns.playerClass ~= "WARLOCK" then return end
    CreateUI()
end)
