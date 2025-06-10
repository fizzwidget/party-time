local addonName, T = ...
T.SettingsUI = {}
local S = T.SettingsUI
local L = _G[addonName.."_Locale"]

------------------------------------------------------
-- Proto mixin for quick settings UI element creation
------------------------------------------------------

function S:Checkbox(settingKey, defaultValue, parentInit, onValueChanged)
    local variable = addonName .. "_" .. settingKey
    local labelText = L.Setting[settingKey]
    local setting = Settings.RegisterAddOnSetting(
        self.category, 
        variable, 
        settingKey, 
        self.table,
        type(defaultValue), 
        labelText, 
        defaultValue
    )
    local init = Settings.CreateCheckbox(self.category, setting, L.SettingTooltip[settingKey])
    if parentInit then
        init:Indent()
        init:SetParentInitializer(parentInit)
    end
    if onValueChanged then
        Settings.SetOnValueChangedCallback(variable, onValueChanged)
    end
    return init
end

-- menuOptions: table of string -> value
-- string: key for getting text/tooltip (and referencing the option value without magic numbers in other code)
-- value: number or whatever to read/write for this settings option
function S:CheckboxDropdown(checkSettingKey, checkDefault, menuSettingKey, menuDefault, menuOptions)
    -- Blizz UI allows separate label/tooltip for the checkbox and dropdown but they always keep both same
    -- we'll follow that by using the checkbox key to get the same label/tooltip text for both
    local labelText = L.Setting[checkSettingKey]
    local tooltipText = L.SettingTooltip[checkSettingKey]
    local checkVariable = addonName .. "_" .. checkSettingKey
    local checkSetting = Settings.RegisterAddOnSetting(
        self.category, 
        checkVariable, 
        checkSettingKey, 
        self.table,
        type(checkDefault), 
        labelText, 
        checkDefault
    )
    local menuVariable = addonName .. "_" .. menuSettingKey
    local menuSetting = Settings.RegisterAddOnSetting(
        self.category, 
        menuVariable,
        menuSettingKey,
        self.table,
        type(menuDefault),
        labelText,
        menuDefault
    )
    local function Menu(options)
        -- invert the table so we can put the menu in value order
        local keysForValues = {}
        for key, value in pairs(menuOptions) do
            keysForValues[value] = key
        end
        
        local container = Settings.CreateControlTextContainer()
        for value, key in T:PairsByKeys(keysForValues) do
            container:Add(value, L.Setting[menuSettingKey.."_"..key], L.SettingTooltip[menuSettingKey.."_"..key])
        end
        return container:GetData()
    end
    local initializer = CreateSettingsCheckboxDropdownInitializer(
        checkSetting, labelText, tooltipText,
        menuSetting, Menu, labelText, tooltipText
    )
    initializer:AddSearchTags(labelText, tooltipText)
    self.layout:AddInitializer(initializer)
end

function S:SectionHeader(stringKey)
    local title, tooltip = L.Setting[stringKey], L.SettingTooltip[stringKey]
    self.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title, tooltip))
end

------------------------------------------------------
-- Settings setup
------------------------------------------------------

function S:Initialize()
    self.category, self.layout = Settings.RegisterVerticalLayoutCategory(T.Title)
    self.table = _G[addonName .. "_Settings"] or {}
    T.Settings = self.table
    T.SettingsCategoryID = self.category:GetID()
    

    Settings.RegisterAddOnCategory(self.category)

end


S:Initialize()