-- Minimal-but-live WoW API mock set for headless tests. Returns a builder
-- so every boot gets a fresh, isolated environment.
--
-- Unlike a pure no-op stub set, frames here KEEP their registered events
-- and scripts, so tests can drive the addon the way the game does:
--   M.Fire("CRAFT_SHOW")            -- dispatch to every registered frame
--   M.FireHooks(M.GameTooltip, "OnTooltipSetItem", M.GameTooltip)
--   M.FlushTimers()                 -- run queued C_Timer.After callbacks
-- All game state the addon reads lives in M.state (class, pet family,
-- levels, TP, money, known spells, craft/trainer windows, map info) -
-- tests mutate it and call the addon's functions.

local function newFontString()
    local fs = { __text = "" }
    return setmetatable(fs, { __index = function(_, k)
        if k == "SetText" then return function(self, t) self.__text = t or "" end end
        if k == "GetText" then return function(self) return self.__text end end
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end })
end

local M -- forward (frames need the registry)

local frameMethods = {}
function frameMethods.RegisterEvent(self, e)
    -- The TBC Anniversary client (newer engine than Era 1.15) removed the
    -- old LEARNED_SPELL_IN_TAB event name and RegisterEvent THROWS on it
    -- (seen in game 2026-07-21). Mirror that in TBC boots so the addon's
    -- fallback to LEARNED_SPELL_IN_SKILL_LINE is really exercised.
    if e == "LEARNED_SPELL_IN_TAB" and M.WOW_PROJECT_ID == 5 then
        error('Frame:RegisterEvent(): Attempt to register unknown event "' .. e .. '"')
    end
    self.__events[e] = true
end
function frameMethods.RegisterUnitEvent(self, e) self.__events[e] = true end
function frameMethods.UnregisterEvent(self, e) self.__events[e] = nil end
function frameMethods.UnregisterAllEvents(self) self.__events = {} end
function frameMethods.SetScript(self, k, fn) self.__scripts[k] = fn end
function frameMethods.GetScript(self, k) return self.__scripts[k] end
function frameMethods.HookScript(self, k, fn)
    self.__hooks[k] = self.__hooks[k] or {}
    table.insert(self.__hooks[k], fn)
end
function frameMethods.Show(self)
    if not self.__shown then
        self.__shown = true
        if self.__scripts.OnShow then self.__scripts.OnShow(self) end
    end
end
function frameMethods.Hide(self)
    if self.__shown then
        self.__shown = false
        if self.__scripts.OnHide then self.__scripts.OnHide(self) end
    end
end
function frameMethods.SetShown(self, v) if v then self:Show() else self:Hide() end end
function frameMethods.IsShown(self) return self.__shown end
function frameMethods.SetChecked(self, v) self.__checked = not not v end
function frameMethods.GetChecked(self) return self.__checked end
function frameMethods.SetSize(self, w, h) self.__w, self.__h = w, h end
function frameMethods.SetWidth(self, w) self.__w = w end
function frameMethods.SetHeight(self, h) self.__h = h end
function frameMethods.GetWidth(self) return self.__w or 0 end
function frameMethods.GetHeight(self) return self.__h or 0 end
function frameMethods.SetText(self, t) self.__text = t or "" end
function frameMethods.GetText(self) return self.__text end
function frameMethods.SetAttribute(self, k, v) self.__attributes[k] = v end
function frameMethods.GetAttribute(self, k) return self.__attributes[k] end
function frameMethods.CreateFontString(self) return newFontString() end
function frameMethods.CreateTexture(self) return newFontString() end
function frameMethods.GetName(self) return self.__name end
function frameMethods.GetParent(self) return self.__parent end

local function newFrame(name, parent)
    local f = {
        __name = name, __parent = parent, __shown = true, __checked = false,
        __events = {}, __scripts = {}, __hooks = {}, __attributes = {},
    }
    setmetatable(f, { __index = function(_, k)
        local m = frameMethods[k]
        if m then return m end
        -- unknown WoW frame methods (PascalCase) are safe no-ops
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end })
    table.insert(M.__frames, f)
    return f
