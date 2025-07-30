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
	if text == "clear" then
		wipe(T.TrackedQuests)
	elseif text == "test" then
		for id in pairs(T.TrackedQuests) do
			print(id, C_QuestLog.GetTitleForQuestID(id))
			local data = ProcessPartyProgress(id)
			DevTools_Dump(data)
			if data and false then
				print("on quest:", table.concat(data.playersOnQuest, ", "))
				print("ready for turnin:", table.concat(data.playersReady, ", "))
				for objective, status in pairs(data.objectives) do
					local summary = {}
					for player, counts in pairs(status) do 
						local info = ("%s %d/%d"):format(player, counts[1], counts[2])
						tinsert(summary, info)
					end
					print(" ", objective, ":", table.concat(summary, ", "))
				end
			end
		end
	elseif text == "" then
		DevTools_Dump(T.TrackedQuests)
		T.ShowFrame()
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

function T.UpdateFrame()
	if not T.Frame:IsShown() then
		T.FrameUpdateTimer:Cancel()
		return
	end
	T.ShowFrame()
end

function T.ShowFrame()
	if not T.Frame then
		T.MakeFrame()
	end
	
	-- TODO? Don't show frame if not in party / if list empty?
	
	T.Frame:SetOwner(UIParent, "ANCHOR_PRESERVE")
	GameTooltip_SetTitle(T.Frame, "Party Quests", NORMAL_FONT_COLOR, false)
	T.Frame:SetPadding(T.Frame.CloseButton:GetWidth() + 2, 0)
	for id in pairs(T.TrackedQuests) do
		-- TODO? color title if not on quest
		-- different color for "unknown" vs C_QuestLog.IsQuestFlaggedCompleted
		GameTooltip_AddNormalLine(T.Frame, C_QuestLog.GetTitleForQuestID(id), false)
		local data = ProcessPartyProgress(id)
		if data then
			--print("on quest:", table.concat(data.playersOnQuest, ", "))
			--print("ready for turnin:", table.concat(data.playersReady, ", "))
			
			-- TODO? if no objectives, just list party members (colored by status)
			
			-- TODO? don't list self (maybe do for testing though)
			
			for objective, status in pairs(data.objectives) do
				local summary = {}
				for player, counts in pairs(status) do 
					local info = ("%s %d/%d"):format(player, counts[1], counts[2])
					tinsert(summary, info)
				end
				--print(" ", objective, ":", table.concat(summary, ", "))
				GameTooltip_AddHighlightLine(T.Frame, objective, false)
				GameTooltip_AddHighlightLine(T.Frame, table.concat(summary, " "), false, 5)
			end
		end
	end
	
	if T.FrameUpdateTimer then
		T.FrameUpdateTimer:Cancel()
	end
	T.FrameUpdateTimer = C_Timer.NewTimer(1.0, T.UpdateFrame)
	
	T.Frame:Show()
end

function x(input)
	if UnitName(input) == "Sethenot" then
		return GREEN_FONT_COLOR
	elseif UnitClass(input) == "Rogue" then
		return WHITE_FONT_COLOR
	else
		return RED_FONT_COLOR
	end
end

function y(input)
	if input == nil then
		input = ""
		return input
	else
		return input
	end
end

local LINE_TYPE_QUEST = 17
local LINE_TYPE_PLAYER = 18
local LINE_TYPE_OBJECTIVE = 8

function ProcessPartyProgress(questID)
	local omitTitle = false
	local ignoreActivePlayer = false
	local data = C_TooltipInfo.GetQuestPartyProgress(questID, omitTitle, ignoreActivePlayer)
	
	-- TODO: is this what we want to report for quests we're not on?
	if not data then return end
	
	local processed = {}
	processed.playersOnQuest = {}
	processed.playersReady = {}
	processed.objectives = {}
	
	-- if no party, no LINE_TYPE_PLAYER lines in tooltip data
	local currentPlayer = UnitName("player") 
	
	for key, line in pairs(data.lines) do
		if type(key) == "number" then 
			if line.type == LINE_TYPE_QUEST then
				-- we should always have exactly one quest header, right?
				-- in that case, nothing to do here
			elseif line.type == LINE_TYPE_PLAYER then
				currentPlayer = line.leftText
			elseif line.type == LINE_TYPE_OBJECTIVE then
				-- TODO does this one need localization format/pattern support?
				local completed, total, objective = strmatch(line.leftText, "(%d+)/(%d) (.+)")
				if objective then
					if not processed.objectives[objective] then
						processed.objectives[objective] = {}
					end
					processed.objectives[objective][currentPlayer] = {tonumber(completed), tonumber(total)}
				end
				
				local onQuest = strfind(line.leftText, QUEST_PROGRESS_TOOLTIP_QUEST_ON_QUEST, 1, true)
				-- nothing to do with this one, since we infer on quest from others?
				
				local readyForTurnIn = strfind(line.leftText, QUEST_PROGRESS_TOOLTIP_QUEST_READY_FOR_TURN_IN, 1, true)
				if readyForTurnIn then
					tinsert(processed.playersReady, currentPlayer)
				end
				
				local notOnQuest = strfind(line.leftText, QUEST_PROGRESS_TOOLTIP_NOT_ON_QUEST, 1, true)
				if not notOnQuest then
					tinsert(processed.playersOnQuest, currentPlayer)
				end
			end
		end
	end
	return processed
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