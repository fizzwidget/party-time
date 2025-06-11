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
-- Settings UI
------------------------------------------------------

function T.SetupSettings(settings)
    settings:Checkbox("Memory", true)
end

------------------------------------------------------
-- Addon message passing
------------------------------------------------------

function T.HandleAddonMessage(self, prefix, message, channel, sender)
    if prefix ~= addonName then return end
    
    -- TODO keep {star}, {rt1}, etc substitution?
    message = C_ChatInfo.ReplaceIconAndGroupExpressions(message)
    
    RaidNotice_AddMessage(RaidWarningFrame, message, ChatTypeInfo["WHISPER"])
    PlaySound(SOUNDKIT.RAID_WARNING)
end

C_ChatInfo.RegisterAddonMessagePrefix(addonName)
EventRegistry:RegisterFrameEventAndCallback("CHAT_MSG_ADDON", T.HandleAddonMessage)

function T.ChatCommandHandler(text)
    C_ChatInfo.SendAddonMessage(addonName, text, "PARTY")
end

SLASH_PARTYTIME1 = "/pt"
SLASH_PARTYTIME2 = "/pw"
SlashCmdList["PARTYTIME"] = T.ChatCommandHandler


------------------------------------------------------
-- Target marker detection
------------------------------------------------------

local units = {"player", "party1", "party2", "party3", "party4"}

if not GFW_PartyTime_SavedPresets then
    GFW_PartyTime_SavedPresets = {}
end

function MarkerFromIndex(index)
    return C_ChatInfo.ReplaceIconAndGroupExpressions(string.format("{rt%d}", index))
end

function T.SetRaidTarget(unit, index)
    print(UnitName(unit), MarkerFromIndex(index))
    GFW_PartyTime_SavedPresets[UnitName(unit)] = index
end

function T.AutoSetPartySymbols()
    for i, unit in pairs(units) do
        if UnitExists(unit) then
            local preset = GFW_PartyTime_SavedPresets[UnitName(unit)]
            if preset then
                SetRaidTarget(unit, preset)
            end
        end
    end
end

function Events:GROUP_ROSTER_UPDATE()
    T.AutoSetPartySymbols()
end

hooksecurefunc("SetRaidTarget", T.SetRaidTarget)