local ADDON_NAME, ns = ...
local L = ns.L

-- Which ability ranks this hunter already knows how to teach. Classic Era
-- exposes that in two different windows, scanned whenever they open:
--  * Beast Training (the hunter spell) is a CRAFT window on Era ("To
--    Craft", CRAFT_SHOW / GetNumCrafts / GetCraftInfo - the same API as
--    vanilla enchanting, NOT the trainer API). Every listed craft is a
--    rank the hunter has learned. Caveat: the list is filtered to the
--    current pet's family, so one visit is not necessarily complete -
--    the cache fills additively across visits/pets.
--  * NPC pet trainers use the real trainer API; services are ranks
--    offered FOR MONEY, only category "used" means already learned.
-- GetTrainerServiceSpellLink does NOT exist on Era (verified in game), so
-- services/crafts are resolved by localized name + rank digit.
-- Additionally the learned-spell event is watched: if the game reports a
-- learned spell whose ID is one of our ability ranks (taming learn), it
-- is cached immediately.
-- Cache: PetTipsCharDB.knownTeach; chardb.scannedBeastTraining marks that
-- Beast Training was scanned at least once.

-- Era 1.15 still has LEARNED_SPELL_IN_TAB; the TBC Anniversary 2.5.6
-- client runs a NEWER engine that removed it in favor of the renamed
-- LEARNED_SPELL_IN_SKILL_LINE (registering the old name THROWS there -
-- found in game 2026-07-21, it silently killed the whole login chain
-- before Core isolated callback errors). Both carry the spellID first,
-- so register whichever the client knows and treat them identically.
local function RegisterLearnedSpell(frame)
    if not pcall(frame.RegisterEvent, frame, "LEARNED_SPELL_IN_TAB") then
        frame:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
    end
end

local function IsLearnedSpellEvent(event)
    return event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE"
end

-- localized ability name -> ability entry (rebuilt per scan; GetSpellInfo
-- can return nil early after login)
local nameToAbility

local function AbilityByLocalName(name)
    if not nameToAbility then
        nameToAbility = {}
        for _, ability in ipairs(ns.PET_ABILITIES) do
            local spellName = GetSpellInfo(ability.ranks[1].spell)
            if spellName then nameToAbility[spellName] = ability end
        end
    end
    return nameToAbility[name]
end

local function ResolveRank(name, rankText)
    local ability = name and AbilityByLocalName(name)
    if not ability then return end
    local rankNo = rankText and tonumber(rankText:match("%d+"))
    if not rankNo and #ability.ranks == 1 then rankNo = 1 end
    return rankNo and ability.ranks[rankNo] or nil
end

local announcedCraft = false
local announcedTrainer = false
local eventLog = {} -- event name -> count, for /pettips debug
local RefreshSidePanel -- forward declaration (Beast Training side panel, below)

local function KnownCount()
    local total = 0
    for _ in pairs(ns.chardb.knownTeach) do total = total + 1 end
    return total
end

-- ---------------------------------------------------------- Beast Training

local function ScanCraft()
    local numCrafts = GetNumCrafts and GetNumCrafts() or 0
    if numCrafts == 0 then return end
    nameToAbility = nil

    local known = ns.chardb.knownTeach
    local matched, newCount = 0, 0
    for i = 1, numCrafts do
        local name, rankText = GetCraftInfo(i)
        local entry = ResolveRank(name, rankText)
        if entry then
            matched = matched + 1
            if not known[entry.spell] then
                known[entry.spell] = true
                newCount = newCount + 1
            end
        end
    end
    -- no pet abilities at all -> some other craft window (e.g. enchanting)
    if matched == 0 then
        RefreshSidePanel(false)
        return
    end
    RefreshSidePanel(true)

    local firstSync = not ns.chardb.scannedBeastTraining
    ns.chardb.scannedBeastTraining = true
    if (firstSync or newCount > 0) and not announcedCraft then
        announcedCraft = true
        print(string.format(L["PetTips: Beast Training synced - %d teachable ranks cached."], KnownCount()))
    end
    if ns.RefreshTrainingList then ns.RefreshTrainingList() end
