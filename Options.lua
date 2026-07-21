local ADDON_NAME, ns = ...
local L = ns.L

-- Settings under Settings -> Options -> AddOns using the modern Settings
-- API, same pattern as ProfessionTips. Changes apply immediately.

ns.OnInit(function()
    local category, layout = Settings.RegisterVerticalLayoutCategory(ADDON_NAME)
    category.ID = ADDON_NAME
    ns.settingsCategory = category

    local function AddHeader(text)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end

    AddHeader(L["Pet Training List"])

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "PetTips_EnableList",
            "enableList",
            ns.db,
            Settings.VarType.Boolean,
            L["Enable training list"],
            true
        )
        if Settings.SetOnValueChangedCallback then
            Settings.SetOnValueChangedCallback("PetTips_EnableList", function()
                if ns.UpdateTrainingTab then ns.UpdateTrainingTab() end
            end)
        end
        Settings.CreateCheckbox(category, setting,
            L["Adds a tab to the spellbook's Pet page listing everything your pet can learn - now and later. Hunters: from pet trainers or by taming wild beasts. Warlocks: from demon trainer grimoires."])
    end

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "PetTips_ShowKnownByPet",
            "showKnownByPet",
            ns.db,
            Settings.VarType.Boolean,
            L["Show abilities known by pet"],
            true
        )
        if Settings.SetOnValueChangedCallback then
            Settings.SetOnValueChangedCallback("PetTips_ShowKnownByPet", function()
                if ns.RefreshTrainingList then ns.RefreshTrainingList() end
            end)
        end
        Settings.CreateCheckbox(category, setting,
            L["Also list the ranks your current pet already knows, as a gray reference section."])
    end

    AddHeader(L["Beast Training"])

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "PetTips_CraftPanel",
            "craftPanel",
            ns.db,
            Settings.VarType.Boolean,
            L["Show missing-ranks panel at Beast Training"],
            false
        )
        if Settings.SetOnValueChangedCallback then
            Settings.SetOnValueChangedCallback("PetTips_CraftPanel", function()
                if ns.UpdateCraftSidePanel then ns.UpdateCraftSidePanel() end
            end)
        end
        Settings.CreateCheckbox(category, setting,
            L["Attach a panel to the right of the Beast Training window listing the ranks your current pet is still missing, with the same colors and tooltips as the training list."])
    end

    AddHeader(L["Beast Tooltips"])

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "PetTips_BeastTooltips",
            "beastTooltips",
            ns.db,
            Settings.VarType.Boolean,
            L["Show taught abilities on beast tooltips"],
            true
        )
        Settings.CreateCheckbox(category, setting,
            L["Beasts that can teach a pet ability show it in their tooltip: green if you already know how to teach it, red if it is new (worth taming)."])
    end

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "PetTips_MobLines",
            "mobLines",
            ns.db,
            Settings.VarType.Number,
            L["Teaching mobs listed per ability"],
            10
        )
        local options = Settings.CreateSliderOptions(3, 25, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, setting, options,
            L["How many tameable mobs an ability tooltip lists before summarizing the rest as '+N more'. Mobs in your current zone are always sorted to the top (in green), so they are never hidden by this cap."])
    end

    AddHeader(L["Demon Grimoires (Warlock)"])

    do
        local setting = Settings.RegisterAddOnSetting(
            category,
            "PetTips_GrimoireTooltips",
            "grimoireTooltips",
            ns.db,
            Settings.VarType.Boolean,
            L["Show hints on grimoire tooltips"],
            true
        )
        Settings.CreateCheckbox(category, setting,
            L["Grimoire items show whether your demon already knows that rank - green when known, red when it is still worth buying, gray when a higher rank makes it obsolete."])
    end

    Settings.RegisterAddOnCategory(category)
end)

SLASH_PETTIPS1 = "/pettips"
SlashCmdList.PETTIPS = function(msg)
    local cmd = msg and strtrim(msg):lower() or ""
    if cmd == "debug" then
        if ns.TrainerScanDebug then ns.TrainerScanDebug() end
        return
    elseif cmd == "list" then
        if ns.TrainingListDebug then ns.TrainingListDebug() end
        return
    end
    Settings.OpenToCategory(ADDON_NAME)
end
