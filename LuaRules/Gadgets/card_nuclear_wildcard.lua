function gadget:GetInfo()
	return {
		name = "Card Effect - Nuclear Wildcard",
		desc = "Applies the Nuclear Wildcard card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 108
local STOCKPILE_TIME_SECONDS = 30

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGroundHeight = Spring.GetGroundHeight
local spGetTeamInfo = Spring.GetTeamInfo
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam

local CMD_ATTACK = CMD.ATTACK

local gaiaAllyTeam
local trinityDefID = UnitDefNames.staticnuke and UnitDefNames.staticnuke.id
local allyTeamActive = {}
local previousStockpileOverrideGet
local pendingOrders = {}
local issuingOrder = {}

local function GetTeamAllyTeam(teamID)
	return select(6, spGetTeamInfo(teamID, false))
end

local function UpdateCardActivation()
	if not (trinityDefID and GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
		end
	end
end

local function GetRandomTargetParams()
	local x = math.random() * Game.mapSizeX
	local z = math.random() * Game.mapSizeZ
	return {x, spGetGroundHeight(x, z), z}
end

function gadget:AllowCommand_GetWantedCommand()
	return {[CMD_ATTACK] = true}
end

function gadget:AllowCommand_GetWantedUnitDefID()
	return trinityDefID and {[trinityDefID] = true} or false
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)
	if cmdID ~= CMD_ATTACK or unitDefID ~= trinityDefID then
		return true
	end
	if issuingOrder[unitID] then
		return true
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if not allyTeamActive[allyTeamID] then
		return true
	end
	pendingOrders[#pendingOrders + 1] = {
		unitID = unitID,
		cmdID = CMD_ATTACK,
		params = GetRandomTargetParams(),
		options = cmdOptions,
	}
	return false
end

function gadget:GameFrame()
	UpdateCardActivation()

	for i = 1, #pendingOrders do
		local order = pendingOrders[i]
		issuingOrder[order.unitID] = true
		Spring.GiveOrderToUnit(order.unitID, order.cmdID, order.params, order.options)
		issuingOrder[order.unitID] = nil
		pendingOrders[i] = nil
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()

	previousStockpileOverrideGet = GG.StockpileOverride_Get
	GG.StockpileOverride_Get = function(unitID, unitDefID, teamID, baseDef)
		if previousStockpileOverrideGet then
			local override = previousStockpileOverrideGet(unitID, unitDefID, teamID, baseDef)
			if override then
				return override
			end
		end
		if unitDefID ~= trinityDefID then
			return nil
		end
		local allyTeamID = GetTeamAllyTeam(teamID)
		if not allyTeamActive[allyTeamID] then
			return nil
		end
		return {
			stockTime = STOCKPILE_TIME_SECONDS * Game.gameSpeed,
			stockCost = 0,
		}
	end
end

function gadget:Shutdown()
	if GG.StockpileOverride_Get == nil then
		return
	end
	GG.StockpileOverride_Get = previousStockpileOverrideGet
end
