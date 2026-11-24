local ADDON_NAME, ns = ...
local L = ns.L
local api = ns.api

-- WoW Forever host of the training list. Forever has the Retail-engine
-- spellbook (PlayerSpellsFrame.SpellBookFrame, load on demand: icon tabs
-- along the top, paged parchment, minimized or maximized). The list docks
-- into it in the style of WhatsTraining's Forever rework (read from its
-- Forever/SpellBook.lua, Widgets.lua, Views.lua on 2026-11-23 - layout and
-- look only, the code is ours):
--  * a look-alike icon tab right of Blizzard's tabs - or hanging below the
--    tab strip like a bookmark when the search box leaves no room - and
--    right of WhatsTraining's own tab when that addon is loaded too
--  * opaque parchment covers painted with the book's own page atlases,
--    one under the toolbar ("attic") and one under the pages, drawn
--    BELOW the window border (frame level = border - 10)
--  * our search box and settings button sit exactly where the book's own
--    are (the attic covers theirs)
--  * per page: the book's own category header (SpellBookHeaderTemplate),
--    a ledger of tinted section bands and 28px icon rows (name | rank |
--    TP or price | level) in the book's ink colors, footer hint + status
--  * maximized book: the ledger flows over both pages, paged with the
--    book's own paging controls (mouse wheel flips)
--
-- HANDS OFF Blizzard's frames (TrainingList.lua history, AGENTS.md "UI"):
-- their spell buttons cast through a protected path, and any field or
-- call an addon writes into the book / its tab system taints it. We only
-- READ their state, anchor our own frames to theirs and post-hook.
--
-- Era/TBC: TrainingList.lua's docked host; this file stays inert there.
if SpellBookFrame and BOOKTYPE_PET and _G["SpellBookSkillLineTab1"] then return end

local FB = {}
ns.ForeverBook = FB

local TL -- ns.TL (TrainingList.lua), picked up at Create

local BEAST_TRAINING_SPELL, SUMMON_IMP_SPELL = 5149, 688
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local SKIN = {
    tab = "spellbook-Tab-Frame-C60",
    tabActive = "spellbook-Tab-Frame-Glow-C60",
    tabGlow = "spellbook-Tab-Frame-glow-gradient-C60",
    pageLeft = "spellbook-Page-Left-C60",
    pageRight = "spellbook-Page-Right-C60", -- also the minimized (single page) art
}
local BAND_TEXTURE = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal-Desaturated"
local BAND_CAP_MASK = "Interface\\AddOns\\PetTips\\Textures\\header-mask"
local BAND_CAP_FRACTION = 8 / 1024

