function gadget:GetInfo()
	return {
		name = "Card Effect - Inefficient Refining",
		desc = "Applies the Inefficient Refining card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 305
local UPDATE_FRAMES = 30
local REQUIRED_OVERDRIVE = 1.5
local BELOW_THRESHOLD_MULT = 0.6
local EFFECT_KEY_PREFIX = "zk_cards_inefficient_refining_"

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitTeam = Spring.GetUnitTeam

local gaiaAllyTeam
local allyTeamActive = {}
local trackedMexes = {}
local mexDefs = {}

for unitDefID = 1, #UnitDefs do
	local cp = UnitDefs[unitDefID].customParams or {}
	if cp.ismex or cp.metal_extractor_mult then
		mexDefs[unitDefID] = true
	end
end

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function SetPenalty(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			econ = BELOW_THRESHOLD_MULT,
			static = true,
		})
	end
end

local function ClearPenalty(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
end

local function TrackMex(unitID, unitDefID, teamID)
	if not mexDefs[unitDefID] then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedMexes[unitID] = allyTeamID
	if not allyTeamActive[allyTeamID] then
		ClearPenalty(unitID)
	end
end

local function UntrackMex(unitID)
	ClearPenalty(unitID)
	trackedMexes[unitID] = nil
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			TrackMex(unitID, spGetUnitDefID(unitID), teamID)
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

local function UpdateMexes()
	for unitID, allyTeamID in pairs(trackedMexes) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or not mexDefs[unitDefID] then
			UntrackMex(unitID)
		else
			allyTeamID = GetTeamAllyTeam(teamID)
			trackedMexes[unitID] = allyTeamID
			local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
			local overdrive = spGetUnitRulesParam(unitID, "overdrive") or 1
			if allyTeamActive[allyTeamID] and buildProgress == 1 and overdrive < REQUIRED_OVERDRIVE then
				SetPenalty(unitID)
			else
				ClearPenalty(unitID)
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackMex(unitID, unitDefID, teamID)
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	TrackMex(unitID, unitDefID, teamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	TrackMex(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	TrackMex(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitDestroyed(unitID)
	UntrackMex(unitID)
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		UpdateMexes()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
