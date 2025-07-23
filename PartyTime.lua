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

if not _G[addonName.."_TrackedQuests"] then
	_G[addonName.."_TrackedQuests"] = {}
end
T.TrackedQuests = _G[addonName.."_TrackedQuests"]

------------------------------------------------------
-- Party warning "chat channel"
------------------------------------------------------

function T.HandleAddonMessage(self, prefix, message, channel, sender)
	if prefix ~= addonName then return end
	local id, text = strmatch(message, "(.)|(.+)")
	if id == "W" then
		-- keep {star}, {rt1}, etc substitution like chat channels
		text = C_ChatInfo.ReplaceIconAndGroupExpressions(text)
		RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["WHISPER"])
		PlaySound(SOUNDKIT.RAID_WARNING)
		
	elseif id == "M" then
		local name, server = strsplit("-", sender)
		for index = 1, 4 do
			local unit = "party"..index
			if not UnitExists(unit) then break end
			if UnitName(unit) == name then
				if text == "START" then
					T.ShowPartyMovieIcon(index)
				elseif text == "STOP" then
					T.HidePartyMovieIcon(index)
				end
				break
			end
		end
		
	elseif id == "Q" then
		local action, quest = strsplit(" ", text)
		local questID = tonumber(quest)
		if action == "ADD" then
			print(action, questID)
			T.TrackedQuests[questID] = true
		elseif action == "REMOVE" then
			print(action, questID)
			T.TrackedQuests[questID] = nil
		end
	end
end

C_ChatInfo.RegisterAddonMessagePrefix(addonName)

EventRegistry:RegisterFrameEventAndCallback("CHAT_MSG_ADDON", T.HandleAddonMessage)

function T.ChatCommandHandler(text, editBox)
	C_ChatInfo.SendAddonMessage(addonName, "W|"..text, "PARTY")
	SendChatMessage(text, "PARTY", editBox.languageID)
end

SLASH_PARTYTIME1 = "/pt"
SLASH_PARTYTIME2 = "/pw"
SlashCmdList["PARTYTIME"] = T.ChatCommandHandler

------------------------------------------------------
-- Shared focused-quest tracker
------------------------------------------------------

-- TEMP
SLASH_PARTYQUEST1 = "/pq"
SlashCmdList["PARTYQUEST"] = function(text)
	if text == "add" then
		C_ChatInfo.SendAddonMessage(addonName, "Q|ADD 1234", "PARTY")
	elseif text == "remove" then
		C_ChatInfo.SendAddonMessage(addonName, "Q|REMOVE 1234", "PARTY")
	elseif text == "" then
		DevTools_Dump(T.TrackedQuests)
	end
end

local function questLogMenu(owner, rootDescription, contextData)
	local function IsSelected()
		return T.TrackedQuests[owner.questID]
	end
	local function SetSelected()
		if T.TrackedQuests[owner.questID] then
			T.TrackedQuests[owner.questID] = nil
			C_ChatInfo.SendAddonMessage(addonName, "Q|REMOVE "..owner.questID, "PARTY")
		else
			T.TrackedQuests[owner.questID] = true
			C_ChatInfo.SendAddonMessage(addonName, "Q|ADD "..owner.questID, "PARTY")
		end
	end
	rootDescription:CreateDivider();
	rootDescription:CreateTitle("PartyTime");
	rootDescription:CreateCheckbox("Track Quest", IsSelected, SetSelected)
end
Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", questLogMenu)

function T.MakeFrame()
	T.Frame = CreateFrame("GameTooltip", addonName.."_Tooltip", UIParent, "GameTooltipTemplate")
	
	T.Frame.CloseButton = CreateFrame("Button", nil, T.Frame, "UIPanelCloseButtonNoScripts")
	T.Frame.CloseButton:SetScript("OnClick", function() T.Frame:Hide() end)
	T.Frame.CloseButton:SetPoint("TOPRIGHT")
	
	T.Frame:SetPoint("CENTER")
	T.Frame:SetFrameStrata("MEDIUM")
	
	T.Frame:EnableMouse(true)
	T.Frame:SetMovable(true)
	T.Frame:RegisterForDrag("LeftButton")
	T.Frame:SetScript("OnDragStart", T.Frame.StartMoving)
	T.Frame:SetScript("OnDragStop", T.Frame.StopMovingOrSizing)
