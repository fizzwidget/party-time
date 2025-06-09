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
-- Constants
------------------------------------------------------
