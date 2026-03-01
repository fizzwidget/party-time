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
	local default, min, max, step = 1.0, 0.25, 2.0, 0.05
	settings:Slider("FrameSize", default, min, max, step, FormatPercentage)
	settings:Checkbox("ShowSelf", true)
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

T.QuestCompletions = {}

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
			-- print(action, questID)
			T.TrackedQuests[questID] = true
		elseif action == "REMOVE" then
			-- print(action, questID)
			T.TrackedQuests[questID] = nil
		elseif action == "COMPLETE" then
			-- print(action, questID)
			
			-- TODO should we be counting messages, or tracking who we have messages from?
			T.QuestCompletions[questID] = (T.QuestCompletions[questID] or 0) + 1
			local units = {"player", "party1", "party2", "party3", "party4"}
			local partyMembers = 0
			for _, unit in pairs(units) do
				if not UnitExists(unit) then
					break
				elseif UnitIsConnected(unit) then
					partyMembers = partyMembers + 1
				end
			end
			if T.QuestCompletions[questID] >= partyMembers then
				T.QuestCompletions[questID] = nil
				T.TrackedQuests[questID] = nil
				C_ChatInfo.SendAddonMessage(addonName, "Q|REMOVE "..questID, "PARTY")
			end
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
	elseif text == "done" then
		local remove, onlyComplete = true, true
		T.PushAllPartyQuests(remove, onlyComplete)
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
	elseif strsub(text, 1, strlen("testcomplete")) == "testcomplete" then
		-- quick grab first quest ID from the list for testing
		local questID
		for id in pairs(T.TrackedQuests) do
			questID = id
			break
		end
		C_ChatInfo.SendAddonMessage(addonName, "Q|COMPLETE "..questID, "PARTY")

	elseif text == "" then
		DevTools_Dump(T.TrackedQuests)
		T.ShowFrame()
	end
end

local function questLogMenu(owner, rootDescription, contextData)
	local questID = owner.questID or T.ClickedQuestID
	local function IsSelected()
		return T.TrackedQuests[questID]
	end
	local function SetSelected()
		if T.TrackedQuests[questID] then
			T.TrackedQuests[questID] = nil
			C_ChatInfo.SendAddonMessage(addonName, "Q|REMOVE "..questID, "PARTY")
		else
			T.TrackedQuests[questID] = true
			C_ChatInfo.SendAddonMessage(addonName, "Q|ADD "..questID, "PARTY")
		end
	end
	rootDescription:CreateDivider();
	rootDescription:CreateTitle("PartyTime");
	rootDescription:CreateCheckbox("Party Quest", IsSelected, SetSelected)
end
Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", questLogMenu)
Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", questLogMenu)

-- ugly hack because MENU_QUEST_OBJECTIVE_TRACKER loses its questID context
local function setClickedQuest(self, block)
	T.ClickedQuestID = block.id
end
local function clearClickedQuest(self, block)
	T.ClickedQuestID = nil
end
hooksecurefunc(QuestObjectiveTracker, "OnBlockHeaderEnter", setClickedQuest)
hooksecurefunc(CampaignQuestObjectiveTracker, "OnBlockHeaderEnter", setClickedQuest)
hooksecurefunc(QuestObjectiveTracker, "OnBlockHeaderLeave", clearClickedQuest)
hooksecurefunc(CampaignQuestObjectiveTracker, "OnBlockHeaderLeave", clearClickedQuest)


function T.MakeFrame()
	T.Frame = CreateFrame("GameTooltip", addonName.."_Tooltip", UIParent, "GameTooltipTemplate")
	T.Frame:SetOwner(UIParent, "ANCHOR_PRESERVE")

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
		T.FrameUpdateTimer = nil
		return
	end
	T.ShowFrame()
end