end

function T.ShowFrame()
	if not T.Frame then
		T.MakeFrame()
	end
	
	-- TEMP
	T.Frame:SetOwner(UIParent, "ANCHOR_PRESERVE")
	GameTooltip_SetTitle(T.Frame, T.Title, NORMAL_FONT_COLOR, false)
	T.Frame:SetPadding(T.Frame.CloseButton:GetWidth() + 2, 0)
	T.Frame:Show()
end

T.ShowFrame()

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
				T.TrySetRaidTarget(unit, preset)
				unitMarkers[preset] = unit
			elseif T.Settings.Autoapply then
				CancelNextSave = true
				repeat
					nextFreeMarker = nextFreeMarker + 1
					-- mod gets us range 0...7, we want 1...8
					if nextFreeMarker > NUM_RAID_MARKERS then
						nextFreeMarker = 1
					end
				until not unitMarkers[nextFreeMarker]
				T.TrySetRaidTarget(unit, nextFreeMarker)
			end
		end
	end
end
function T.TrySetRaidTarget(unit, index)
	if GetRaidTargetIndex(unit) == index then return end
	SetRaidTarget(unit, index)
end

function Events:GROUP_ROSTER_UPDATE()
	if UnitLeadsAnyGroup("player") then
		T.AutoSetPartySymbols()
	end
end

-- save assigned marker whenever one is set on a unit
function T.SetRaidTarget(unit, index)
	if UnitIsPlayer(unit) and UnitPlayerOrPetInParty(unit) then
		if not CancelNextSave and T.Settings.RememberMenuMarkers then
			--print("saving", MarkerFromIndex(index), "for", UnitName(unit))
			T.SavedPresets[UnitName(unit)] = index
		end
		CancelNextSave = false
	end
end
hooksecurefunc("SetRaidTarget", T.SetRaidTarget)

local function partyMenu(owner, rootDescription, contextData)
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

Menu.ModifyMenu("MENU_UNIT_SELF", partyMenu)
Menu.ModifyMenu("MENU_UNIT_PARTY", partyMenu)

------------------------------------------------------
-- Show when party members in movie/cinematic
------------------------------------------------------

function Events:CINEMATIC_START()
	C_ChatInfo.SendAddonMessage(addonName, "M|START", "PARTY")
end

function Events:CINEMATIC_STOP(...)
	C_ChatInfo.SendAddonMessage(addonName, "M|STOP", "PARTY")
end

function Events:PLAY_MOVIE(...)
	C_ChatInfo.SendAddonMessage(addonName, "M|START", "PARTY")
end

function Events:STOP_MOVIE(...)
	C_ChatInfo.SendAddonMessage(addonName, "M|STOP", "PARTY")
end

T.Icons = {}

function T.MakePartyMovieIcon(index)
	local parent = PartyFrame["MemberFrame"..index]
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints(parent.Portrait)
	local texture = frame:CreateTexture()
	texture:SetAllPoints()
	
	local icon = "Interface\\Icons\\Inv_misc_film_01"
	texture:SetTexture(icon)
	
	frame:SetScript("OnEnter", function()
		GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Watching a movie")
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	T.Icons[index] = frame
	return frame
end

function T.ShowPartyMovieIcon(index)
	local frame = T.Icons[index]
	if not frame then
		frame = T.MakePartyMovieIcon(index)
	else
		frame:Show()
	end
end

function T.HidePartyMovieIcon(index)
	local frame = T.Icons[index]
	if frame then
		frame:Hide()
	end
end