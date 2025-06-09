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
-- Addon message passing
------------------------------------------------------

function T.HandleAddonMessage(self, prefix, message, channel, sender)
    if prefix ~= addonName then return end
    
    print(prefix, message, channel, sender)
end

C_ChatInfo.RegisterAddonMessagePrefix(addonName)
EventRegistry:RegisterFrameEventAndCallback("CHAT_MSG_ADDON", T.HandleAddonMessage)

function T.TestMessage(text, channel)
    if not channel then
        channel = "PARTY"
    end
    C_ChatInfo.SendAddonMessage(addonName, text, channel)
end