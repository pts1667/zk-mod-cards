function gadget:GetInfo()
	return {
		name = "Card Effect - Hardened Logistics",
		desc = "Applies the Hardened Logistics card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 207
local UPDATE_FRAMES = 30
local HEALTH_MULT = 1.5
local REPAIR_TIME_MULT = 0.5
local EFFECT_KEY_PREFIX = "zk_cards_hardened_logistics_"

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spSetUnitCosts = Spring.SetUnitCosts

local gaiaAllyTeam
local allyTeamActive = {}
local trackedStatics = {}

local function IsStatic(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef and unitDef.isImmobile and not (unitDef.customParams and unitDef.customParams.mobilebuilding) and true or false
end

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function ApplyStaticHealth(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			healthMult = HEALTH_MULT,
			static = true,
		})
	end
end

local function RemoveStaticHealth(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
end

local function SetRepairBuildTime(unitID, unitDefID, fastRepair)
	if not unitDefID then
		return
	end
	local baseBuildTime = UnitDefs[unitDefID].buildTime
	if not baseBuildTime then
		return
	end
	spSetUnitCosts(unitID, {
		buildTime = baseBuildTime * ((fastRepair and REPAIR_TIME_MULT) or 1),
	})
end

local function TrackStatic(unitID, unitDefID, teamID)
	if not IsStatic(unitDefID) then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedStatics[unitID] = {
		unitDefID = unitDefID,
		allyTeamID = allyTeamID,
	}
	if allyTeamActive[allyTeamID] then
		ApplyStaticHealth(unitID)
	else
		RemoveStaticHealth(unitID)
	end
end

local function UntrackStatic(unitID, data)
	RemoveStaticHealth(unitID)
	if data and data.unitDefID and not (GG.HasCombatRepairPenalty and GG.HasCombatRepairPenalty(unitID)) then
		SetRepairBuildTime(unitID, data.unitDefID, false)
	end
	trackedStatics[unitID] = nil
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID and IsStatic(unitDefID) then
				TrackStatic(unitID, unitDefID, teamID)
			end
		end
	end
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam and not allyTeamActive[allyTeamID] and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
			SweepAllyTeam(allyTeamID)
		end
	end
end

local function UpdateRepairRates()
	for unitID, data in pairs(trackedStatics) do
		local unitDefID = spGetUnitDefID(unitID)
		if not unitDefID or not IsStatic(unitDefID) then
			trackedStatics[unitID] = nil
			RemoveStaticHealth(unitID)
		else
			data.unitDefID = unitDefID
			local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
			if allyTeamActive[data.allyTeamID] and buildProgress == 1 and not (GG.HasCombatRepairPenalty and GG.HasCombatRepairPenalty(unitID)) then
				SetRepairBuildTime(unitID, unitDefID, true)
			elseif not (GG.HasCombatRepairPenalty and GG.HasCombatRepairPenalty(unitID)) then
				SetRepairBuildTime(unitID, unitDefID, false)
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackStatic(unitID, unitDefID, teamID)
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	TrackStatic(unitID, unitDefID, teamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	local data = trackedStatics[unitID]
	if data then
		UntrackStatic(unitID, data)
	end
	TrackStatic(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	local data = trackedStatics[unitID]
	if data then
		UntrackStatic(unitID, data)
	end
	TrackStatic(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitDestroyed(unitID)
	UntrackStatic(unitID, trackedStatics[unitID])
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		UpdateRepairRates()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
