------------------------------------------------------
-- Addon loading & shared infrastructure
------------------------------------------------------
local addonName, T = ...
_G[addonName] = T

T.Title = C_AddOns.GetAddOnMetadata(addonName, "Title")
T.Version = C_AddOns.GetAddOnMetadata(addonName, "Version")

-- event handling
T.EventFrame = CreateFrame("Frame")
T.EventFrame:SetScript("OnEvent", function(self, event, ...)
    local handler = T.EventHandlers[event]
    assert(handler, "Missing event handler for registered event "..event)
    handler(T.EventFrame, ...)
end)
T.EventHandlers = setmetatable({}, {__newindex = function(table, key, value)
    assert(type(value) == 'function', "Members of this table must be functions")
    rawset(table, key, value)
    T.EventFrame:RegisterEvent(key)
end })
local Events = T.EventHandlers

------------------------------------------------------
-- Saved variables & settings UI
------------------------------------------------------

function T.SetupSettings(settings)
    settings:Checkbox("Memory", true)
    settings:Checkbox("Autoapply", true)
end

if not _G[addonName.."_SavedPresets"] then
    _G[addonName.."_SavedPresets"] = {}
end
T.SavedPresets = _G[addonName.."_SavedPresets"]

------------------------------------------------------
-- Party warning "chat channel"
------------------------------------------------------

function T.HandleAddonMessage(self, prefix, message, channel, sender)
   if prefix ~= addonName then return end
   
   print(prefix, message, channel, sender)
   local id, text = strmatch(message, "(.)|(.+)")
   if id == "W" then
      -- keep {star}, {rt1}, etc substitution like chat channels
      text = C_ChatInfo.ReplaceIconAndGroupExpressions(text)
      RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["WHISPER"])
      PlaySound(SOUNDKIT.RAID_WARNING)
    
   elseif id == "I" then
      print(text, sender)
      local name, server = strsplit("-", sender)
      for index = 1, 4 do
         local unit = "party"..index
         if not UnitExists(unit) then break end
         if UnitName(unit) == name then
            if text == "START" then
               -- TODO show icon
               print(unit, "is in a movie")
            elseif text == "STOP" then
               -- TODO hide icon
               print(unit, "is no longer in a movie")         
            end
            break
         end
      end
      
   end

end

C_ChatInfo.RegisterAddonMessagePrefix(addonName)

EventRegistry:RegisterFrameEventAndCallback("CHAT_MSG_ADDON", T.HandleAddonMessage)

function T.ChatCommandHandler(text)
    C_ChatInfo.SendAddonMessage(addonName, "W|"..text, "PARTY")
end

SLASH_PARTYTIME1 = "/pt"
SLASH_PARTYTIME2 = "/pw"
SlashCmdList["PARTYTIME"] = T.ChatCommandHandler


------------------------------------------------------
-- Save & restore target markers
------------------------------------------------------


local function MarkerFromIndex(index)
    return C_ChatInfo.ReplaceIconAndGroupExpressions(("{rt%d}"):format(index))
end

-- set saved markers (if any) for party members
function T.AutoSetPartySymbols()
   local units = {"player", "party1", "party2", "party3", "party4"}
   local unitMarkers = {}
   local nextFreeMarker = 0
   for _, unit in pairs(units) do
      if UnitExists(unit) then
         local preset = T.SavedPresets[UnitName(unit)]
         if preset and T.Settings.Memory then
            SetRaidTarget(unit, preset)
            unitMarkers[preset] = unit
            --print("setting unitMarkers", preset, unit)
         else
            CancelNextSave = true
            repeat  
               nextFreeMarker = nextFreeMarker + 1
            until not unitMarkers[nextFreeMarker]
            SetRaidTarget(unit, nextFreeMarker)
         end
      end
   end
end
function Events:GROUP_ROSTER_UPDATE()
    if T.Settings.Autoapply and UnitLeadsAnyGroup("player") then
        T.AutoSetPartySymbols()
    end
end

-- save assigned marker whenever one is set on a unit
-- TODO should we save markers only for certain units (is a player, in party, etc?)
function T.SetRaidTarget(unit, index)
    if not CancelNextSave and T.Settings.RememberMenuMarkers then
        --print("saving", MarkerFromIndex(index), "for", UnitName(unit))
        T.SavedPresets[UnitName(unit)] = index
    end
    CancelNextSave = false
end
hooksecurefunc("SetRaidTarget", T.SetRaidTarget)

function menu(owner, rootDescription, contextData)
    local function IsSelected()
        return T.Settings.RememberMenuMarkers
    end
    local function SetSelected()
        T.Settings.RememberMenuMarkers = not T.Settings.RememberMenuMarkers
    end
    rootDescription:CreateDivider();
    rootDescription:CreateTitle("PartyTime");
    rootDescription:CreateCheckbox("Remember Target Marker", IsSelected, SetSelected)
end

Menu.ModifyMenu("MENU_UNIT_SELF", menu)
Menu.ModifyMenu("MENU_UNIT_PARTY", menu)

------------------------------------------------------
-- Show when party members in movie/cinematic
------------------------------------------------------

function Events:CINEMATIC_START()
   C_ChatInfo.SendAddonMessage(addonName, "I|START", "PARTY")
   print("CINEMATIC_START")
end

function Events:CINEMATIC_STOP(...)
   C_ChatInfo.SendAddonMessage(addonName, "I|STOP", "PARTY")
   print("CINEMATIC_STOP")
end

function Events:PLAY_MOVIE(...)
   C_ChatInfo.SendAddonMessage(addonName, "I|START", "PARTY")
   print("PLAY_MOVIE")
end

function Events:STOP_MOVIE(...)
   C_ChatInfo.SendAddonMessage(addonName, "I|STOP", "PARTY")
   print("STOP_MOVIE")
end

-- TEMP
function T.MakePartyIcon()   
   local parent = PartyFrame.MemberFrame1
   local frame = CreateFrame("Frame", nil, parent)
   frame:SetAllPoints(parent.Portrait)
   local texture = frame:CreateTexture()
   texture:SetAllPoints()
   
   --local icon = "Interface\\Icons\\Inv_misc_film_01"
   local icon = "Interface\\Icons\\spell_nature_timestop"
   texture:SetTexture(icon)
   
   frame:SetScript("OnEnter", function()
      GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
      GameTooltip:SetText("Watching a movie")x
      GameTooltip:Show()
   end)
   frame:SetScript("OnLeave", GameTooltip_Hide)
end
