function widget:GetInfo()
	return {
		name = "Chili Card Cheats",
		desc = "Cheats-only panel for instantly granting cards",
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
local ComboBox
local screen0

local window
local globalButton
local cardPicker
local allyTeamPicker
local descriptionBox
local categoryLabel
local statusLabel
local previewImage

local allyTeamItems = {}
local allyTeamByItem = {}
local cardItems = {}
local cardByItem = {}

local function IsCheatsVisible()
	return Spring.IsCheatingEnabled()
end

local function EnsureGlobalButton()
	if globalButton or not WG.GlobalCommandBar then
		return
	end

	globalButton = WG.GlobalCommandBar.AddCommand(
		"LuaUI/Images/commands/Bold/repeat.png",
		"Toggle card cheats",
		function()
			if window then
				window:SetVisibility(not window.visible)
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

local function BuildCardItems()
	for i = 1, #cardData.defs do
		local cardDef = cardData.defs[i]
		cardItems[i] = string.format("%s | %03d | %s", CATEGORY_NAME[cardDef.category] or "Unknown", cardDef.id, cardDef.name)
		cardByItem[i] = cardDef.id
	end
end

local function GetAllyTeamLabel(allyTeamID)
	local teamList = Spring.GetTeamList(allyTeamID) or {}
	local names = {}

	for i = 1, #teamList do
		local teamID = teamList[i]
		if teamID ~= Spring.GetGaiaTeamID() then
			local _, leaderID, _, isAI = Spring.GetTeamInfo(teamID, false)
			if isAI then
				local _, aiName, _, shortName = Spring.GetAIInfo(teamID)
				names[#names + 1] = shortName or aiName or ("AI " .. teamID)
			else
				names[#names + 1] = Spring.GetPlayerInfo(leaderID, false) or ("Team " .. teamID)
			end
		end
	end

	if #names == 0 then
		return string.format("Ally %d", allyTeamID)
	end

	return string.format("Ally %d | %s", allyTeamID, table.concat(names, ", "))
end

local function RefreshAllyTeamItems()
	local allyTeams = Spring.GetAllyTeamList() or {}
	local gaiaAllyTeamID = select(6, Spring.GetTeamInfo(Spring.GetGaiaTeamID(), false))
	local selectedAllyTeamID = allyTeamPicker and allyTeamByItem[allyTeamPicker.selected] or Spring.GetMyAllyTeamID()

	allyTeamItems = {}
	allyTeamByItem = {}

	for i = 1, #allyTeams do
		local allyTeamID = allyTeams[i]
		if allyTeamID ~= gaiaAllyTeamID then
			allyTeamItems[#allyTeamItems + 1] = GetAllyTeamLabel(allyTeamID)
			allyTeamByItem[#allyTeamItems] = allyTeamID
		end
	end

	if not allyTeamPicker then
		return
	end

	allyTeamPicker.items = allyTeamItems
	allyTeamPicker:Invalidate()

	local selectedIndex = 1
	for i = 1, #allyTeamByItem do
		if allyTeamByItem[i] == selectedAllyTeamID then
			selectedIndex = i
			break
		end
	end
	allyTeamPicker:Select(selectedIndex)
end

local function UpdateCardPreview()
	if not (cardPicker and previewImage and categoryLabel and descriptionBox) then
		return
	end

	local cardID = cardByItem[cardPicker.selected]
	local cardDef = cardID and cardData.byID[cardID]
	if not cardDef then
		return
	end

	previewImage.file = cardDef.image
	previewImage:Invalidate()
	categoryLabel:SetCaption(string.format("%s Card", CATEGORY_NAME[cardDef.category] or "Unknown"))
	descriptionBox:SetText(cardDef.description)
end

local function CenterWindow()
	if not (window and screen0) then
		return
	end
	window:SetPos(math.floor((screen0.width - window.width) / 2), math.floor((screen0.height - window.height) / 2))
end

local function GrantSelectedCard()
	local cardID = cardByItem[cardPicker and cardPicker.selected]
	local allyTeamID = allyTeamByItem[allyTeamPicker and allyTeamPicker.selected]
	local cardDef = cardID and cardData.byID[cardID]

	if not (cardDef and allyTeamID) then
		if statusLabel then
			statusLabel:SetCaption("Select a valid card and allyteam.")
		end
		return
	end

	Spring.SendLuaRulesMsg(string.format("%s:grant:%d:%d", PREFIX, allyTeamID, cardID))
	statusLabel:SetCaption(string.format("Granted %s to allyteam %d.", cardDef.name, allyTeamID))
end

local function InitializeWindow()
	if window then
		return
	end

	window = Window:New{
		name = "zk_card_cheats_window",
		width = 520,
		height = 300,
		parent = screen0,
		dockable = false,
		draggable = true,
		resizable = false,
		tweakDraggable = true,
		tweakResizable = true,
		classname = "main_window_small",
		padding = {14, 14, 14, 14},
	}

	Label:New{
		x = 16,
		y = 12,
		right = 16,
		height = 24,
		fontsize = 20,
		caption = "Card Cheats",
		parent = window,
	}

	TextBox:New{
		x = 16,
		y = 40,
		right = 16,
		height = 30,
		objectOverrideFont = GetSpecialFont(14, {0.88, 0.88, 0.88, 1}),
		text = "Grant any card immediately to any allyteam while cheats are enabled.",
		parent = window,
	}

	Label:New{
		x = 16,
		y = 82,
		width = 80,
		height = 20,
		fontsize = 14,
		caption = "Card",
		parent = window,
	}

	cardPicker = ComboBox:New{
		x = 16,
		y = 104,
		width = 300,
		height = 28,
		items = cardItems,
		selected = 1,
		parent = window,
		OnSelect = {
			function()
				UpdateCardPreview()
			end,
		},
	}

	Label:New{
		x = 16,
		y = 142,
		width = 80,
		height = 20,
		fontsize = 14,
		caption = "Allyteam",
		parent = window,
	}

	allyTeamPicker = ComboBox:New{
		x = 16,
		y = 164,
		width = 300,
		height = 28,
		items = {"Ally 0"},
		selected = 1,
		parent = window,
	}

	local previewPanel = Panel:New{
		x = 332,
		y = 82,
		right = 16,
		height = 154,
		padding = {10, 10, 10, 10},
		parent = window,
	}

	previewImage = Image:New{
		x = 0,
		y = 0,
		width = 48,
		height = 48,
		parent = previewPanel,
	}

	categoryLabel = Label:New{
		x = 60,
		y = 0,
		right = 0,
		height = 22,
		fontsize = 15,
		caption = "",
		parent = previewPanel,
	}

	descriptionBox = TextBox:New{
		x = 0,
		y = 58,
		right = 0,
		bottom = 0,
		objectOverrideFont = GetSpecialFont(13, {0.88, 0.88, 0.88, 1}),
		text = "",
		parent = previewPanel,
	}

	Button:New{
		x = 16,
		bottom = 18,
		width = 140,
		height = 34,
		caption = "Grant Card",
		parent = window,
		OnClick = {
			function()
				GrantSelectedCard()
			end,
		},
	}

	statusLabel = Label:New{
		x = 168,
		bottom = 22,
		right = 16,
		height = 24,
		fontsize = 13,
		caption = "",
		parent = window,
	}

	window:SetVisibility(false)
	window.OnResize = {
		function()
			CenterWindow()
		end
	}

	RefreshAllyTeamItems()
	UpdateCardPreview()
	CenterWindow()
end

local function RefreshVisibility()
	EnsureGlobalButton()
	if not Chili then
		return
	end

	local visible = IsCheatsVisible()
	if globalButton then
		globalButton:SetVisibility(visible)
	end
	if not visible then
		if window then
			window:SetVisibility(false)
		end
		return
	end

	InitializeWindow()
	RefreshAllyTeamItems()
	UpdateCardPreview()
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
	ComboBox = Chili.ComboBox
	screen0 = Chili.Screen0

	BuildCardItems()
	RefreshVisibility()
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
	if frame % 15 ~= 0 then
		return
	end
	RefreshVisibility()
end

function widget:PlayerChanged(playerID)
	if playerID == Spring.GetMyPlayerID() then
		RefreshVisibility()
	end
end

function widget:ViewResize()
	CenterWindow()
end
