function widget:GetInfo()
	return {
		name = "Chili Picked Cards",
		desc = "Shows the cards already picked by your side",
		author = "Codex",
		layer = -9,
		enabled = true,
	}
end

local constants = VFS.Include("LuaRules/Configs/Cards/card_constants.lua")
local cardData = VFS.Include("LuaRules/Configs/Cards/card_defs.lua")

local PREFIX = constants.PREFIX

local Chili
local Window
local Label
local TextBox
local screen0

local window
local toggleButton
local bodyText
local emptyLabel
local lastRenderedText
local expanded = true
local expandedHeight = PANEL_HEIGHT

local PANEL_X = 0
local PANEL_Y = 50
local PANEL_WIDTH = 280
local PANEL_HEIGHT = 180
local COLLAPSED_HEIGHT = 44

local function IsSpectator()
	return Spring.GetSpectatingState()
end

local function GetMyTeamID()
	return Spring.GetMyTeamID()
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

local function EnsureWindow()
	if window then
		return
	end

	window = Window:New{
		name = "zk_picked_cards_window",
		x = PANEL_X,
		y = PANEL_Y,
		width = PANEL_WIDTH,
		height = PANEL_HEIGHT,
		minWidth = PANEL_WIDTH,
		minHeight = 110,
		dockable = true,
		dockableSavePositionOnly = true,
		draggable = false,
		resizable = true,
		tweakDraggable = true,
		tweakResizable = true,
		classname = "main_window_small",
		parent = screen0,
		parentWidgetName = widget:GetInfo().name,
		padding = {10, 10, 10, 10},
	}

	Label:New{
		x = 8,
		y = 8,
		right = 8,
		height = 22,
		fontsize = 16,
		caption = "Picked Cards",
		parent = window,
	}

	toggleButton = Chili.Button:New{
		right = 8,
		y = 6,
		width = 28,
		height = 24,
		caption = "-",
		parent = window,
	}

	emptyLabel = Label:New{
		x = 8,
		y = 34,
		right = 8,
		height = 22,
		fontsize = 13,
		caption = "No cards picked yet.",
		parent = window,
	}

	bodyText = TextBox:New{
		x = 8,
		y = 34,
		right = 8,
		bottom = 8,
		padding = {0, 0, 0, 0},
		font = GetSpecialFont(13, {0.90, 0.90, 0.90, 1}),
		text = "",
		parent = window,
	}

	local function ApplyCollapsedState()
		if expanded then
			window.height = math.max(expandedHeight or PANEL_HEIGHT, PANEL_HEIGHT)
			window.minHeight = 110
			toggleButton:SetCaption("-")
			emptyLabel:SetVisibility(true)
			bodyText:SetVisibility(true)
		else
			expandedHeight = math.max(window.height, PANEL_HEIGHT)
			window.height = COLLAPSED_HEIGHT
			window.minHeight = COLLAPSED_HEIGHT
			toggleButton:SetCaption("+")
			emptyLabel:SetVisibility(false)
			bodyText:SetVisibility(false)
		end
		window:UpdateClientArea()
		window:Invalidate()
	end

	toggleButton.OnClick[1] = function()
		expanded = not expanded
		ApplyCollapsedState()
	end

	window.OnResize = {
		function(self)
			if expanded then
				expandedHeight = math.max(self.height, PANEL_HEIGHT)
			end
		end
	}

	ApplyCollapsedState()
end

local function HideWindow()
	if window then
		window:SetVisibility(false)
	end
end

local function Refresh()
	if not Chili then
		return
	end

	local teamID = GetMyTeamID()
	if IsSpectator() or not teamID then
		HideWindow()
		return
	end

	EnsureWindow()
	window:SetVisibility(true)
	if not expanded then
		return
	end

	local appliedCount = Spring.GetTeamRulesParam(teamID, PREFIX .. "_applied_count") or 0
	if appliedCount <= 0 then
		bodyText:SetText("")
		emptyLabel:SetCaption("No cards picked yet.")
		lastRenderedText = ""
		return
	end

	local lines = {}
	for i = 1, appliedCount do
		local cardID = Spring.GetTeamRulesParam(teamID, PREFIX .. "_applied_" .. i .. "_id")
		local cardDef = cardID and cardData.byID[cardID]
		if cardDef then
			local shortText = cardDef.shortDescription or cardDef.description or ""
			lines[#lines + 1] = string.format("%d. %s\n%s", i, cardDef.name, shortText)
		end
	end

	local renderedText = table.concat(lines, "\n")
	if renderedText ~= lastRenderedText then
		bodyText:SetText(renderedText)
		lastRenderedText = renderedText
	end
	emptyLabel:SetCaption("")
end

function widget:Initialize()
	Chili = WG.Chili
	if not Chili then
		widgetHandler:RemoveWidget()
		return
	end

	Window = Chili.Window
	Label = Chili.Label
	TextBox = Chili.TextBox
	screen0 = Chili.Screen0

	Refresh()
end

function widget:Shutdown()
	if window then
		window:Dispose()
		window = nil
	end
end

function widget:GameFrame(frame)
	if frame % 15 ~= 0 then
		return
	end
	Refresh()
end

function widget:PlayerChanged(playerID)
	if playerID == Spring.GetMyPlayerID() then
		Refresh()
	end
end
