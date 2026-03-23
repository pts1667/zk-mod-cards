function gadget:GetInfo()
	return {
		name = "Card Effect - Corroded Armor",
		desc = "Applies the Corroded Armor card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 304
local UPDATE_FRAMES = 30
local DRAIN_PER_MINUTE = 0.05
local DRAIN_PER_TICK = DRAIN_PER_MINUTE / (60 * Game.gameSpeed / UPDATE_FRAMES)

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitTeam = Spring.GetUnitTeam
local spSetUnitHealth = Spring.SetUnitHealth

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function IsCommander(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	local cp = unitDef and unitDef.customParams
	return cp and cp.commtype ~= nil
end

local function TrackUnit(unitID, unitDefID, teamID)
	if not unitDefID or IsCommander(unitDefID) then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedUnits[unitID] = allyTeamID
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			TrackUnit(unitID, spGetUnitDefID(unitID), teamID)
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

local function UpdateCorrosion()
	for unitID, allyTeamID in pairs(trackedUnits) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or IsCommander(unitDefID) then
			trackedUnits[unitID] = nil
		else
			allyTeamID = GetTeamAllyTeam(teamID)
			trackedUnits[unitID] = allyTeamID
			if allyTeamActive[allyTeamID] then
				local health, maxHealth, _, _, buildProgress = spGetUnitHealth(unitID)
				if not health or not maxHealth then
					trackedUnits[unitID] = nil
				elseif buildProgress == 1 and health > 0 then
					spSetUnitHealth(unitID, math.max(0, health - maxHealth * DRAIN_PER_TICK))
				end
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackUnit(unitID, unitDefID, teamID)
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	TrackUnit(unitID, unitDefID, teamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitDestroyed(unitID)
	trackedUnits[unitID] = nil
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		UpdateCorrosion()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
