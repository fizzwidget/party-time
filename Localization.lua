-----------------------------------------------------
-- localization.lua
-- English strings by default, localizations override with their own.
------------------------------------------------------
-- Setup for shorthand when defining strings and automatic lookup in settings
local addonName = ...
_G[addonName.."_Locale"] = {}
local Locale = _G[addonName.."_Locale"]
Locale.Text = {}
Locale.Setting = {}
Locale.SettingTooltip = {}
local L = Locale.Text
local S = Locale.Setting
local T = Locale.SettingTooltip
------------------------------------------------------
S.Memory = "Save markers per player"
T.Memory = "Remembers the target marker you set on each player"
S.Autoapply = "Automatically set markers"
T.Autoapply = "Sets saved markers for known players and defaults based on party position if they are unknown"
------------------------------------------------------

if (GetLocale() == "frFR") then

end

------------------------------------------------------

if (GetLocale() == "deDE") then

end

------------------------------------------------------

if (GetLocale() == "esES" or GetLocale() == "esMX") then

end

------------------------------------------------------

if (GetLocale() == "ruRU") then

end

------------------------------------------------------

if (GetLocale() == "koKR") then

end

------------------------------------------------------

if (GetLocale() == "zhTW") then

end
