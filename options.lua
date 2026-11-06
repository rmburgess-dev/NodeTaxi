--[[ In-game settings page: Settings -> AddOns -> NodeTaxi ----------------]]
local ADDON_NAME, ns = ...
local NodeTaxi = ns

local function addInitializer(category, initializer)
    Settings.RegisterInitializer(category, initializer)
    return initializer
end

local function addHeader(category, text)
    local factory = CreateSettingsListSectionHeaderInitializer
    if not factory then
        return
    end
    addInitializer(category, factory(text))
end

local function addCheckbox(category, key, label, tooltip)
    local defaults = NodeTaxi:GetDefaults()
    local setting = Settings.RegisterProxySetting(
        category, "NodeTaxi_" .. key, Settings.VarType.Boolean, label, defaults[key],
        function() return NodeTaxi:GetSettings()[key] end,
        function(value) NodeTaxi:SetSetting(key, value) end)
    addInitializer(category, Settings.CreateCheckboxInitializer(setting, nil, tooltip))
end

local function addSlider(category, key, label, minValue, maxValue, step, tooltip, suffix)
    local defaults = NodeTaxi:GetDefaults()
    local setting = Settings.RegisterProxySetting(
        category, "NodeTaxi_" .. key, Settings.VarType.Number, label, defaults[key],
        function() return NodeTaxi:GetSettings()[key] end,
        function(value) NodeTaxi:SetSetting(key, value) end)

    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    if options and options.SetLabelFormatter and MinimalSliderWithSteppersMixin
        and MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            local display = math.floor((value or 0) * 10 + 0.5) / 10
            return tostring(display) .. (suffix or "")
        end)
    end
    addInitializer(category, Settings.CreateSliderInitializer(setting, options, tooltip))
end

local function addDropdown(category, key, label, values, tooltip)
    local defaults = NodeTaxi:GetDefaults()
    local setting = Settings.RegisterProxySetting(
        category, "NodeTaxi_" .. key, Settings.VarType.String, label, defaults[key],
        function() return NodeTaxi:GetSettings()[key] end,
        function(value) NodeTaxi:SetSetting(key, value) end)

    local function options()
        local container = Settings.CreateControlTextContainer()
        for _, entry in ipairs(values) do
            container:Add(entry[1], entry[2])
        end
        return container:GetData()
    end
    addInitializer(category, Settings.CreateDropdownInitializer(setting, options, tooltip))
end

local function addButton(category, label, buttonText, fn, tooltip)
    local factory = CreateSettingsButtonInitializer
    if not factory then
        return
    end
    addInitializer(category, factory(label, buttonText or label, fn, tooltip, true))
end

function NodeTaxi:BuildOptions()
    if self.settingsCategory or not Settings or not Settings.RegisterVerticalLayoutCategory then
        return
    end

    local category = Settings.RegisterVerticalLayoutCategory("NodeTaxi")
    self.settingsCategory = category

    addHeader(category, "Routing")
    addCheckbox(category, "auto", "Rebuild automatically when the TomTom target changes",
        "When enabled, NodeTaxi rebuilds after a TomTom arrow-target change.")
    addDropdown(category, "kind", "Resource filter", {
        { "auto", "Auto — follow active tracking" },
        { "herb", "Herbs only" },
        { "ore", "Ore only" },
        { "both", "Herbs and ore" },
    }, "Which resource nodes the route may include.")

    addSlider(category, "maxNodes", "Maximum nodes per leg", 1, 20, 1,
        "Maximum number of resource nodes selected for one zone leg.", " nodes")
    addSlider(category, "cluster", "Maximum nodes per nearby cluster", 1, 8, 1,
        "Limits how many nodes one compact cluster can contribute.", " nodes")
    addSlider(category, "spur", "Maximum node deviation", 0, 300, 5,
        "Maximum yards a selected node may pull away from the hidden corridor.", " yd")
    addSlider(category, "corridor", "Corridor search width", 25, 600, 25,
        "How far from the corridor NodeTaxi looks for resource nodes.", " yd")
    addSlider(category, "detour", "Detour budget", 1.0, 3.0, 0.1,
        "Route length relative to direct distance. Higher values allow more wandering.", "×")
    addSlider(category, "replan", "Rolling re-plan distance", 0, 100, 5,
        "How far you move before the current leg is re-evaluated. Zero updates only when the TomTom target changes.", " yd")

    addHeader(category, "Display")
    addCheckbox(category, "allNodes", "Show every known node",
        "Draws the full known-node field on the world map and minimap. Turn off for a route-only view.")
    addCheckbox(category, "quiet", "Quiet routine automatic chat",
        "Suppresses automatic node-reached, crossing and gather messages. Manual /nt commands and the short route-update line still respond.")
    addCheckbox(category, "routeChat", "Show a short route-update line",
        "Prints one line when an automatic TomTom target/zone rebuild finishes.")
    addSlider(category, "ring", "Nearby-node circle distance", 0, 200, 5,
        "Nodes inside this distance become hollow circles so the game's tracking dot stays visible.", " yd")

    addHeader(category, "Actions")
    addButton(category, "Build the route now", "Build route", function()
        NodeTaxi.HandleCommand("route")
    end, "Build or rebuild the route to the current TomTom target.")
    addButton(category, "Clear the route", "Clear route", function()
        NodeTaxi.HandleCommand("stop")
    end, "Remove the current NodeTaxi route overlay.")
    addButton(category, "Preview the overlay", "Preview", function()
        NodeTaxi.HandleCommand("preview")
    end, "Draw a synthetic route to verify the overlay.")
    addButton(category, "Import GatherMate2 data", "Import", function()
        NodeTaxi.HandleCommand("import gathermate2")
    end, "Import local GatherMate2 herb and ore data into NodeTaxiDB.")
    addButton(category, "Reset settings to defaults", "Reset defaults", function()
        NodeTaxi:ResetSettings()
        if SettingsPanel and SettingsPanel.GetCurrentCategory and SettingsPanel.SelectCategory then
            local current = SettingsPanel:GetCurrentCategory()
            if current then
                SettingsPanel:SelectCategory(current, true)
            end
        end
    end, "Reset all configurable NodeTaxi settings to their defaults.")

    addHeader(category, "About")
    local version = "unknown"
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or version
    elseif GetAddOnMetadata then
        version = GetAddOnMetadata(ADDON_NAME, "Version") or version
    end
    addButton(category, "NodeTaxi " .. tostring(version), "Print diagnostics", function()
        NodeTaxi.HandleCommand("debug")
    end, "Print client, tracking, position, snapshot and overlay diagnostics to chat.")

    Settings.RegisterAddOnCategory(category)
end