end

-- ------------------------------------------------------- NPC pet trainer

local function ScanTrainer()
    local numServices = GetNumTrainerServices()
    if not numServices or numServices == 0 then return end
    nameToAbility = nil

    local known = ns.chardb.knownTeach
    local newCount = 0
    for i = 1, numServices do
        local name, rankText, category = GetTrainerServiceInfo(i)
        local entry = ResolveRank(name, rankText)
        -- only "used" services are ranks the hunter already bought
        if entry and category == "used" and not known[entry.spell] then
            known[entry.spell] = true
            newCount = newCount + 1
        end
    end

    if newCount > 0 and not announcedTrainer then
        announcedTrainer = true
        print(string.format(L["PetTips: pet trainer synced - %d newly recorded ranks."], newCount))
    end
    if newCount > 0 and ns.RefreshTrainingList then ns.RefreshTrainingList() end
end

-- ---------------------------------------- Beast Training side panel
-- The window itself only lists ranks the hunter already knows, so a side
-- panel attached to it shows the rest for the current pet, in sections
-- with centered dividers like the spellbook list: ranks the hunter knows
-- but the pet can't take yet (white), ranks not learned at all (red,
-- tagged trainer/taming) and - optional, same setting as the main list -
-- the ranks the pet already knows (gray). Smooth scroll, no "+N more".
-- Rank tooltips (incl. taming mob lists) are shared with the main list.
-- The Beast Training window itself stays completely untouched.

local PANEL_ROW_HEIGHT = 16

local sidePanel, sideScroll, sideContent
local sideRows = {}

local function SideTag(entry)
    if entry.src == "t" then return L["(trainer)"]
    elseif entry.src == "w" then return L["(taming)"]
    elseif entry.src == "tw" then return L["(trainer or taming)"]
    else return L["(no known source)"] end
end

local function EnsureSidePanel()
    if sidePanel then return end
    sidePanel = CreateFrame("Frame", "PetTipsCraftPanel", CraftFrame, "BackdropTemplate")
    -- anchored to both corners of the window's right edge, so the panel
    -- tracks the Beast Training window's height - including live resizes
    -- by other addons (anchors re-evaluate automatically)
    sidePanel:SetPoint("TOPLEFT", CraftFrame, "TOPRIGHT", -34, -12)
    sidePanel:SetPoint("BOTTOMLEFT", CraftFrame, "BOTTOMRIGHT", -34, 76)
    sidePanel:SetWidth(250)
    sidePanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    sidePanel:SetBackdropColor(0, 0, 0, 0.9)

    local title = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText(L["Missing for this pet"])

    sideScroll = CreateFrame("ScrollFrame", "PetTipsCraftPanelScroll", sidePanel,
        "UIPanelScrollFrameTemplate")
    sideScroll:SetPoint("TOPLEFT", 8, -26)
    sideScroll:SetPoint("BOTTOMRIGHT", -28, 8)
    sideContent = CreateFrame("Frame", nil, sideScroll)
    sideContent:SetSize(214, 1)
    sideScroll:SetScrollChild(sideContent)
end