function T.ShowFrame()
	if not T.Frame then
		T.MakeFrame()
	end
	local settings = _G[addonName .. "_Settings"]

	-- setting to include self in list
	local units = {"party1", "party2", "party3", "party4"}
	if settings and settings.ShowSelf then
		tinsert(units, 1, "player")
	end
	
	GameTooltip_SetTitle(T.Frame, "Party Quests", NORMAL_FONT_COLOR, false)
	T.Frame:SetMinimumWidth(T.Frame.TextLeft1:GetWidth() + 2 + T.Frame.CloseButton:GetWidth())
	
	-- order dependency: this runs before Settings.lua
	-- TODO same default value in multiple places is sad
	local frameSize = settings and settings.FrameSize or 1.0 
	T.Frame:SetScale(frameSize)

	for id in pairs(T.TrackedQuests) do
		-- different color for on quest, not on quest, previously completed quest
		local questTitle = C_QuestLog.GetTitleForQuestID(id)
		local questTitleColor
		if C_QuestLog.IsOnQuest(id) then
			questTitleColor = NORMAL_FONT_COLOR
		elseif C_QuestLog.IsQuestFlaggedCompleted(id) then
			questTitleColor = GRAY_FONT_COLOR
		else
			questTitleColor = RED_FONT_COLOR
		end
				
		local data = ProcessPartyProgress(id)
		if not data then
			-- always title (only) if not on quest
			GameTooltip_AddColoredLine(T.Frame, questTitle, questTitleColor, false)
		else
			
			-- prep list of members w/ on quest, not on quest, ready for turnin status
			local membersOnQuest = {}
			local membersWithoutQuest = {}
			for _, unit in pairs(units) do
				local unitName = UnitName(unit)
				if UnitIsPlayer(unit) then
					if not UnitIsVisible(unitName) then
						tinsert(membersOnQuest, ORANGE_FONT_COLOR:WrapTextInColorCode(UnitName(unit)))
						tinsert(membersWithoutQuest, ORANGE_FONT_COLOR:WrapTextInColorCode(UnitName(unit)))
					elseif data.playersReady[unitName] then
						tinsert(membersOnQuest, GREEN_FONT_COLOR:WrapTextInColorCode(UnitName(unit)))
					elseif data.playersOnQuest[unitName] then
						tinsert(membersOnQuest, WHITE_FONT_COLOR:WrapTextInColorCode(unitName))
					else
						tinsert(membersOnQuest, RED_FONT_COLOR:WrapTextInColorCode(unitName))
						tinsert(membersWithoutQuest, unitName)
					end
				end
			end
			
			local function hasObjectives(data)
				for objective in pairs(data.objectives) do
					return true
				end
			end
			if not hasObjectives(data) then
				-- separate lines for title and party status
				GameTooltip_AddColoredLine(T.Frame, questTitle, questTitleColor, false)
				GameTooltip_AddHighlightLine(T.Frame, table.concat(membersOnQuest, " "), false, 7.5)
			else
				-- combined line for title and missing members
				local missingMembersText = table.concat(membersWithoutQuest, " ")
				GameTooltip_AddColoredDoubleLine(T.Frame, questTitle, missingMembersText, questTitleColor, RED_FONT_COLOR)
			end
				
			for objective, status in pairs(data.objectives) do
				local summary = {}
				for player, counts in pairs(status) do 
					local info = ("%s %d/%d"):format(player, counts[1], counts[2])
					tinsert(summary, info)
				end
				--print(" ", objective, ":", table.concat(summary, ", "))
				GameTooltip_AddColoredLine(T.Frame, objective, LIGHTYELLOW_FONT_COLOR, false, 7.5)
				GameTooltip_AddHighlightLine(T.Frame, table.concat(summary, " "), false, 15)
			end
		end
	end
	
	if T.FrameUpdateTimer then
		T.FrameUpdateTimer:Cancel()
		T.FrameUpdateTimer = nil
	end
	T.FrameUpdateTimer = C_Timer.NewTimer(1.0, T.UpdateFrame)
	
	T.Frame:Show()
end

local LINE_TYPE_PLAYER = 18
local LINE_TYPE_OBJECTIVE = 8

function ProcessPartyProgress(questID)
	local settings = _G[addonName .. "_Settings"]
	
	local omitTitle = true
	local ignoreActivePlayer = not (settings and settings.ShowSelf)
	local data = C_TooltipInfo.GetQuestPartyProgress(questID, omitTitle, ignoreActivePlayer)
	
	if not data then return nil end
	
	local processed = {}
	processed.playersOnQuest = {}
	processed.playersReady = {}
	processed.objectives = {}
	
	-- if no party, no LINE_TYPE_PLAYER lines in tooltip data
	local currentPlayer = UnitName("player") 
	
	for key, line in pairs(data.lines) do
		if type(key) == "number" then 
			if line.type == LINE_TYPE_PLAYER then
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
					processed.playersReady[currentPlayer] = true
				end
				
				local notOnQuest = strfind(line.leftText, QUEST_PROGRESS_TOOLTIP_NOT_ON_QUEST, 1, true)
				if not notOnQuest then
					processed.playersOnQuest[currentPlayer] = true
				end
			end
		end
	end
	return processed
end

function T.PushPartyQuest(questID, remove)
	if remove then
		C_ChatInfo.SendAddonMessage(addonName, "Q|REMOVE "..questID, "PARTY")
	else
		C_ChatInfo.SendAddonMessage(addonName, "Q|ADD "..questID, "PARTY")
	end
