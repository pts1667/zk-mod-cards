function widget:GetInfo()
	return {
		name = "Chili Card Draft",
		desc = "Displays the active side card draft and sends vote selections",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

local constants = VFS.Include("LuaRules/Configs/Cards/card_constants.lua")
local cardData = VFS.Include("LuaRules/Configs/Cards/card_defs.lua")

local PREFIX = constants.PREFIX
local CATEGORY_NAME = constants.CATEGORY_NAME

local Chili
local Window
local Panel
local Button
local Label
local TextBox
local Image
local screen0

local WINDOW_WIDTH = 1140
local WINDOW_HEIGHT_EXPANDED = 520
local CARD_AREA_LEFT = 16
local CARD_AREA_TOP = 88
local CARD_AREA_HEIGHT = 300
local CARD_GAP = 16
local HISTORY_PANEL_WIDTH = 180
local HISTORY_PANEL_RIGHT = 16

local window
local headerLabel
local timerLabel
local subtitleLabel
local historyLabel
local emptyHistoryLabel
local globalButton
local collapseButton
local historyPanel

local cardControls = {}
local visibleStageSeq
local isMinimized = false
local CenterWindow

local function IsSpectator()
	return Spring.GetSpectatingState()
end

local function GetMyTeamID()
	return Spring.GetMyTeamID()
end

local function GetMyPlayerID()
	return Spring.GetMyPlayerID()
end

local function EnsureGlobalButton()
	if globalButton or not WG.GlobalCommandBar then
		return
	end
	globalButton = WG.GlobalCommandBar.AddCommand(
		"LuaUI/Images/metalplus.png",
		"Toggle the active card draft window",
		function()
			isMinimized = not isMinimized
			if window then
				window:SetVisibility(not isMinimized)
				if window.visible then
					window:BringToFront()
				end
			end
		end
	)
	globalButton:SetVisibility(false)
end

local function GetSpecialFont(size, color)
	if WG.GetSpecialFont then
		return WG.GetSpecialFont(size, "internal_white", {
			outlineColor = {0, 0, 0, 1},
			color = color or {1, 1, 1, 1},
		})
	end
	return nil
end

local function HideWindow()
	if window then
		window:SetVisibility(false)
	end
	if globalButton then
		globalButton:SetVisibility(false)
	end
	visibleStageSeq = nil
end

local function UpdateMinimizedState()
	if not window then
		return
	end

	if collapseButton then
		collapseButton:SetCaption(isMinimized and "+" or "-")
	end
	window:SetVisibility(not isMinimized)
end

local function FormatSeconds(frameDelta)
	local seconds = math.max(0, math.ceil(frameDelta / constants.GAME_SPEED))
	local minutesPart = math.floor(seconds / 60)
	local secondsPart = seconds % 60
	return string.format("%d:%02d", minutesPart, secondsPart)
end

local function SendVote(slot, stageSeq)
	Spring.SendLuaRulesMsg(string.format("%s:vote:%d:%d", PREFIX, stageSeq, slot))
	isMinimized = true
	UpdateMinimizedState()
end

local function UpdateCardButton(cardControl, cardID, slot, stageSeq, voteCount, selectedSlot)
	local cardDef = cardData.byID[cardID]
	if not cardDef then
		cardControl.button:SetVisibility(false)
		return
	end

	cardControl.button:SetVisibility(true)
	cardControl.button.OnClick[1] = function()
		SendVote(slot, stageSeq)
	end
	cardControl.button.backgroundColor = (selectedSlot == slot) and {0.98, 0.54, 0.20, 0.92} or {0.18, 0.18, 0.20, 0.92}
	cardControl.button.focusColor = (selectedSlot == slot) and {1, 0.62, 0.24, 0.95} or {0.28, 0.28, 0.32, 0.95}
	cardControl.button.borderColor = (selectedSlot == slot) and {1, 0.72, 0.36, 1} or {0.48, 0.48, 0.54, 1}
	cardControl.button.tooltip = cardDef.description
	cardControl.button:Invalidate()

	cardControl.image.file = cardDef.image
	cardControl.image:Invalidate()
	cardControl.title:SetText(cardDef.name)
	cardControl.body:SetText(cardDef.description)
	cardControl.footer:SetCaption(string.format("Option %d  |  Votes: %d", slot, voteCount or 0))
end

local function UpdateHistory(teamID)
	local appliedCount = Spring.GetTeamRulesParam(teamID, PREFIX .. "_applied_count") or 0
	if appliedCount <= 0 then
		historyLabel:SetText("")
		emptyHistoryLabel:SetCaption("No cards applied yet.")
		return
	end

	local lines = {}
	for i = 1, appliedCount do
		local cardID = Spring.GetTeamRulesParam(teamID, PREFIX .. "_applied_" .. i .. "_id")
		local cardDef = cardID and cardData.byID[cardID]
		if cardDef then
			lines[#lines + 1] = string.format("%d. %s", i, cardDef.name)
		end
	end
	historyLabel:SetText(table.concat(lines, "\n"))
	emptyHistoryLabel:SetCaption("")
end

function CenterWindow()
	if not (window and screen0) then
		return
	end
	window:SetPos(math.floor((screen0.width - window.width) / 2), math.floor((screen0.height - window.height) / 2))
end

local function CreateCardControl(parent, leftPos)
	local button = Button:New{
		x = leftPos,
		y = CARD_AREA_TOP,
		width = 280,
		height = CARD_AREA_HEIGHT,
		padding = {10, 10, 10, 10},
		caption = "",
		noFont = true,
		parent = parent,
	}

	local image = Image:New{
		x = 18,
		y = 16,
		width = 48,
		height = 48,
		parent = button,
	}

	local title = TextBox:New{
		x = 76,
		y = 16,
		right = 12,
		height = 54,
		objectOverrideFont = GetSpecialFont(18, {1, 1, 1, 1}),
		text = "",
		parent = button,
	}

	local body = TextBox:New{
		x = 18,
		y = 84,
		right = 18,
		height = 154,
		objectOverrideFont = GetSpecialFont(14, {0.88, 0.88, 0.88, 1}),
		text = "",
		parent = button,
	}

	local footer = Label:New{
		x = 18,
		bottom = 18,
		right = 18,
		height = 24,
		fontsize = 14,
		caption = "",
		parent = button,
	}

	return {
		button = button,
		image = image,
		title = title,
		body = body,
		footer = footer,
	}
end

local function LayoutCardControls(offerCount)
	local count = math.max(1, math.min(constants.MAX_OFFERS_PER_DRAFT, offerCount or constants.OFFERS_PER_DRAFT))
	local availableWidth = WINDOW_WIDTH - CARD_AREA_LEFT - HISTORY_PANEL_WIDTH - HISTORY_PANEL_RIGHT - 28
	local buttonWidth = math.floor((availableWidth - CARD_GAP * (count - 1)) / count)
	for slot = 1, #cardControls do
		local control = cardControls[slot]
		local visible = slot <= count
		control.button:SetVisibility(visible)
		if visible then
			control.button.x = CARD_AREA_LEFT + (slot - 1) * (buttonWidth + CARD_GAP)
			control.button.y = CARD_AREA_TOP
			control.button.width = buttonWidth
			control.button.height = CARD_AREA_HEIGHT
			control.button:UpdateClientArea()
			control.button:Invalidate()
		end
	end
end

local function InitializeWindow()
	if window then
		return
	end

	window = Window:New{
		name = "zk_card_draft_window",
		width = WINDOW_WIDTH,
		height = WINDOW_HEIGHT_EXPANDED,
		parent = screen0,
		dockable = false,
		draggable = false,
		resizable = false,
		tweakDraggable = true,
		tweakResizable = true,
		classname = "main_window_small",
		padding = {14, 14, 14, 14},
	}

	headerLabel = Label:New{
		x = 16,
		y = 12,
		right = 248,
		height = 26,
		fontsize = 22,
		caption = "Card Draft",
		parent = window,
	}

	timerLabel = Label:New{
		right = 56,
		y = 12,
		width = 180,
		height = 26,
		align = "right",
		fontsize = 22,
		caption = "0:00",
		parent = window,
	}

	collapseButton = Button:New{
		right = 16,
		y = 10,
		width = 28,
		height = 28,
		caption = "-",
		parent = window,
		OnClick = {
			function()
				isMinimized = not isMinimized
				UpdateMinimizedState()
				if window and window.visible then
					window:BringToFront()
				end
			end,
		},
	}

	subtitleLabel = TextBox:New{
		x = 16,
		y = 42,
		right = 220,
		height = 36,
		objectOverrideFont = GetSpecialFont(15, {0.88, 0.88, 0.88, 1}),
		text = "Pick one card for your side before the timer expires.",
		parent = window,
	}

	historyPanel = Panel:New{
		right = HISTORY_PANEL_RIGHT,
		y = 88,
		width = HISTORY_PANEL_WIDTH,
		bottom = 16,
		padding = {10, 10, 10, 10},
		parent = window,
	}

	Label:New{
		x = 0,
		y = 0,
		right = 0,
		height = 22,
		fontsize = 16,
		caption = "Applied This Match",
		parent = historyPanel,
	}

	emptyHistoryLabel = Label:New{
		x = 0,
		y = 30,
		right = 0,
		height = 24,
		fontsize = 13,
		caption = "No cards applied yet.",
		parent = historyPanel,
	}

	historyLabel = TextBox:New{
		x = 0,
		y = 28,
		right = 0,
		bottom = 0,
		objectOverrideFont = GetSpecialFont(13, {0.90, 0.90, 0.90, 1}),
		text = "",
		parent = historyPanel,
	}

	for slot = 1, constants.MAX_OFFERS_PER_DRAFT do
		cardControls[slot] = CreateCardControl(window, CARD_AREA_LEFT)
	end
	LayoutCardControls(constants.OFFERS_PER_DRAFT)

	window:SetVisibility(false)
	window.OnResize = {
		function()
			CenterWindow()
		end
	}
	UpdateMinimizedState()
	CenterWindow()
end

local function RefreshUI(forceOpen)
	EnsureGlobalButton()
	if not Chili then
		return
	end

	local teamID = GetMyTeamID()

	if IsSpectator() or not teamID then
		HideWindow()
		return
	end

	local isActive = Spring.GetTeamRulesParam(teamID, PREFIX .. "_active") == 1
	local stageSeq = Spring.GetTeamRulesParam(teamID, PREFIX .. "_stage_seq") or Spring.GetGameRulesParam(PREFIX .. "_stage_seq") or 0

	if not isActive then
		HideWindow()
		if window then
			UpdateHistory(teamID)
		end
		return
	end

	InitializeWindow()
	if globalButton then
		globalButton:SetVisibility(true)
	end

	local categoryID = Spring.GetTeamRulesParam(teamID, PREFIX .. "_stage_category") or Spring.GetGameRulesParam(PREFIX .. "_stage_category") or 0
	local closeFrame = Spring.GetTeamRulesParam(teamID, PREFIX .. "_close_frame") or Spring.GetGameRulesParam(PREFIX .. "_stage_close_frame") or 0
	local offerCount = Spring.GetTeamRulesParam(teamID, PREFIX .. "_offer_count") or constants.OFFERS_PER_DRAFT
	local currentFrame = Spring.GetGameFrame()
	local selectedStageSeq = Spring.GetPlayerRulesParam(GetMyPlayerID(), PREFIX .. "_vote_stage_seq")
	local selectedSlot = 0
	if selectedStageSeq == stageSeq then
		selectedSlot = Spring.GetPlayerRulesParam(GetMyPlayerID(), PREFIX .. "_vote_slot") or 0
	end

	headerLabel:SetCaption(string.format("%s Cards", CATEGORY_NAME[categoryID] or "Unknown"))
	timerLabel:SetCaption(FormatSeconds(closeFrame - currentFrame))
	subtitleLabel:SetText(string.format("Vote for one of %d cards. Highest votes win; ties are broken randomly.", offerCount))
	LayoutCardControls(offerCount)

	for slot = 1, #cardControls do
		local cardID = Spring.GetTeamRulesParam(teamID, PREFIX .. "_offer_" .. slot .. "_id") or 0
		local voteCount = Spring.GetTeamRulesParam(teamID, PREFIX .. "_offer_" .. slot .. "_votes") or 0
		UpdateCardButton(cardControls[slot], cardID, slot, stageSeq, voteCount, selectedSlot)
	end

	UpdateHistory(teamID)
	if forceOpen or visibleStageSeq ~= stageSeq then
		isMinimized = false
		UpdateMinimizedState()
		window:BringToFront()
		visibleStageSeq = stageSeq
	else
		UpdateMinimizedState()
	end
end

function widget:Initialize()
	Chili = WG.Chili
	if not Chili then
		widgetHandler:RemoveWidget()
		return
	end

	Window = Chili.Window
	Panel = Chili.Panel
	Button = Chili.Button
	Label = Chili.Label
	TextBox = Chili.TextBox
	Image = Chili.Image
	screen0 = Chili.Screen0

	EnsureGlobalButton()
	RefreshUI(true)
end

function widget:Shutdown()
	if window then
		window:Dispose()
		window = nil
	end
	if globalButton then
		globalButton:SetVisibility(false)
	end
end

function widget:GameFrame(frame)
	if frame % 10 ~= 0 then
		return
	end
	RefreshUI(false)
end

function widget:PlayerChanged(playerID)
	if playerID == GetMyPlayerID() then
		RefreshUI(true)
	end
end

function widget:ViewResize()
	CenterWindow()
end