end

return function()
    M = { __frames = {}, __timers = {}, __prints = {} }

    -- ------------------------------------------------------ game state
    M.state = {
        class = "HUNTER",
        petFamily = nil,     -- localized UnitCreatureFamily("pet"); nil = no pet
        petLevel = 1,
        playerLevel = 60,
        tpTotal = 0, tpSpent = 0,
        money = 0,
        petKnown = {},       -- spellId -> true: IsSpellKnown(spell, true)
        playerSpells = {},   -- spellId -> true: IsPlayerSpell
        crafts = {},         -- { {name=, rank=, craftType=, tp=, reqLevel=}, ... }
        services = {},       -- { {name=, rank=, category=, cost=}, ... }
        combat = false,
        inInstance = false, instanceId = nil,
        mapId = nil, mapInfo = {}, realZones = {},
    }

    -- ------------------------------------------------------ dispatch
    function M.Fire(event, ...)
        local snapshot = {}
        for i, f in ipairs(M.__frames) do snapshot[i] = f end
        for _, f in ipairs(snapshot) do
            if f.__events[event] and f.__scripts.OnEvent then
                f.__scripts.OnEvent(f, event, ...)
            end
        end
    end
    function M.FireHooks(frame, script, ...)
        for _, fn in ipairs(frame.__hooks[script] or {}) do fn(...) end
    end
    function M.FlushTimers()
        local t = M.__timers
        M.__timers = {}
        for _, fn in ipairs(t) do fn() end
    end

    -- ------------------------------------------------------ frames / UI
    M.CreateFrame = function(_, name, parent)
        local f = newFrame(name, parent)
        if name then M.__env[name] = f end
        return f
    end
    M.UIParent = newFrame("UIParent")
    M.WorldFrame = newFrame("WorldFrame")

    M.SpellBookFrame = newFrame("SpellBookFrame")
    M.SpellBookFrame.bookType = "spell"
    M.SpellBookFrame.selectedSkillLine = 2
    M.SpellBookFrame.Update = function() end
    M.SpellBookFrame.UpdateSpells = function() end
    for i = 1, 8 do M["SpellBookSkillLineTab" .. i] = newFrame("SpellBookSkillLineTab" .. i) end
    for i = 1, 12 do M["SpellButton" .. i] = newFrame("SpellButton" .. i) end
    M.SpellBookPrevPageButton = newFrame("SpellBookPrevPageButton")
    M.SpellBookNextPageButton = newFrame("SpellBookNextPageButton")
    M.SpellBookPageText = newFrame("SpellBookPageText")

    local function newTooltip(name)
        local tip = newFrame(name)
        tip.__lines = {}
        tip.SetOwner = function(self) self.__lines = {}; self.__spell = nil end
        tip.SetSpellByID = function(self, id) self.__spell = id end
        tip.AddLine = function(self, text) table.insert(self.__lines, tostring(text)) end
        tip.SetHyperlink = function() end
        tip.GetItem = function(self)
            if self.__item then return self.__item[1], self.__item[2] end
        end
        return tip
    end
    M.GameTooltip = newTooltip("GameTooltip")
    M.ItemRefTooltip = newTooltip("ItemRefTooltip")

    M.hooksecurefunc = function(a, b, c)
        if type(a) == "table" then
            local orig = a[b]
            a[b] = function(...)
                local r = orig(...)
                c(...)
                return r
            end
        else
            local orig = M.__env[a]
            M.__env[a] = function(...)
                local r = orig(...)
                b(...)
                return r
            end
        end
    end

    -- ------------------------------------------------------ unit / player
    M.UnitClass = function() return M.state.class, M.state.class end
    M.UnitCreatureFamily = function() return M.state.petFamily end
    M.UnitExists = function(u) if u == "pet" then return M.state.petFamily ~= nil end return true end
    M.UnitLevel = function(u)
        if u == "pet" then
            if not M.state.petFamily then return 0 end
            return M.state.petLevel
        end
        return M.state.playerLevel
    end
    M.IsSpellKnown = function(spell, pet) return (pet and M.state.petKnown[spell]) or false end
    M.IsPlayerSpell = function(spell) return M.state.playerSpells[spell] or false end
    M.GetPetTrainingPoints = function() return M.state.tpTotal, M.state.tpSpent end
    M.GetMoney = function() return M.state.money end
    M.InCombatLockdown = function() return M.state.combat end
    M.UnitGUID = function() return nil end

    -- ------------------------------------------------------ spells / items
    -- deterministic fake names: "Spell<id>" / "Item<id>"
    M.GetSpellInfo = function(id) return "Spell" .. id, nil, "icon" .. id end
    M.GetItemInfo = function(id) return "Item" .. id end
    M.GetCoinTextureString = function(c) return tostring(c) .. "c" end

    -- ------------------------------------------------------ craft / trainer
    M.GetNumCrafts = function() return #M.state.crafts end
    M.GetCraftInfo = function(i)
        local c = M.state.crafts[i]
        if not c then return nil end
        return c.name, c.rank, c.craftType or "available", nil, nil, c.tp or 0, c.reqLevel or 0
    end
    M.GetNumTrainerServices = function() return #M.state.services end
    M.GetTrainerServiceInfo = function(i)
        local s = M.state.services[i]
        if not s then return nil end
        return s.name, s.rank, s.category or "available"
    end
    M.GetTrainerServiceCost = function(i)
        local s = M.state.services[i]
        return s and s.cost or 0
    end

    -- ------------------------------------------------------ world / zones
    M.IsInInstance = function() return M.state.inInstance end
    M.GetInstanceInfo = function()
        return "Inst", "party", nil, nil, nil, nil, nil, M.state.instanceId
    end
    M.C_Map = {
        GetBestMapForUnit = function() return M.state.mapId end,
        GetMapInfo = function(id) return M.state.mapInfo[id] end,
    }
    M.GetRealZoneText = function(id) return M.state.realZones[id] end

    -- ------------------------------------------------------ misc API
    M.C_AddOns = { GetAddOnMetadata = function() return "test" end }
    M.C_Timer = { After = function(_, fn) table.insert(M.__timers, fn) end }
    M.GetLocale = function() return "enUS" end
    M.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        table.insert(M.__prints, table.concat(parts, " "))
    end
    M.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    M.strlower = string.lower
    M.strtrim = function(s) return (tostring(s):gsub("^%s*(.-)%s*$", "%1")) end
    M.strsplit = function(sep, s)
        local parts = {}
        for p in string.gmatch(s, "([^" .. sep .. "]+)") do parts[#parts + 1] = p end
        return unpack(parts)
    end
    M.PlaySound = function() end
    M.SOUNDKIT = setmetatable({}, { __index = function() return 0 end })
    M.SearchBoxTemplate_OnTextChanged = function() end
    M.UNKNOWN = "Unknown"
    M.BOOKTYPE_PET = "pet"
    M.BOOKTYPE_SPELL = "spell"
    M.SPELLS_PER_PAGE = 12
    M.MAX_SKILLLINE_TABS = 8
    M.SlashCmdList = {}

    -- ------------------------------------------------------ Settings API
    M.Settings = {
        RegisterVerticalLayoutCategory = function()
            return {}, { AddInitializer = function() end }
        end,
        RegisterAddOnSetting = function() return {} end,
        SetOnValueChangedCallback = function() end,
        CreateCheckbox = function() end,
        CreateSliderOptions = function() return { SetLabelFormatter = function() end } end,
        CreateSlider = function() end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function() end,
        VarType = { Boolean = "boolean", Number = "number" },
    }
    M.CreateSettingsListSectionHeaderInitializer = function() return {} end
    M.MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }

    return M
end
