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
    
    -- keep {star}, {rt1}, etc substitution like chat channels
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
-- Save & restore target markers
------------------------------------------------------

local units = {"player", "party1", "party2", "party3", "party4"}

local function MarkerFromIndex(index)
    return C_ChatInfo.ReplaceIconAndGroupExpressions(("{rt%d}"):format(index))
end

-- set saved markers (if any) for party members
function T.AutoSetPartySymbols()
    for i, unit in pairs(units) do
        if UnitExists(unit) then
            local preset = T.SavedPresets[UnitName(unit)]
            if preset then
                SetRaidTarget(unit, preset)
            end
        end
    end
end

function Events:GROUP_ROSTER_UPDATE()
    T.AutoSetPartySymbols()
end

-- save assigned marker whenever one is set on a unit
-- TODO should we save markers only for certain units (is a player, in party, etc?)
function T.SetRaidTarget(unit, index)
    --print("saving", MarkerFromIndex(index), "for", UnitName(unit))
    GFW_PartyTime_SavedPresets[UnitName(unit)] = index
end
hooksecurefunc("SetRaidTarget", T.SetRaidTarget)