function gadget:GetInfo()
	return {
		name = "Card Effect - Frontier Economy",
		desc = "Applies the Frontier Economy card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 106
local UPDATE_FRAMES = 30
local CONTEST_RADIUS = 900
local SAFE_MULT = 1.25
local CONTESTED_MULT = 0.75
local EFFECT_KEY_PREFIX = "zk_cards_frontier_economy_"

local spAreTeamsAllied = Spring.AreTeamsAllied
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitsInSphere = Spring.GetUnitsInSphere
local spGetUnitIsCloaked = Spring.GetUnitIsCloaked

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

local function SetMexMult(unitID, mult)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			econ = mult,
			static = true,
		})
	end
end

local function ClearMexMult(unitID)
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
		ClearMexMult(unitID)
	end
end

local function UntrackMex(unitID)
	ClearMexMult(unitID)
	trackedMexes[unitID] = nil
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID and mexDefs[unitDefID] then
				TrackMex(unitID, unitDefID, teamID)
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

local function IsContested(unitID, teamID)
	local x, y, z = spGetUnitPosition(unitID)
	if not x then
		return false
	end
	local units = spGetUnitsInSphere(x, y, z, CONTEST_RADIUS) or {}
	for i = 1, #units do
		local otherID = units[i]
		if otherID ~= unitID then
			local otherTeam = spGetUnitTeam(otherID)
			if otherTeam and not spAreTeamsAllied(teamID, otherTeam) and not spGetUnitIsCloaked(otherID) then
				return true
			end
		end
	end
	return false
end

local function UpdateMexes()
	for unitID, allyTeamID in pairs(trackedMexes) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or not mexDefs[unitDefID] then
			trackedMexes[unitID] = nil
			ClearMexMult(unitID)
		else
			allyTeamID = GetTeamAllyTeam(teamID)
			trackedMexes[unitID] = allyTeamID
			local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
			if allyTeamActive[allyTeamID] and buildProgress == 1 then
				SetMexMult(unitID, IsContested(unitID, teamID) and CONTESTED_MULT or SAFE_MULT)
			else
				ClearMexMult(unitID)
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