local function SideRow(i)
    local row = sideRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, sideContent)
    row:SetSize(210, PANEL_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * PANEL_ROW_HEIGHT)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.text:SetPoint("LEFT", 0, 0)
    row.text:SetJustifyH("LEFT")
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.right:SetPoint("RIGHT", 0, 0)
    row.right:SetJustifyH("RIGHT")
    row.text:SetPoint("RIGHT", row.right, "LEFT", -4, 0)

    row:SetScript("OnEnter", function(self)
        if self.entry then ns.ShowRankTooltip(self.entry, self) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sideRows[i] = row
    return row
end

function RefreshSidePanel(isBeastTraining) -- assigns the forward-declared local
    if not isBeastTraining or not ns.db.craftPanel then
        if sidePanel then sidePanel:Hide() end
        return
    end
    EnsureSidePanel()
    local sections = ns.BuildTrainingSections()
    local petLevel = UnitLevel("pet") or 0
    local playerLevel = UnitLevel("player") or 0

    local items = {}
    local function AddSection(headerText, list, color, opts)
        if #list == 0 then return end
        items[#items + 1] = { header = headerText }
        for _, r in ipairs(list) do
            items[#items + 1] = { entry = r, color = color,
                tag = opts and opts.tag and SideTag(r) or nil,
                known = opts and opts.known or nil }
        end
    end
    AddSection(L["Needs pet level / points"], sections.gated, { 1, 1, 1 })
    AddSection(L["Not learned by you yet"], sections.notKnown, { 1, 0.45, 0.35 }, { tag = true })
    if ns.db.showKnownByPet then
        AddSection(L["Known by pet"], sections.known, { 0.55, 0.55, 0.55 }, { known = true })
    end

    for i = 1, #items do
        local row = SideRow(i)
        local item = items[i]
        row:Show()
        if item.header then
            row.entry = nil
            row.text:SetJustifyH("CENTER")
            row.text:SetText(item.header)
            row.text:SetTextColor(0.95, 0.95, 0.95)
            row.right:SetText("")
        else
            row.entry = item.entry
            local name = GetSpellInfo(item.entry.spell) or "?"
            if #item.entry.ability.ranks > 1 then
                name = string.format("%s %d", name, item.entry.rank)
            end
            if item.tag then
                name = name .. " |cff909090" .. item.tag .. "|r"
            end
            row.text:SetJustifyH("LEFT")
            row.text:SetText(name)
            row.text:SetTextColor(unpack(item.color))
            if item.known then
                row.right:SetText(L["known"])
            else
                local lvl = item.entry.level
                local lvlColor
                if petLevel >= lvl then lvlColor = "|cffffffff"
                elseif playerLevel >= lvl then lvlColor = "|cffff8000"
                else lvlColor = "|cffff2020" end
                row.right:SetText(string.format("%d || %sL%d|r", item.entry.tp, lvlColor, lvl))
            end
            row.right:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    for i = #items + 1, #sideRows do
        sideRows[i]:Hide()
        sideRows[i].entry = nil
    end
    sideContent:SetHeight(math.max(1, #items * PANEL_ROW_HEIGHT))
    sidePanel:Show()
end
ns.RefreshCraftSidePanel = function()
    if sidePanel and sidePanel:IsShown() then RefreshSidePanel(true) end
end
-- options callback: apply the craftPanel setting while the window is open
ns.UpdateCraftSidePanel = function()
    if not ns.db.craftPanel then
        if sidePanel then sidePanel:Hide() end
    elseif CraftFrame and CraftFrame:IsShown() then
        ScanCraft() -- re-detects beast training and shows/refreshes the panel
    end
end

-- ---------------------------------------------------------------- debug

-- /pettips debug (while Beast Training or a trainer is open): dump what
-- the craft/trainer APIs report, to diagnose scan problems.
function ns.TrainerScanDebug()
    local events = {}
    for name, count in pairs(eventLog) do
        events[#events + 1] = name .. " x" .. count
    end
    print(string.format("PetTips debug: events since login: %s",
        #events > 0 and table.concat(events, ", ") or "NONE"))
    print(string.format("PetTips debug: known ranks cached=%d, beastTrainingSynced=%s",
        KnownCount(), tostring(ns.chardb.scannedBeastTraining)))

    if ns.isWarlock then
        local fams = {}
        for id in pairs(ns.chardb.syncedDemonFams or {}) do
            fams[#fams + 1] = ns.DEMON_FAMILIES[id] or tostring(id)
        end
        print(string.format("PetTips debug: warlock - synced demons: %s; current pet family=%s",
            #fams > 0 and table.concat(fams, ", ") or "NONE",
            tostring(UnitCreatureFamily("pet"))))
        ns.SyncCurrentDemonDebug()
        return
    end

    nameToAbility = nil
    local numCrafts = GetNumCrafts and GetNumCrafts() or 0
    print(string.format("PetTips debug: craft window: %d crafts", numCrafts))
    for i = 1, math.min(numCrafts, 100) do
        local name, rankText, craftType, _, _, tp, reqLevel = GetCraftInfo(i)
        local entry = ResolveRank(name, rankText)
        print(string.format("  craft %d: %s | %s | %s | tp=%s | lvl=%s | spell=%s",
            i, tostring(name), tostring(rankText), tostring(craftType),
            tostring(tp), tostring(reqLevel), tostring(entry and entry.spell)))
    end

    local numServices = GetNumTrainerServices() or 0
    print(string.format("PetTips debug: trainer window: %d services", numServices))
    for i = 1, math.min(numServices, 100) do
        local name, rankText, category = GetTrainerServiceInfo(i)
        local cost = GetTrainerServiceCost and GetTrainerServiceCost(i)
        local entry = ResolveRank(name, rankText)
        print(string.format("  service %d: %s | %s | %s | cost=%s | spell=%s",
            i, tostring(name), tostring(rankText), tostring(category),
            tostring(cost), tostring(entry and entry.spell)))
    end

    if numCrafts == 0 and numServices == 0 then
        print("PetTips debug: no window open? Open Beast Training or a pet trainer first.")
    else
        ScanCraft()
        ScanTrainer()
    end
end

-- ------------------------------------------------- warlock demon sync
-- Warlock known-state works differently: a bought grimoire teaches the
-- rank to the demon TYPE, but the client only exposes it while that demon
-- is summoned (IsSpellKnown(spell, true) on the pet spellbook; there is
-- no trainer window - demon trainers are grimoire VENDORS on Era). So
-- whenever a demon is out, its family's ranks are recorded into the same
-- per-character cache the hunter scan uses (chardb.knownTeach), which is
-- what lets the list show the other demons' bought ranks while browsing.
-- chardb.syncedDemonFams[famId] marks families recorded at least once.

local function SyncCurrentDemon()
    local famId = ns.GetPetFamilyId()
    if not famId or not ns.DEMON_FAMILIES[famId] then return end
    local known = ns.chardb.knownTeach
    local changed = false
    for _, ability in ipairs(ns.PET_ABILITIES) do
        if ability.families[famId] then
            for _, r in ipairs(ability.ranks) do
                if not known[r.spell] and IsSpellKnown(r.spell, true) then
                    known[r.spell] = true
                    changed = true
                end
            end
        end
    end
    ns.chardb.syncedDemonFams[famId] = true
    if changed and ns.RefreshTrainingList then ns.RefreshTrainingList() end
end
ns.SyncCurrentDemonDebug = SyncCurrentDemon -- force-run via /pettips debug

-- ------------------------------------------------- grimoire tooltips
-- Known/missing hint on grimoire item tooltips (vendor, bags, links):
-- green when the demon already knows that rank (don't buy it twice!),
-- red when it is still missing, gray when a higher rank makes it moot.

local function RankLabel(entry)
    local name = GetSpellInfo(entry.spell) or ("spell " .. entry.spell)
    if #entry.ability.ranks > 1 then
        return string.format("%s %d", name, entry.rank)
    end
    return name
end

-- How a grimoire relates to what the demon knows: "known" (don't buy it
-- twice), "obsolete" (a higher rank is known) or "missing" (worth buying).
-- Also returns the demon's family name for the tooltip line.
function ns.ClassifyGrimoire(entry)
    local known = ns.chardb.knownTeach
    local curFam = ns.GetPetFamilyId()
    local isCurrent = curFam and entry.ability.families[curFam]
    local function rankKnown(r)
        return known[r.spell] or (isCurrent and IsSpellKnown(r.spell, true))
    end
    local petRank = 0
    for _, r in ipairs(entry.ability.ranks) do
        if rankKnown(r) then petRank = r.rank end
    end
    local famName
    for id in pairs(entry.ability.families) do famName = ns.DEMON_FAMILIES[id] end
    local state
    if rankKnown(entry) then state = "known"
    elseif petRank > entry.rank then state = "obsolete"
    else state = "missing" end
    return state, famName
end

local function HandleGrimoireTooltip(tooltip)
    if not ns.db.grimoireTooltips then return end
    if not tooltip.GetItem then return end
    local _, link = tooltip:GetItem()
    local itemId = link and tonumber(link:match("item:(%d+)"))
    local entry = itemId and ns.GRIMOIRE_BY_ITEM and ns.GRIMOIRE_BY_ITEM[itemId]
    if not entry then return end

    local state, famName = ns.ClassifyGrimoire(entry)
    if state == "known" then
        tooltip:AddLine(string.format(L["PetTips: your %s already knows this."], famName or "?"), 0.4, 0.9, 0.4)
    elseif state == "obsolete" then
        tooltip:AddLine(string.format(L["PetTips: your %s already knows a higher rank."], famName or "?"), 0.6, 0.6, 0.6)
    else
        tooltip:AddLine(string.format(L["PetTips: not yet known by your %s."], famName or "?"), 1, 0.45, 0.35)
    end
end

-- ---------------------------------------------------------------- events

ns.OnLogin(function()
    if ns.playerClass ~= "WARLOCK" then return end
    local watcher = CreateFrame("Frame")
    watcher:RegisterUnitEvent("UNIT_PET", "player")
    watcher:RegisterEvent("SPELLS_CHANGED")
    RegisterLearnedSpell(watcher)
    watcher:SetScript("OnEvent", function(_, event, arg1)
        eventLog[event] = (eventLog[event] or 0) + 1
        if IsLearnedSpellEvent(event) then
            local entry = arg1 and ns.ABILITY_BY_SPELL[arg1]
            if entry and not ns.chardb.knownTeach[arg1] then
                ns.chardb.knownTeach[arg1] = true
                print(string.format(L["PetTips: your demon learned %s (rank %d)."],
                    GetSpellInfo(arg1) or "?", entry.rank))
                if ns.RefreshTrainingList then ns.RefreshTrainingList() end
            end
            return
        end
        SyncCurrentDemon()
    end)
    -- initial sync: pet spell data can lag behind PLAYER_LOGIN
    C_Timer.After(3, SyncCurrentDemon)

    -- both tooltip API paths with a once-per-tooltip guard (same pattern
    -- as ProfessionTips): whichever fires first renders, the other no-ops
    local function OnCleared(tooltip) tooltip.petTipsGrimoireDone = nil end
    GameTooltip:HookScript("OnTooltipCleared", OnCleared)
    ItemRefTooltip:HookScript("OnTooltipCleared", OnCleared)
    local function GuardedHandle(tooltip)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        if tooltip.petTipsGrimoireDone then return end
        tooltip.petTipsGrimoireDone = true
        HandleGrimoireTooltip(tooltip)
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, GuardedHandle)
    end
    pcall(function()
        GameTooltip:HookScript("OnTooltipSetItem", GuardedHandle)
        ItemRefTooltip:HookScript("OnTooltipSetItem", GuardedHandle)
    end)
end)

ns.OnLogin(function()
    if ns.playerClass ~= "HUNTER" then return end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("CRAFT_SHOW")
    watcher:RegisterEvent("CRAFT_UPDATE")
    watcher:RegisterEvent("CRAFT_CLOSE")
    watcher:RegisterEvent("TRAINER_SHOW")
    watcher:RegisterEvent("TRAINER_UPDATE")
    watcher:RegisterEvent("TRAINER_CLOSED")
    RegisterLearnedSpell(watcher)
    watcher:SetScript("OnEvent", function(_, event, arg1)
        eventLog[event] = (eventLog[event] or 0) + 1
        if event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
            ScanCraft()
        elseif event == "CRAFT_CLOSE" then
            announcedCraft = false
        elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
            ScanTrainer()
        elseif event == "TRAINER_CLOSED" then
            announcedTrainer = false
        elseif IsLearnedSpellEvent(event) then
            local entry = arg1 and ns.ABILITY_BY_SPELL[arg1]
            if entry and not ns.chardb.knownTeach[arg1] then
                ns.chardb.knownTeach[arg1] = true
                print(string.format(L["PetTips: learned to teach %s (rank %d)."],
                    GetSpellInfo(arg1) or "?", entry.rank))
                if ns.RefreshTrainingList then ns.RefreshTrainingList() end
                if sidePanel and sidePanel:IsShown() then RefreshSidePanel(true) end
            end
        end
    end)
end)
