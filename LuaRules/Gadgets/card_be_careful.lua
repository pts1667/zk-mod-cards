function gadget:GetInfo()
	return {
		name = "Card Effect - Be Careful",
		desc = "Applies the Be Careful card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 310

local spDestroyUnit = Spring.DestroyUnit
local spGetAllUnits = Spring.GetAllUnits
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetUnitAllyTeam = Spring.GetUnitAllyTeam
local spGetUnitDefID = Spring.GetUnitDefID

local gaiaAllyTeam
local allyTeamActive = {}
local allyTeamState = {}
local pendingWipes = {}

local function IsCommander(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	local cp = unitDef and unitDef.customParams
	return cp and cp.commtype ~= nil
end

local function GetState(allyTeamID)
	local state = allyTeamState[allyTeamID]
	if not state then
		state = {
			commanders = {},
			aliveCount = 0,
			hadCommander = false,
			triggered = false,
		}
		allyTeamState[allyTeamID] = state
	end
	return state
end

local function AddCommander(unitID, allyTeamID)
	if not allyTeamID or allyTeamID == gaiaAllyTeam then
		return
	end
	local state = GetState(allyTeamID)
	if not state.commanders[unitID] then
		state.commanders[unitID] = true
		state.aliveCount = state.aliveCount + 1
		state.hadCommander = true
	end
end

local function RemoveCommander(unitID, allyTeamID, wasDestroyed)
	local state = allyTeamID and allyTeamState[allyTeamID]
	if not state or not state.commanders[unitID] then
		return
	end
	state.commanders[unitID] = nil
	state.aliveCount = math.max(0, state.aliveCount - 1)
	if wasDestroyed and allyTeamActive[allyTeamID] and state.hadCommander and state.aliveCount == 0 and not state.triggered then
		state.triggered = true
		pendingWipes[allyTeamID] = true
	end
end

local function SweepCommanders()
	for _, unitID in ipairs(spGetAllUnits()) do
		local unitDefID = spGetUnitDefID(unitID)
		if IsCommander(unitDefID) then
			AddCommander(unitID, spGetUnitAllyTeam(unitID))
		end
	end
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
		end
	end
end

local function ProcessPendingWipes()
	for allyTeamID in pairs(pendingWipes) do
		for _, unitID in ipairs(spGetAllUnits()) do
			if spGetUnitAllyTeam(unitID) == allyTeamID then
				spDestroyUnit(unitID, false, true)
			end
		end
		pendingWipes[allyTeamID] = nil
	end
end

function gadget:UnitCreated(unitID, unitDefID)
	if IsCommander(unitDefID) then
		AddCommander(unitID, spGetUnitAllyTeam(unitID))
	end
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID, oldTeamID)
	if IsCommander(unitDefID or spGetUnitDefID(unitID)) then
		if oldTeamID then
			RemoveCommander(unitID, select(6, spGetTeamInfo(oldTeamID, false)), false)
		end
		AddCommander(unitID, spGetUnitAllyTeam(unitID))
	end
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	if IsCommander(unitDefID or spGetUnitDefID(unitID)) then
		if oldTeamID then
			RemoveCommander(unitID, select(6, spGetTeamInfo(oldTeamID, false)), false)
		end
		AddCommander(unitID, spGetUnitAllyTeam(unitID))
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, teamID)
	if IsCommander(unitDefID) then
		local allyTeamID = teamID and select(6, spGetTeamInfo(teamID, false)) or spGetUnitAllyTeam(unitID)
		RemoveCommander(unitID, allyTeamID, true)
	end
end

function gadget:GameFrame(frame)
	if frame % 30 == 0 then
		UpdateCardActivation()
	end
	ProcessPendingWipes()
end

function gadget:Initialize()
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))
	UpdateCardActivation()
	SweepCommanders()
end