-- geometry (same numbers as WhatsTraining's Forever book)
local HEADER_HEIGHT = 60      -- the page cover starts below the tab strip
local HANGING_TAB_RISE = 4
local TAB_WIDTH = 44
local PAGE_WIDTH, PAGE_TOP, PAGE_BOTTOM = 696, -90, 15 -- fallback until the book has laid out
local PAGE_LEFT, PAGE_RIGHT = 65, 45
local LIST_TOP, LIST_BOTTOM = -68, 46 -- scroll area inside a page
local ROW_HEIGHT = 28
local HEADING_HEIGHT, HEADING_GAP = ROW_HEIGHT + 4, 8
local NOTE_HEIGHT = 26

-- the book's ink-on-parchment palette (WhatsTraining Forever/Theme.lua)
local THEME = {
    backing = { 0.10, 0.07, 0.035 },
    body = { 0.19, 0.12, 0.06 },
    strong = { 0.08, 0.04, 0.02 },
    dim = { 0.4, 0.4, 0.4 },
    available = { 0.10, 0.38, 0.05 },
    nextLevel = { 0.08, 0.22, 0.50 },
    unavailable = { 0.45, 0.09, 0.04 },
    clear = { 0.30, 0.19, 0.08, 0 },
    separator = { 0.30, 0.19, 0.08, 0.18 },
    highlight = { 1, 0.85, 0.50, 0.06 },
    shadow = { 0, 0, 0, 1 },
    -- section band: r, g, b of the band, then r, g, b of its text
    sections = {
        now      = { 0.12, 0.24, 0.08, 0.65, 1, 0.40 },
        fromPet  = { 0.08, 0.18, 0.29, 0.55, 0.84, 1 },
        gated    = { 0.32, 0.15, 0.03, 1, 0.82, 0.30 },
        notKnown = { 0.30, 0.07, 0.04, 1, 0.55, 0.45 },
        known    = { 0.20, 0.17, 0.12, 0.75, 0.75, 0.75 },
    },
}

local book, psf, tabSystem
local root, launcher, attic, returnTab, paging
local pages = {}  -- [1] left (or only) page, [2] right page of the maximized book
local covers = {}
local active, shownTab, openOnShow, queued, expanded = false, nil, false, false, nil
local rendering = false
local wtHooked = false

-- ---------------------------------------------------------------- helpers

local function Color(c, alpha)
    if CreateColor then return CreateColor(c[1], c[2], c[3], alpha or c[4] or 1) end
end

local function Hex(c, text)
    return string.format("|cff%02x%02x%02x%s|r", c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5, text)
end

-- a Blizzard sub-frame / region by key, or nil (read only - never written)
local function Child(frame, key)
    local value = frame and frame[key]
    if type(value) == "table" then return value end
end

local function Gamepad()
    return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false
end

local function Defer(fn)
    if RunNextFrame then RunNextFrame(fn) else C_Timer.After(0, fn) end
end

local function Title()
    return ns.isWarlock and L["Demon Training"] or L["Pet Training"]
end

local function Label(parent, font, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(unpack(color or THEME.body))
    return fs
end

local function HideTooltip(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

-- ---------------------------------------------------------------- tabs

local function MakeTab(name, parent)
    local button = CreateFrame("Button", name, parent)
    button:SetSize(TAB_WIDTH, 32)
    -- a slightly smaller icon stands in for the native tab's icon mask
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(34, 33)
    button.icon:SetPoint("BOTTOM", -1, 0)
    local function FrameArt(atlas, y)
        local texture = button:CreateTexture(nil, "ARTWORK", nil, 1)
        texture:SetAtlas(atlas, true)
        texture:SetPoint("BOTTOM", 0, y)
        return texture
    end
    button.normal = FrameArt(SKIN.tab, 1)
    button.active = FrameArt(SKIN.tabActive, 1)
    button.glow = FrameArt(SKIN.tabGlow, 0)
    -- CheckButton-style state: selected look while the list is open
    function button:SetChecked(checked)
        self.checked = checked and true or false
        self.normal:SetShown(not self.checked)
        self.active:SetShown(self.checked)
        self.glow:SetShown(self.checked)
    end
    function button:GetChecked() return self.checked end
    button:SetChecked(false)
    return button
end

-- bookmark mode: 80% size, art mirrored, hanging from the tab strip
local function InvertTab(button, inverted)
    if button.inverted == inverted then return end
    button.inverted = inverted
    local scale = inverted and 0.8 or 1
    button:SetSize(TAB_WIDTH * scale, 32 * scale)
    local edge = inverted and "TOP" or "BOTTOM"
    button.icon:SetSize(34 * scale, 33 * scale)
    button.icon:ClearAllPoints()
    button.icon:SetPoint(edge, -scale, 0)
    for _, art in ipairs({ { button.normal, SKIN.tab, 1 }, { button.active, SKIN.tabActive, 1 },
        { button.glow, SKIN.tabGlow, 0 } }) do
        local texture, atlas, offset = art[1], art[2], art[3]
        texture:SetAtlas(atlas, true, nil, true)
        local width, height = texture:GetSize()
        if width and height then texture:SetSize(width * scale, height * scale) end
        if inverted and AnchorUtil and AnchorUtil.SetMirroredTexCoordAlongVerticalAxis then
            AnchorUtil.SetMirroredTexCoordAlongVerticalAxis(texture, texture:GetTexCoord())
        end
        texture:ClearAllPoints()
        texture:SetPoint(edge, 0, (inverted and -offset or offset) * scale)
    end
end

-- Blizzard's currently selected category tab (read only)
local function SelectedNativeTab()
    local id = tabSystem.selectedTabID
    local button = id and tabSystem.GetTabButton and tabSystem:GetTabButton(id)
    if button then return button end
    if type(tabSystem.tabs) == "table" then
        for _, t in ipairs(tabSystem.tabs) do
            if t.isSelected and t:IsShown() then return t end
        end
    end
end

-- ---------------------------------------------------------------- covers

local OnWheel -- forward

-- opaque, mouse-eating rectangle painted with the book's own page art
-- (anchored to the whole book and clipped to the cover, so it lines up
-- with the real page underneath)
local function Cover()
    local frame = CreateFrame("Frame", nil, root)
    frame:SetFrameLevel(root:GetFrameLevel())
    frame:SetClipsChildren(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) OnWheel(delta) end)
    frame.backing = frame:CreateTexture(nil, "BACKGROUND")
    frame.backing:SetAllPoints()
    frame.backing:SetColorTexture(THEME.backing[1], THEME.backing[2], THEME.backing[3], 1)
    frame.art = CreateFrame("Frame", nil, frame)
    frame.art:SetAllPoints(frame)
    frame.art:SetClipsChildren(true)
    frame.art:SetFrameLevel(frame:GetFrameLevel() + 1)
    local function Page(atlas, from, to)
        local texture = frame.art:CreateTexture(nil, "BACKGROUND")
        texture:SetAtlas(atlas)
        texture:SetPoint("TOPLEFT", root, from)
        texture:SetPoint("BOTTOMRIGHT", root, to)
        return texture
    end
    frame.whole = Page(SKIN.pageRight, "TOPLEFT", "BOTTOMRIGHT")
    frame.left = Page(SKIN.pageLeft, "TOPLEFT", "BOTTOM")
    frame.right = Page(SKIN.pageRight, "TOP", "BOTTOMRIGHT")
    covers[#covers + 1] = frame
    return frame
end

-- ---------------------------------------------------------------- page widgets

-- fixed-shape frames, one pool per kind: a refresh only fills them in
local function Pool(page, create)
    local pool, used = {}, 0
    function pool:Acquire()
        used = used + 1
        local frame = self[used] or create()
        self[used] = frame
        if frame.Resize then frame:Resize() end
        frame:Show()
        return frame
    end
    function pool:ReleaseAll()
        for _, frame in ipairs(self) do
            frame.item = nil
            frame:Hide()
        end
        used = 0
    end
    page.pools[#page.pools + 1] = pool
    return pool
end

-- right-hand columns, measured from the list's right edge
local function Columns(width)
    return width - 262, width - 180, width - 100 -- rank, cost (TP / price), level
end

local function CreateRow(page)
    local parent = page.content
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 8, -2)
    row.icon:SetSize(24, 24)
    row.iconBorder = row:CreateTexture(nil, "OVERLAY")
    row.iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    row.iconBorder:SetPoint("CENTER", row.icon, "CENTER")
    row.iconBorder:SetSize(40, 40)
    row.name = Label(row, "SystemFont_Med3")
    row.name:SetWordWrap(false)
    row.rank = Label(row, "SystemFont_Med3")
    row.rank:SetWordWrap(false)
    row.cost = Label(row, "SystemFont_Med3")
    row.cost:SetWordWrap(false)
    row.level = Label(row, "SystemFont_Med3")
    row.level:SetWordWrap(false)
    function row:Resize()
        local width = parent:GetWidth()
        local rankX, costX, levelX = Columns(width)
        self:SetWidth(width)
        self.name:SetPoint("TOPLEFT", self, "TOPLEFT", 38, -6)
        self.name:SetWidth(rankX - 46)
        self.rank:SetPoint("TOPLEFT", self, "TOPLEFT", rankX, -6)
        self.rank:SetWidth(costX - rankX - 8)
        self.cost:SetPoint("TOPLEFT", self, "TOPLEFT", costX, -6)
        self.cost:SetWidth(levelX - costX - 8)
        self.level:SetPoint("TOPLEFT", self, "TOPLEFT", levelX, -6)
        self.level:SetWidth(width - levelX - 8)
    end

    -- faint ink line between rows: two 1px gradients
    row.separator = CreateFrame("Frame", nil, row)
    row.separator:SetPoint("BOTTOMLEFT", 38, 0)
    row.separator:SetPoint("BOTTOMRIGHT", -8, 0)
    row.separator:SetHeight(2)
    for i = 1, 2 do
        local half = row.separator:CreateTexture(nil, "BACKGROUND")
        half:SetPoint("BOTTOMLEFT", 0, i - 1)
        half:SetPoint("BOTTOMRIGHT", 0, i - 1)
        half:SetHeight(1)
        half:SetColorTexture(1, 1, 1, 1)
        local from, to = Color(THEME.clear), Color(THEME.separator)
        if from and to then
            half:SetGradient("VERTICAL", i == 1 and from or to, i == 1 and to or from)
        end
    end
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(unpack(THEME.highlight))
    row:SetHighlightTexture(highlight)

    row:SetScript("OnEnter", function(self)
        if self.item and self.item.entry then ns.ShowRankTooltip(self.item.entry, self) end
    end)
    row:SetScript("OnLeave", HideTooltip)
    row:SetScript("OnHide", HideTooltip)
    return row
end

-- section band: achievement parchment tinted with the section color,
-- fading out to the right, with a rounded left cap
local function CreateHeading(page)
    local parent = page.content
    local heading = CreateFrame("Frame", nil, parent)
    heading:SetHeight(ROW_HEIGHT)
    heading.band = heading:CreateTexture(nil, "BACKGROUND")
    heading.band:SetTexture(BAND_TEXTURE)
    heading.band:SetTexCoord(BAND_CAP_FRACTION, 1, 0, 1)
    heading.band:SetPoint("TOPRIGHT")
    heading.band:SetHeight(ROW_HEIGHT)
    heading.cap = heading:CreateTexture(nil, "BACKGROUND")
    heading.cap:SetTexture(BAND_TEXTURE)
    heading.cap:SetTexCoord(0, BAND_CAP_FRACTION, 0, 1)
    heading.cap:SetPoint("TOPLEFT")
    heading.cap:SetHeight(ROW_HEIGHT)
    local mask = heading.CreateMaskTexture and heading:CreateMaskTexture()
    if mask then
        mask:SetAllPoints(heading.cap)
        mask:SetTexture(BAND_CAP_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        heading.cap:AddMaskTexture(mask)
    end
    heading.text = Label(heading, "SystemFont_Med3")
    heading.text:SetPoint("TOPLEFT", 8, 0)
    heading.text:SetPoint("BOTTOMRIGHT", -8, 0)
    heading.text:SetJustifyV("MIDDLE")
    heading.text:SetShadowColor(unpack(THEME.shadow))
    heading.text:SetShadowOffset(1, -1)
    function heading:Resize()
        local width = parent:GetWidth()
        local capWidth = width * BAND_CAP_FRACTION
        self:SetWidth(width)
        self.cap:SetWidth(capWidth)
        self.band:SetPoint("TOPLEFT", self, "TOPLEFT", capWidth, 0)
    end
    function heading:Paint(c)
        local capAlpha = 0.75 - 0.75 * BAND_CAP_FRACTION
        local from, mid, to = Color(c, 0.75), Color(c, capAlpha), Color(c, 0)
        if from and mid and to then
            self.cap:SetGradient("HORIZONTAL", from, mid)
            self.band:SetGradient("HORIZONTAL", mid, to)
        end
        self.text:SetTextColor(c[4], c[5], c[6])
    end
    return heading
end

-- hint lines above the list ("Open Beast Training once ...")
local function CreateNote(page)
    local parent = page.content
    local note = CreateFrame("Button", nil, parent)
    note:SetHeight(NOTE_HEIGHT)
    note.text = Label(note, "SystemFont_Med3")
    note.text:SetPoint("LEFT", 8, 0)
    note.text:SetPoint("RIGHT", -8, 0)
    note.text:SetWordWrap(false)
    note.highlight = note:CreateTexture(nil, "HIGHLIGHT")
    note.highlight:SetAllPoints()
    note.highlight:SetColorTexture(unpack(THEME.highlight))
    function note:Resize() self:SetWidth(parent:GetWidth()) end
    note:SetScript("OnClick", function(self)
        if self.item and self.item.beastSync and ns.ShowBeastSyncPopup then ns.ShowBeastSyncPopup() end
    end)
    return note
end

-- one book page: header, scrolling list, footer
local function CreatePage(page, headerX)
    page.pools = {}
    local header = CreateFrame("Frame", nil, page, "SpellBookHeaderTemplate")
    header:SetWidth(680)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", page, "TOPLEFT", headerX, -5)
    page.header = header
    page.title = Child(header, "Text") or Label(header, "SystemFont_Huge2")
    page.backplate = Child(header, "Backplate")

    page.footer = Label(page, "GameFontNormal")
    page.footer:SetPoint("LEFT", page, "BOTTOMLEFT", 8, 31)
    page.footer:SetWordWrap(false)

    local scroll = CreateFrame("ScrollFrame", nil, page, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, LIST_BOTTOM)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PAGE_WIDTH - 20, 1)
    scroll:SetScrollChild(content)
    page.scroll, page.content = scroll, content

    page.headings = Pool(page, function() return CreateHeading(page) end)
    page.rows = Pool(page, function() return CreateRow(page) end)
    page.notes = Pool(page, function() return CreateNote(page) end)
end

local function ResizePage(page, viewWidth)
    page:SetWidth(viewWidth + 16)
    page.header:SetWidth(viewWidth)
    page.content:SetWidth(viewWidth - 4)
    page.footer:SetWidth(viewWidth - 12 - (page.status and 180 or 0))
end

local function FitBackplate(page)
    if not page.backplate then return end
    local width = page.title:GetStringWidth() or 0
    page.backplate:SetWidth(math.min((page.header:GetWidth() or 0) + 85, math.max(416, width * 2.5)))
end

-- ---------------------------------------------------------------- ledger

local function Columns_Text(item)
    local entry, key = item.entry, item.key
    local rank = #entry.ability.ranks > 1 and string.format(L["Rank %d"], entry.rank) or ""
    if key == "known" then
        return rank, "", THEME.dim, L["known"], THEME.dim
    end
    local playerLevel = UnitLevel("player") or 0
    if ns.isWarlock then
        local cost, costColor = L["auto"], THEME.body
        if entry.src == "g" then
            cost = api.GetCoinTextureString(entry.money or 0)
            costColor = GetMoney() >= (entry.money or 0) and THEME.body or THEME.unavailable
        end
        local levelColor = playerLevel >= entry.level and THEME.available or THEME.unavailable
        return rank, cost, costColor, string.format(L["Level %d"], entry.level), levelColor
    end
    -- browsing another family: no pet level / points to compare against
    local _, browsing = TL.EffectiveFamily()
    local petLevel = browsing and 0 or (UnitLevel("pet") or 0)
    local costColor = THEME.body
    if not browsing then
        local totalTP, spentTP = api.GetPetTrainingPoints()
        if (totalTP or 0) - (spentTP or 0) < entry.tp then costColor = THEME.unavailable end
    end
    -- green: the pet meets it; blue: only the hunter (the pet catches up);
    -- red: not even the hunter
    local levelColor = THEME.unavailable
    if petLevel >= entry.level then
        levelColor = THEME.available
    elseif playerLevel >= entry.level then
        levelColor = THEME.nextLevel
    end
    return rank, string.format(L["%d TP"], entry.tp), costColor,
        string.format(L["Level %d"], entry.level), levelColor
end

local function HeadingText(item)
    return item.label or string.format("%s • %d", item.text, item.count or 0)
end

-- draws items into a page's scroll content, returns the content height
local function Render(page, items)
    for _, pool in ipairs(page.pools) do pool:ReleaseAll() end
    local content, y = page.content, 0
    for i, item in ipairs(items) do
        if item.kind == "header" then
            if i > 1 then y = y + HEADING_GAP end
            local heading = page.headings:Acquire()
            heading.item = item
            heading:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            heading:Paint(THEME.sections[item.key] or THEME.sections.known)
            heading.text:SetText(HeadingText(item))
            y = y + HEADING_HEIGHT
        elseif item.kind == "rank" then
            local row = page.rows:Acquire()
            row.item = item
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            local entry = item.entry
            row.icon:SetTexture(api.GetSpellIcon(entry.spell) or QUESTION_MARK)
            local name = TL.RankName(entry)
            if item.tag then name = name .. "  " .. Hex(THEME.dim, item.tag) end
            row.name:SetText(name)
            row.name:SetTextColor(unpack(item.key == "known" and THEME.dim or THEME.body))
            local rank, cost, costColor, level, levelColor = Columns_Text(item)
            row.rank:SetText(rank)
            row.rank:SetTextColor(unpack(item.key == "known" and THEME.dim or THEME.body))
            row.cost:SetText(cost)
            row.cost:SetTextColor(unpack(costColor))
            row.level:SetText(level)
            row.level:SetTextColor(unpack(levelColor))
            local nextItem = items[i + 1]
            row.separator:SetShown(nextItem ~= nil and nextItem.kind == "rank")
            y = y + ROW_HEIGHT
        else
            local note = page.notes:Acquire()
            note.item = item
            note:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            note.text:SetText(item.text or "")
            note.text:SetTextColor(unpack(item.beastSync and THEME.nextLevel or THEME.body))
            note:EnableMouse(item.beastSync and true or false)
            y = y + NOTE_HEIGHT
        end
    end
    content:SetHeight(math.max(1, y))
    return y
end

-- maximized book: split the ledger into page halves of `height` px; a
-- section cut in two repeats its band as "<name> • continued"
local function Paginate(items, height)
    local halves, half, y, section = {}, {}, 0, nil
    for _, item in ipairs(items) do
        local gap, span = 0, ROW_HEIGHT
        if item.kind == "header" then
            gap, span = (#half > 0) and HEADING_GAP or 0, HEADING_HEIGHT
        elseif item.kind == "note" then
            span = NOTE_HEIGHT
        end
        -- a band needs room for itself and one row
        local needed = item.kind == "header" and span + ROW_HEIGHT or span
        if #half > 0 and y + gap + needed > height then
            halves[#halves + 1] = half
            half, y, gap = {}, 0, 0
            if item.kind == "rank" and section then
                half[1] = setmetatable({ label = section.text .. " • " .. L["continued"] }, { __index = section })
                y = HEADING_HEIGHT
            end
        end
        if item.kind == "header" then section = item end
        half[#half + 1] = item
        y = y + gap + span
    end
    halves[#halves + 1] = half
    return halves
end

local function ListHeight(page)
    local height = page.scroll:GetHeight()
    if not height or height <= 0 then height = (page:GetHeight() or 0) + LIST_TOP - LIST_BOTTOM end
    return math.max(height, HEADING_HEIGHT + ROW_HEIGHT * 4)
end

local function SetPaged(page, paged)
    local scroll = page.scroll
    local bar = Child(scroll, "ScrollBar")
    if bar then bar:SetShown(not paged) end
    scroll:EnableMouseWheel(not paged)
    if paged then scroll:SetVerticalScroll(0) end
end

local function Draw()
    local items = TL.BuildDisplayList()
    local main, second = pages[1], pages[2]
    main.title:SetText(Title())
    FitBackplate(main)
    main.family:SetText(string.format("%s %s", L["Family:"], TL.FamilyLabel()))
    main.status:SetText(TL.StatusText())

    if not expanded then
        second:Hide()
        SetPaged(main, false)
        local height = Render(main, items)
        local scroll = main.scroll
        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
        local maxScroll = math.max(0, height - (scroll:GetHeight() or 0))
        if (scroll:GetVerticalScroll() or 0) > maxScroll then scroll:SetVerticalScroll(maxScroll) end
        return
    end

    second:Show()
    second.title:SetText(string.format("%s • %s", Title(), L["continued"]))
    FitBackplate(second)
    SetPaged(main, true)
    SetPaged(second, true)
    local halves = Paginate(items, ListHeight(main))
    local spreads = math.max(1, math.ceil(#halves / 2))
    paging:SetMaxPages(spreads)
    local spread = math.min(math.max(paging:GetCurrentPage() or 1, 1), spreads)
    Render(main, halves[spread * 2 - 1] or {})
    Render(second, halves[spread * 2] or {})
    paging:SetShown(spreads > 1)
end

-- `rendering` also swallows the OnPageChanged the paging controls fire
-- while we set them up; an error must not leave it stuck
function FB.Refresh()
    if rendering or not (root and root:IsShown()) then return end
    rendering = true
    local ok, err = pcall(Draw)
    rendering = false
    if not ok then
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(err) else error(err) end
    end
end

function OnWheel(delta)
    if expanded then
        if paging.OnMouseWheel then
            paging:OnMouseWheel(delta)
        elseif paging.SetCurrentPage then
            paging:SetCurrentPage((paging:GetCurrentPage() or 1) + (delta > 0 and -1 or 1))
        end
        return
    end
    local scroll = pages[1].scroll
    local handler = scroll:GetScript("OnMouseWheel")
    if handler then handler(scroll, delta) end
end

-- ---------------------------------------------------------------- toolbar

local function SortedAbilities()
    local list = {}
    for _, ability in ipairs(ns.PET_ABILITIES) do list[#list + 1] = ability end
    table.sort(list, function(a, b)
        return (api.GetSpellName(a.ranks[1].spell) or a.key) < (api.GetSpellName(b.ranks[1].spell) or b.key)
    end)
    return list
end

local function Changed()
    if pages[1] then pages[1].scroll:SetVerticalScroll(0) end
    if paging and paging.SetCurrentPage then
        rendering = true
        paging:SetCurrentPage(1)
        rendering = false
    end
    FB.Refresh()
end

-- the settings button's menu: what the Era list has as buttons and the
-- ability-filter popup
local function SettingsMenu(_, rootDescription)
    if not ns.isWarlock then
        local filter = TL.sourceFilter
        rootDescription:CreateTitle(L["Sources"])
        rootDescription:CreateCheckbox(L["Taming"], function() return filter.taming end,
            function() filter.taming = not filter.taming; Changed() end)
        rootDescription:CreateCheckbox(L["Trainer"], function() return filter.trainer end,
            function() filter.trainer = not filter.trainer; Changed() end)
        rootDescription:CreateDivider()
    end
    rootDescription:CreateCheckbox(L["Known by pet"], function() return ns.db.showKnownByPet end,
        function() ns.db.showKnownByPet = not ns.db.showKnownByPet; Changed() end)
    local shown = rootDescription:CreateButton(L["Shown abilities"])
    for _, ability in ipairs(SortedAbilities()) do
        shown:CreateCheckbox(api.GetSpellName(ability.ranks[1].spell) or ability.key,
            function(key) return not ns.db.hiddenAbilities[key] end,
            function(key)
                ns.db.hiddenAbilities[key] = (not ns.db.hiddenAbilities[key]) or nil
                Changed()
                if ns.RefreshCraftSidePanel then ns.RefreshCraftSidePanel() end
            end, ability.key)
    end
end

local function OpenMenu(owner, generator)
    if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(owner, generator) end
end

local function CreateToolbar(main)
    -- settings: same art as the book's own settings button
    local settings = CreateFrame("Button", nil, main)
    main.settings = settings
    settings:SetSize(15, 16)
    local normal = settings:CreateTexture(nil, "ARTWORK")
    normal:SetAtlas("common-dropdown-a-button", true)
    normal:SetPoint("CENTER")
    settings:SetNormalTexture(normal)
    local pushed = settings:CreateTexture(nil, "ARTWORK")
    pushed:SetAtlas("common-dropdown-a-button-pressed", true)
    pushed:SetPoint("CENTER")
    settings:SetPushedTexture(pushed)
    local hover = settings:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAtlas("common-dropdown-a-button", true)
    hover:SetPoint("CENTER")
    hover:SetAlpha(0.4)
    settings:SetHighlightTexture(hover, "ADD")
    settings:SetScript("OnClick", function(self) OpenMenu(self, SettingsMenu) end)

    local search = CreateFrame("EditBox", "PetTipsBookSearchBox", main, "SearchBoxTemplate")
    main.search = search
    search:SetSize(300, 30)
    search:SetAutoFocus(false)
    search:HookScript("OnHide", function(self) self:ClearFocus() end)
    search:HookScript("OnTextChanged", function(self)
        if TL.SetSearch(self:GetText()) then Changed() end
    end)

    -- header right: the family selector, WhatsTraining's "total ▾" spot
    local family = CreateFrame("Button", nil, main)
    local arrow = family:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    arrow:SetSize(16, 16)
    local border = Child(main.header, "Border")
    -- the 16px glyph occupies its top half
    arrow:SetPoint("TOPRIGHT", border or main.header, "TOPRIGHT", 0, border and 15 or -8)
    main.family = Label(family, "SystemFont_Med3")
    main.family:SetPoint("RIGHT", arrow, "LEFT", -2, -4)
    main.family:SetJustifyH("RIGHT")
    family:SetPoint("TOPLEFT", main.family, "TOPLEFT", -4, 4)
    family:SetPoint("BOTTOMRIGHT", arrow, "BOTTOMRIGHT", 0, -4)
    local glow = family:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(THEME.highlight[1], THEME.highlight[2], THEME.highlight[3], 0.25)
    family:SetScript("OnClick", function(self) OpenMenu(self, TL.FamilyMenu) end)
    family:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Pet family"], 1, 1, 1)
        GameTooltip:Show()
    end)
    family:SetScript("OnLeave", HideTooltip)

    -- footer right: TP unspent / grimoires to buy
    main.status = Label(main, "SystemFont_Med3", THEME.strong)
    main.status:SetPoint("RIGHT", main, "BOTTOMRIGHT", -24, 31)
    main.status:SetJustifyH("RIGHT")
end

-- our search box / settings button go exactly where the book's own are
local function PlaceToolbar()
    local main = pages[1]
    main.settings:ClearAllPoints()
    main.search:ClearAllPoints()
    local nativeSettings, nativeSearch = Child(book, "SettingsDropdown"), Child(book, "SearchBox")
    if nativeSettings then
        main.settings:SetAllPoints(nativeSettings)
    else
        main.settings:SetPoint("TOPRIGHT", root, "TOPRIGHT", -30, -27)
    end
    if nativeSearch then
        main.search:SetAllPoints(nativeSearch)
    else
        main.search:SetPoint("RIGHT", main.settings, "LEFT", -5, 4)
    end
end

-- ---------------------------------------------------------------- WhatsTraining

-- WhatsTraining (Forever rework) puts its own look-alike tab 8px right of
-- Blizzard's tabs and the same kind of cover over the book. Only one list
-- may be open: opening ours closes theirs through their own tab, and
-- their tab opening closes ours.
local function WhatsTraining()
    local wtLauncher, wtRoot = _G.WhatsTrainingLauncher, _G.WhatsTrainingOverlay
    if wtLauncher and wtRoot and wtLauncher ~= launcher then return wtLauncher, wtRoot end
end

local Sync, Request -- forward

local function HookWhatsTraining()
    if wtHooked then return end
    local wtLauncher, wtRoot = WhatsTraining()
    if not wtLauncher then return end
    wtHooked = true
    wtLauncher:HookScript("OnClick", function()
        if active and wtRoot:IsShown() then
            active = false
            Sync()
        end
    end)
    -- their tab is placed in THEIR (deferred) sync, often after ours ran:
    -- follow every move / show so ours never sits on it (seen 2026-11-23)
    wtLauncher:HookScript("OnShow", function() Request() end)
    hooksecurefunc(wtLauncher, "SetPoint", function() Request() end)
end

-- frame edges in screen pixels: the tabs, the search box and the two
-- launchers do not share one effective scale
local function ScreenEdge(frame, edge)
    if not frame then return end
    local value = edge == "LEFT" and frame:GetLeft() or frame:GetRight()
    local scale = frame:GetEffectiveScale()
    if value and scale then return value * scale end
end

local function CloseWhatsTraining()
    local wtLauncher, wtRoot = WhatsTraining()
    if wtLauncher and wtRoot:IsShown() and wtLauncher.Click then wtLauncher:Click() end
end

-- right of Blizzard's tabs (or of WhatsTraining's), or hanging below the
-- strip like a bookmark when the native search box leaves no room. Room
-- rule = WhatsTraining's: gap + one tab up to the search box, no margin.
local function PlaceLauncher()
    local wtLauncher = WhatsTraining()
    local wtShown = wtLauncher and wtLauncher:IsShown() and wtLauncher:GetRight() ~= nil
    local wtBookmark = wtShown and wtLauncher.bookmark or false
    local anchor, gap = tabSystem, 8
    -- flush against WhatsTraining's tab: the narrow book has barely one
    -- tab of room left there (user's choice 2026-11-23: gap 0)
    if wtShown and not wtBookmark then anchor, gap = wtLauncher, 0 end
    local ownScale = launcher:GetEffectiveScale() or 1
    local searchLeft = ScreenEdge(Child(book, "SearchBox"), "LEFT")
    local anchorRight = ScreenEdge(anchor, "RIGHT")
    local bookmark = wtBookmark
        or (searchLeft and anchorRight and searchLeft - anchorRight < (gap + TAB_WIDTH) * ownScale) or false
    launcher:ClearAllPoints()
    if wtBookmark then
        launcher:SetPoint("TOPLEFT", wtLauncher, "TOPRIGHT", 2, 0)
    elseif bookmark then
        -- hang from the strip, but RIGHT of WhatsTraining's tab when that
        -- one still fits beside the strip - never underneath it
        local x = 8
        local wtRight, tabsRight = ScreenEdge(wtShown and wtLauncher, "RIGHT"), ScreenEdge(tabSystem, "RIGHT")
        if wtRight and tabsRight then x = (wtRight - tabsRight) / ownScale + 2 end
        launcher:SetPoint("TOPLEFT", tabSystem, "BOTTOMRIGHT", x, HANGING_TAB_RISE)
    else
        launcher:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
    end
    InvertTab(launcher, bookmark)
    attic:ClearAllPoints()
    attic:SetPoint("TOP", root, "TOP")
    attic:SetPoint("BOTTOM", root, "TOP", 0, -HEADER_HEIGHT)
    attic:SetPoint("RIGHT", root, "RIGHT")
    attic:SetPoint("LEFT", bookmark and tabSystem or launcher, "RIGHT")
end

-- ---------------------------------------------------------------- sync

-- page width follows the book's own spell view
local function SizePages()
    local views = Child(Child(book, "PagedSpellsFrame"), "ViewFrames")
    local view = views and Child(views, 1)
    local width = view and view:GetWidth()
    if not width or width <= 0 then width = PAGE_WIDTH - 16 end
    if math.abs((pages[1]:GetWidth() or 0) - (width + 16)) < 0.01 then return false end
    for _, page in ipairs(pages) do ResizePage(page, width) end
    return true
end

local function Open()
    CloseWhatsTraining()
    active = true
    shownTab = tabSystem.selectedTabID
    expanded = nil -- fresh layout: scroll to the top, first spread
    PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
end

function Sync()
    if not root then return end
    local enabled = ns.db.enableList and not Gamepad()
    if not enabled or not book:IsVisible() then active = false end
    local current = tabSystem.selectedTabID
    if active and current and shownTab and current ~= shownTab then active = false end
    launcher:SetChecked(active)
    if not enabled or not book:IsVisible() then
        root:Hide()
        returnTab:Hide()
        launcher:Hide()
        return
    end

    local bookScale, frameScale = book:GetEffectiveScale(), psf:GetEffectiveScale()
    local scale = (bookScale and frameScale and frameScale > 0) and bookScale / frameScale or 1
    local strata = psf:GetFrameStrata()
    -- below the window border, like WhatsTraining's cover
    local border = Child(psf, "NineSlice")
    local level = border and (border:GetFrameLevel() - 10) or ((book:GetFrameLevel() or 1) + 50)
    for _, frame in ipairs({ root, launcher }) do
        frame:SetScale(scale)
        if strata then frame:SetFrameStrata(strata) end
        frame:SetFrameLevel(level)
    end
    launcher:SetFrameLevel(level + 6)
    returnTab:SetFrameLevel(level + 5)
    pages[1]:SetFrameLevel(level + 2)

    HookWhatsTraining()
    PlaceLauncher()
    launcher:Show()
    if not active then
        root:Hide()
        returnTab:Hide()
        return
    end

    local isExpanded = not book.isMinimized
    local resized = SizePages()
    if expanded ~= isExpanded or resized then
        expanded = isExpanded
        pages[1].scroll:SetVerticalScroll(0)
        if paging.SetCurrentPage then
            rendering = true
            paging:SetCurrentPage(1)
            rendering = false
        end
    end
    for _, frame in ipairs(covers) do
        frame.whole:SetShown(not expanded)
        frame.left:SetShown(expanded)
        frame.right:SetShown(expanded)
    end
    -- their selected tab would keep glowing next to ours: a look-alike in
    -- the unselected state sits on it (click = back to that page)
    local native = SelectedNativeTab()
    if native then
        returnTab:ClearAllPoints()
        returnTab:SetPoint("CENTER", native)
        local icon = Child(native, "Icon")
        returnTab.icon:SetTexture((icon and icon:GetTexture()) or native.tabIcon)
        returnTab.tooltip = native.tooltipText
        returnTab:Show()
    else
        returnTab:Hide()
    end
    PlaceToolbar()
    root:Show()
    FB.Refresh()
end

-- deferred: lets the book finish its own layout first
function Request()
    if queued then return end
    queued = true
    Defer(function()
        queued = false
        Sync()
    end)
end

-- ---------------------------------------------------------------- API

function FB.Create(nativeBook)
    if root then return end
    TL = ns.TL
    book, psf, tabSystem = nativeBook, PlayerSpellsFrame, nativeBook.CategoryTabSystem

    root = CreateFrame("Frame", "PetTipsTrainingFrame", psf)
    root:Hide()
    root:SetAllPoints(book)

    local content = Cover()
    content:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -HEADER_HEIGHT)
    content:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT")
    attic = Cover() -- the toolbar right of the tabs, placed by PlaceLauncher

    launcher = MakeTab("PetTipsSpellbookTab", psf)
    launcher:Hide()
    launcher.icon:SetTexture(api.GetSpellIcon(ns.isWarlock and SUMMON_IMP_SPELL or BEAST_TRAINING_SPELL)
        or QUESTION_MARK)
    launcher:SetScript("OnClick", function()
        if active then active = false else Open() end
        Sync()
    end)
    launcher:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Title(), 1, 1, 1)
        GameTooltip:Show()
    end)
    launcher:SetScript("OnLeave", HideTooltip)
    launcher:SetScript("OnHide", HideTooltip)
    launcher:RegisterEvent("UI_SCALE_CHANGED")
    launcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    launcher:SetScript("OnEvent", Request)

    returnTab = MakeTab(nil, root)
    root.returnTab = returnTab
    returnTab:Hide()
    Cover():SetAllPoints(returnTab)
    returnTab:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
        active = false
        Sync()
    end)
    returnTab:SetScript("OnEnter", function(self)
        if not self.tooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltip, 1, 1, 1)
        GameTooltip:Show()
    end)
    returnTab:SetScript("OnLeave", HideTooltip)

    local main = CreateFrame("Frame", nil, root)
    main:SetPoint("TOPLEFT", root, "TOPLEFT", PAGE_LEFT, PAGE_TOP)
    main:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", PAGE_LEFT, PAGE_BOTTOM)
    main:SetWidth(PAGE_WIDTH)
    CreatePage(main, 20)
    main.footer:SetText(L["Hover a row for its sources and costs."])
    CreateToolbar(main)
    pages[1] = main

    local second = CreateFrame("Frame", nil, main)
    second:SetPoint("TOPRIGHT", root, "TOPRIGHT", -PAGE_RIGHT, PAGE_TOP)
    second:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -PAGE_RIGHT, PAGE_BOTTOM)
    second:SetWidth(PAGE_WIDTH)
    CreatePage(second, 11)
    second:Hide()
    pages[2] = second
    ResizePage(main, PAGE_WIDTH - 16)
    ResizePage(second, PAGE_WIDTH - 16)

    -- the book's own page flipper, bottom right of the right page
    paging = CreateFrame("Frame", nil, second, "PagingControlsHorizontalTemplate")
    paging:ClearAllPoints()
    paging:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -75, 40)
    local pageText = Child(paging, "PageText")
    if pageText then
        pageText:SetFontObject("SystemFont_Med3")
        pageText:SetTextColor(unpack(THEME.body))
    end
    paging.spacing = 8
    paging.prevPageSound, paging.nextPageSound = SOUNDKIT.IG_ABILITY_PAGE_TURN, SOUNDKIT.IG_ABILITY_PAGE_TURN
    function second:OnPageChanged() FB.Refresh() end

    root:SetScript("OnShow", function(self)
        self:RegisterEvent("SPELLS_CHANGED")
        self:RegisterUnitEvent("UNIT_PET", "player")
        self:RegisterEvent("PET_BAR_UPDATE")
        if ns.isWarlock then self:RegisterEvent("PLAYER_MONEY") end
        TL.MaybeShowSyncPopup(self)
    end)
    root:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        TL.HideSyncPopup()
        TL.ResetFamily()
    end)
    root:SetScript("OnEvent", function(_, event)
        if event == "UNIT_PET" then TL.ResetFamily() end
        FB.Refresh()
    end)

    -- following the book without touching it: post-hooks only
    hooksecurefunc(tabSystem, "SetTabVisuallySelected", function(_, tabID)
        -- fires on every spell data refresh too: only a CHANGED tab is the
        -- player asking for another page
        if active and tabID ~= shownTab then active = false end
        Sync()
    end)
    book:HookScript("OnShow", function()
        if openOnShow then
            openOnShow = false
            Open()
        end
        Sync()
        Request()
    end)
    book:HookScript("OnHide", function()
        -- reopening the book shows THEIR page again
        active = false
        Sync()
    end)
    -- minimize / maximize, UI scale
    book:HookScript("OnSizeChanged", Request)
    if book:IsVisible() then Sync() end
end

-- options toggle
function FB.UpdateTab()
    if root then Sync() end
end

-- /pettips show: open the list, or arm it for the next time the book
-- opens - the addon never opens the book itself (a tainted open = dead
-- spell buttons)
function FB.ShowList()
    if root and book:IsVisible() then
        if not active then Open() end
        Sync()
    else
        openOnShow = true
        print(L["PetTips: open your spellbook - the list opens on the PetTips tab, next to the spellbook's own tabs."])
    end
    return true
end

-- headless tests (tests/test_forever.lua) look inside
FB._test = { pages = pages, Paginate = Paginate }
