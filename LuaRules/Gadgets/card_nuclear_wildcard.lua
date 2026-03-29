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
local COST_MULT = 0.5
local EFFECT_KEY_PREFIX = "zk_cards_nuclear_wildcard_"

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGroundHeight = Spring.GetGroundHeight
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam

local gaiaAllyTeam
local trinityDefID = UnitDefNames.staticnuke and UnitDefNames.staticnuke.id
local allyTeamActive = {}
local previousStockpileOverrideGet
local trackedTrinities = {}

local function GetTeamAllyTeam(teamID)
	return select(6, spGetTeamInfo(teamID, false))
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function UpdateCardActivation()
	if not (trinityDefID and GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam then
			allyTeamActive[allyTeamID] = GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) or false
		end
	end
end

local function ApplyTrinityBuff(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			cost = COST_MULT,
			static = true,
		})
	end
end

local function RemoveTrinityBuff(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
end

local function TrackTrinity(unitID, teamID)
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedTrinities[unitID] = allyTeamID
	if allyTeamActive[allyTeamID] then
		ApplyTrinityBuff(unitID)
	else
		RemoveTrinityBuff(unitID)
	end
end

local function UntrackTrinity(unitID)
	RemoveTrinityBuff(unitID)
	trackedTrinities[unitID] = nil
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			if spGetUnitDefID(unitID) == trinityDefID then
				TrackTrinity(unitID, teamID)
			end
		end
	end
end

local function GetRandomTargetParams()
	local x = math.random() * Game.mapSizeX
	local z = math.random() * Game.mapSizeZ
	return {x, spGetGroundHeight(x, z), z}
end

function gadget:ScriptFireWeapon(unitID, unitDefID, weaponNum)
	if unitDefID ~= trinityDefID then
		return
	end
	local teamID = spGetUnitTeam(unitID)
	local allyTeamID = teamID and GetTeamAllyTeam(teamID)
	if not allyTeamActive[allyTeamID] then
		return
	end

	local params = GetRandomTargetParams()
	Spring.SetUnitTarget(unitID, params[1], params[2], params[3], false, false, -1)
end

function gadget:GameFrame(frame)
	UpdateCardActivation()

	for unitID, allyTeamID in pairs(trackedTrinities) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if unitDefID ~= trinityDefID or not teamID then
			UntrackTrinity(unitID)
		else
			allyTeamID = GetTeamAllyTeam(teamID)
			trackedTrinities[unitID] = allyTeamID
			if allyTeamActive[allyTeamID] then
				ApplyTrinityBuff(unitID)
			else
				RemoveTrinityBuff(unitID)
			end
		end
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam and allyTeamActive[allyTeamID] then
			SweepAllyTeam(allyTeamID)
		end
	end

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

function gadget:UnitCreated(unitID, unitDefID, teamID)
	if unitDefID == trinityDefID then
		TrackTrinity(unitID, teamID)
	end
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	if unitDefID == trinityDefID then
		TrackTrinity(unitID, teamID)
	end
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	if (unitDefID or spGetUnitDefID(unitID)) == trinityDefID then
		TrackTrinity(unitID, newTeamID)
	end
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	if (unitDefID or spGetUnitDefID(unitID)) == trinityDefID then
		TrackTrinity(unitID, newTeamID)
	end
end

function gadget:UnitDestroyed(unitID)
	UntrackTrinity(unitID)
end

function gadget:Shutdown()
	if GG.StockpileOverride_Get == nil then
		for unitID in pairs(trackedTrinities) do
			UntrackTrinity(unitID)
		end
		return
	end
	GG.StockpileOverride_Get = previousStockpileOverrideGet
	for unitID in pairs(trackedTrinities) do
		UntrackTrinity(unitID)
	end
end