end

function T.PushAllPartyQuests(remove, onlyComplete)
	for id in pairs(T.TrackedQuests) do
		if remove and onlyComplete then
			if  C_QuestLog.IsQuestFlaggedCompleted(id) then
				T.PushPartyQuest(id, remove)
			end
		else
			T.PushPartyQuest(id, remove)
		end
	end
end

function Events:QUEST_TURNED_IN(questID, xpReward, moneyReward)
	-- TODO for every quest, or only tracked ones?
	C_ChatInfo.SendAddonMessage(addonName, "Q|COMPLETE "..questID, "PARTY")
end

function Events:QUEST_DETAIL()
	if UnitInAnyGroup("player") then
		if not T.AcceptQuestCheckbox then
			T.AcceptQuestCheckbox = CreateFrame("CheckButton", nil, QuestFrameDetailPanel, "UICheckButtonTemplate") -- TODO actual template
			T.AcceptQuestCheckbox:SetPoint("LEFT", QuestFrameAcceptButton, "RIGHT", 2, -1)
			T.AcceptQuestCheckbox:SetSize(24, 24)
			T.AcceptQuestCheckbox.Text:SetText("Party Quest")
			T.AcceptQuestCheckbox:SetScript("OnClick", function(self)
				T.Settings.TrackOnAccept = self:GetChecked()
			end)
		end	
		T.AcceptQuestCheckbox:Show()
		T.AcceptQuestCheckbox:SetChecked(T.Settings.TrackOnAccept)
		T.AutoTrackQuestID = GetQuestID()
	elseif T.AcceptQuestCheckbox then
		T.AcceptQuestCheckbox:Hide()
	end
end

function Events:QUEST_ACCEPTED(questID)
	if T.Settings.TrackOnAccept and UnitInAnyGroup("player") and questID == T.AutoTrackQuestID then
		T.PushPartyQuest(questID)
		T.AutoTrackQuestID = nil
	end
end

if UnitInAnyGroup("player") then
	-- print("load")
	T.ShowFrame()
end

------------------------------------------------------
-- Save & restore target markers
------------------------------------------------------


local function MarkerFromIndex(index)
	return C_ChatInfo.ReplaceIconAndGroupExpressions(("{rt%d}"):format(index))
end

function T.TrySetRaidTarget(unit, index)
	if GetRaidTargetIndex(unit) == index then return end
	SetRaidTarget(unit, index)
end

function Events:GROUP_ROSTER_UPDATE()
	if UnitInAnyGroup("player") then
		-- print("GROUP_ROSTER_UPDATE")
		T.ShowFrame()
	else
		T.Frame:Hide()
	end
	T.PushAllPartyQuests()
end

-- save assigned marker whenever one is set on a unit
function T.SetRaidTarget(unit, index)
	if UnitIsPlayer(unit) and UnitPlayerOrPetInParty(unit) then
		if not CancelNextSave and T.Settings.RememberMenuMarkers then
			-- print("saving", MarkerFromIndex(index), "for", UnitName(unit))
			T.SavedPresets[UnitName(unit)] = index
		end
		CancelNextSave = false
	end
end
hooksecurefunc("SetRaidTarget", T.SetRaidTarget)

local menuActionButton = CreateFrame("Button", nil, nil, "InsecureActionButtonTemplate")
menuActionButton:SetAttribute("pressAndHoldAction", 1)
menuActionButton:RegisterForClicks("LeftButtonUp")
menuActionButton:SetPropagateMouseClicks(true)
menuActionButton:SetPropagateMouseMotion(true)
menuActionButton:Hide()

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
	
	local element = rootDescription:CreateButton("Apply Party Markers", function() end)
	element:HookOnEnter(function(frame)
		local macrotext = ""
		local units = {"player", "party1", "party2", "party3", "party4"}
		for _, unit in pairs(units) do
			local name = UnitName(unit)
			local index = T.SavedPresets[name]
			if index then
				macrotext = macrotext .. ("/tm [@%s] %d\n"):format(unit, index)
			end
		end
		menuActionButton:SetAttribute("type", "macro")
		menuActionButton:SetAttribute("typerelease", "macro")
		menuActionButton:SetAttribute("macrotext", macrotext)
		menuActionButton:SetParent(frame)
		menuActionButton:SetAllPoints(frame)
		menuActionButton:SetFrameStrata("TOOLTIP")
		menuActionButton:Show()
	end)
	element:HookOnLeave(function()
		menuActionButton:Hide()
		menuActionButton:SetParent(nil)
	end)

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