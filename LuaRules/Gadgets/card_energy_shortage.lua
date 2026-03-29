function gadget:GetInfo()
	return {
		name = "Card Effect - Energy Shortage",
		desc = "Applies the Energy Shortage card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 302
local EFFECT_KEY_PREFIX = "zk_cards_energy_shortage_"
local UPDATE_FRAMES = 30
local CYCLE_FRAMES = 180 * Game.gameSpeed
local MIN_FACTOR = 0.2
local MAX_FACTOR = 1.2
local MID_FACTOR = (MIN_FACTOR + MAX_FACTOR) * 0.5
local AMP_FACTOR = (MAX_FACTOR - MIN_FACTOR) * 0.5

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function GetCurrentFactor(frame)
	return MID_FACTOR + AMP_FACTOR * math.sin((frame / CYCLE_FRAMES) * math.pi * 2)
end

local function ApplyFactor(unitID, factor)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			energy = factor,
			static = true,
		})
	end
end

local function RemoveFactor(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
end

local function TrackUnit(unitID, teamID)
	local allyTeamID = select(6, spGetTeamInfo(teamID, false))
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedUnits[unitID] = allyTeamID
	if not allyTeamActive[allyTeamID] then
		RemoveFactor(unitID)
	end
end

local function UntrackUnit(unitID)
	RemoveFactor(unitID)
	trackedUnits[unitID] = nil
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			TrackUnit(unitID, teamID)
		end
	end
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam then
			allyTeamActive[allyTeamID] = GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) or false
			if allyTeamActive[allyTeamID] then
				SweepAllyTeam(allyTeamID)
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackUnit(unitID, teamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	TrackUnit(unitID, newTeamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	TrackUnit(unitID, newTeamID)
end

function gadget:UnitDestroyed(unitID)
	UntrackUnit(unitID)
end

function gadget:GameFrame(frame)
	UpdateCardActivation()
	if frame % UPDATE_FRAMES ~= 0 then
		return
	end

	local factor = GetCurrentFactor(frame)
	for unitID, allyTeamID in pairs(trackedUnits) do
		if not spGetUnitDefID(unitID) or not spGetUnitTeam(unitID) then
			UntrackUnit(unitID)
		elseif allyTeamActive[allyTeamID] then
			ApplyFactor(unitID, factor)
		else
			RemoveFactor(unitID)
		end
	end
end

function gadget:Initialize()
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))
	UpdateCardActivation()
end
