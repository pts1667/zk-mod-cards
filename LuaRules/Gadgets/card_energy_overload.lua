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
local UPDATE_FRAMES = 15
local RAMP_FRAMES = 20 * 60 * Game.gameSpeed
local MIN_DECAY_PER_SECOND = 0.01
local MAX_DECAY_PER_SECOND = 0.05
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
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetUnitTeam = Spring.GetUnitTeam
local spAddUnitDamage = Spring.AddUnitDamage

local allyTeamActive = {}
local trackedSingus = {}
local gaiaAllyTeam

local function Lerp(a, b, t)
	return a + (b - a) * t
end

local function GetBaseIncomeMultiplier(allyTeamID)
	if GG.allyTeamIncomeMult then
		return GG.allyTeamIncomeMult[allyTeamID] or 1
	end
	return 1
end

local function ApplyIncomeMultiplier(unitID, allyTeamID, energyMult)
	if not (GG.unit_handicap and GG.UpdateUnitAttributes) then
		return
	end

	local handicap = energyMult * GetBaseIncomeMultiplier(allyTeamID)
	if GG.unit_handicap[unitID] ~= handicap then
		GG.unit_handicap[unitID] = handicap
		GG.UpdateUnitAttributes(unitID)
	end
end

local function RestoreIncomeMultiplier(unitID, allyTeamID)
	if not (GG.unit_handicap and GG.UpdateUnitAttributes) then
		return
	end

	local baseMult = GetBaseIncomeMultiplier(allyTeamID)
	if baseMult == 1 then
		GG.unit_handicap[unitID] = nil
	else
		GG.unit_handicap[unitID] = baseMult
	end
	GG.UpdateUnitAttributes(unitID)
end

local function IsEligibleSingu(unitDefID)
	return unitDefID == SINGU_DEF_ID
end

local function UpdateSinguEffect(unitID, frame, data)
	local ageFactor = math.min(1, math.max(0, (frame - data.startFrame) / RAMP_FRAMES))
	local energyMult = Lerp(MIN_ENERGY_MULT, MAX_ENERGY_MULT, ageFactor)
	ApplyIncomeMultiplier(unitID, data.allyTeamID, energyMult)

	local health, maxHealth = spGetUnitHealth(unitID)
	if health and maxHealth and maxHealth > 0 then
		local decayPerSecond = Lerp(MIN_DECAY_PER_SECOND, MAX_DECAY_PER_SECOND, ageFactor)
		local decayAmount = maxHealth * decayPerSecond * (UPDATE_FRAMES / Game.gameSpeed)
		spAddUnitDamage(unitID, decayAmount, 0, nil, -7)
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

	if not allyTeamActive[allyTeamID] then
		RestoreIncomeMultiplier(unitID, allyTeamID)
	end
end

local function UntrackSingu(unitID)
	local allyTeamID = trackedSingus[unitID] and trackedSingus[unitID].allyTeamID or spGetUnitAllyTeam(unitID)
	if allyTeamID ~= nil then
		RestoreIncomeMultiplier(unitID, allyTeamID)
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
			else
				RestoreIncomeMultiplier(unitID, data.allyTeamID)
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
