function gadget:GetInfo()
	return {
		name = "Card Effect - Rapid Deployment",
		desc = "Applies the Rapid Deployment card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 105
local BUILD_MULT = 3
local DISARM_FRAMES = 20 * Game.gameSpeed
local EFFECT_KEY_PREFIX = "zk_cards_rapid_deployment_"

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitTeam = Spring.GetUnitTeam

local gaiaAllyTeam
local allyTeamActive = {}
local trackedFactories = {}
local factoryLikeDefs = {}

local function IsFactoryLike(unitDef)
	local cp = unitDef and unitDef.customParams or {}
	return unitDef and unitDef.isBuilder and unitDef.buildOptions and #unitDef.buildOptions > 0
		and (unitDef.isFactory or cp.child_of_factory or cp.factorytab)
end

for unitDefID = 1, #UnitDefs do
	if IsFactoryLike(UnitDefs[unitDefID]) then
		factoryLikeDefs[unitDefID] = true
	end
end

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function ApplyFactoryBuff(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			build = BUILD_MULT,
			static = true,
		})
	end
end

local function RemoveFactoryBuff(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
end

local function TrackFactory(unitID, unitDefID, teamID)
	if not factoryLikeDefs[unitDefID] then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedFactories[unitID] = allyTeamID
	if allyTeamActive[allyTeamID] then
		ApplyFactoryBuff(unitID)
	else
		RemoveFactoryBuff(unitID)
	end
end

local function UntrackFactory(unitID)
	RemoveFactoryBuff(unitID)
	trackedFactories[unitID] = nil
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID and factoryLikeDefs[unitDefID] then
				TrackFactory(unitID, unitDefID, teamID)
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

local function DisarmUnit(unitID)
	if not GG.addParalysisDamageToUnit then
		return
	end
	local _, maxHealth = spGetUnitHealth(unitID)
	if maxHealth and maxHealth > 0 then
		GG.addParalysisDamageToUnit(unitID, maxHealth * 2, DISARM_FRAMES, 0, nil)
	end
end

function gadget:UnitFromFactory(unitID, unitDefID, unitTeam, factID, factDefID)
	if not UnitDefs[unitDefID] or UnitDefs[unitDefID].isImmobile then
		return
	end
	local allyTeamID = GetTeamAllyTeam(unitTeam)
	if not allyTeamID or not allyTeamActive[allyTeamID] then
		return
	end
	if not factDefID then
		factDefID = spGetUnitDefID(factID)
	end
	if not (factDefID and factoryLikeDefs[factDefID]) then
		return
	end
	DisarmUnit(unitID)
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackFactory(unitID, unitDefID, teamID)
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	TrackFactory(unitID, unitDefID, teamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	TrackFactory(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	TrackFactory(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitDestroyed(unitID)
	UntrackFactory(unitID)
end

function gadget:GameFrame(frame)
	if frame % 30 == 0 then
		UpdateCardActivation()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
