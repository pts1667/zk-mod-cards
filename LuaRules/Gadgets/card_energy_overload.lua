function gadget:GetInfo()
	return {
		name = "Card Effect - Energy Overload",
		desc = "Applies the Energy Overload card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 103
local SINGU_DEF_ID = UnitDefNames.energysingu and UnitDefNames.energysingu.id
local EFFECT_KEY_PREFIX = "zk_cards_energy_overload_"
local UPDATE_FRAMES = 15
local RAMP_FRAMES = 20 * 60 * Game.gameSpeed
local MIN_DECAY_PER_SECOND = 0.025
local MAX_DECAY_PER_SECOND = 0.25
local MIN_ENERGY_MULT = 2.0
local MAX_ENERGY_MULT = 5.0

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spSetUnitHealth = Spring.SetUnitHealth

local allyTeamActive = {}
local trackedSingus = {}
local gaiaAllyTeam

local function Lerp(a, b, t)
	return a + (b - a) * t
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function IsEligibleSingu(unitDefID)
	return unitDefID == SINGU_DEF_ID
end

local function UpdateSinguEffect(unitID, frame, data)
	local ageFactor = math.min(1, math.max(0, (frame - data.startFrame) / RAMP_FRAMES))
	local energyMult = Lerp(MIN_ENERGY_MULT, MAX_ENERGY_MULT, ageFactor)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			energy = energyMult,
			static = true,
		})
	end

	local health, maxHealth = spGetUnitHealth(unitID)
	if health and maxHealth and maxHealth > 0 then
		local decayPerSecond = Lerp(MIN_DECAY_PER_SECOND, MAX_DECAY_PER_SECOND, ageFactor)
		local decayAmount = maxHealth * decayPerSecond * (UPDATE_FRAMES / Game.gameSpeed)
		spSetUnitHealth(unitID, math.max(0, health - decayAmount))
	end
end

local function TrackSingu(unitID, teamID)
	local unitDefID = spGetUnitDefID(unitID)
	if not IsEligibleSingu(unitDefID) then
		return
	end

	local allyTeamID = select(6, spGetTeamInfo(teamID, false))
	if allyTeamID == gaiaAllyTeam then
		return
	end

	trackedSingus[unitID] = trackedSingus[unitID] or {
		allyTeamID = allyTeamID,
		teamID = teamID,
		startFrame = spGetGameFrame(),
	}
	trackedSingus[unitID].allyTeamID = allyTeamID
	trackedSingus[unitID].teamID = teamID

	if not allyTeamActive[allyTeamID] and GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
end

local function UntrackSingu(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
	trackedSingus[unitID] = nil
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			if spGetUnitDefID(unitID) == SINGU_DEF_ID then
				TrackSingu(unitID, teamID)
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

function gadget:UnitFinished(unitID, unitDefID, teamID)
	if IsEligibleSingu(unitDefID) then
		TrackSingu(unitID, teamID)
	end
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	if IsEligibleSingu(unitDefID or spGetUnitDefID(unitID)) then
		TrackSingu(unitID, newTeamID)
	end
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	if IsEligibleSingu(unitDefID or spGetUnitDefID(unitID)) then
		TrackSingu(unitID, newTeamID)
	end
end

function gadget:UnitDestroyed(unitID)
	UntrackSingu(unitID)
end

function gadget:GameFrame(frame)
	UpdateCardActivation()
	if frame % UPDATE_FRAMES ~= 0 then
		return
	end

	for unitID, data in pairs(trackedSingus) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if unitDefID ~= SINGU_DEF_ID or not teamID then
			UntrackSingu(unitID)
		else
			data.teamID = teamID
			data.allyTeamID = select(6, spGetTeamInfo(teamID, false))
			if allyTeamActive[data.allyTeamID] then
				UpdateSinguEffect(unitID, frame, data)
			elseif GG.Attributes then
				GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
			end
		end
	end
end

function gadget:Initialize()
	if not SINGU_DEF_ID then
		gadgetHandler:RemoveGadget(self)
		return
	end
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))
	UpdateCardActivation()
end
