function gadget:GetInfo()
	return {
		name = "Card Effect - Tanks",
		desc = "Applies the Tanks card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 104
local CHECK_FRAMES = 30
local ALLOWED_FACTORY_NAMES = {
	factorytank = true,
	platetank = true,
}

local spDestroyUnit = Spring.DestroyUnit
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam

local gaiaAllyTeam
local allyTeamActive = {}
local forbiddenFactoryDefs = {}

for unitDefID = 1, #UnitDefs do
	local unitDef = UnitDefs[unitDefID]
	local cp = unitDef.customParams or {}
	local isFactory = unitDef.isBuilding and unitDef.isBuilder and unitDef.buildOptions and #unitDef.buildOptions > 0 and (cp.factorytab or cp.child_of_factory)
	if isFactory and not ALLOWED_FACTORY_NAMES[unitDef.name] then
		forbiddenFactoryDefs[unitDefID] = true
	end
end

local function IsForbiddenFactory(unitDefID)
	return forbiddenFactoryDefs[unitDefID] and true or false
end

local function SweepForbiddenFactories(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID and IsForbiddenFactory(unitDefID) then
				spDestroyUnit(unitID, false, true)
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
			SweepForbiddenFactories(allyTeamID)
		end
	end
end

function gadget:AllowUnitCreation(unitDefID, builderID, builderTeam)
	if not builderID then
		return true
	end
	local builderUnitDefID = spGetUnitDefID(builderID)
	if not IsForbiddenFactory(builderUnitDefID) then
		return true
	end
	local allyTeamID = select(6, spGetTeamInfo(builderTeam, false))
	if not allyTeamActive[allyTeamID] then
		return true
	end
	return false, true
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	if not IsForbiddenFactory(unitDefID) then
		return
	end
	local allyTeamID = select(6, spGetTeamInfo(teamID, false))
	if allyTeamActive[allyTeamID] then
		spDestroyUnit(unitID, false, true)
	end
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	if not IsForbiddenFactory(unitDefID or spGetUnitDefID(unitID)) then
		return
	end
	local allyTeamID = select(6, spGetTeamInfo(newTeamID, false))
	if allyTeamActive[allyTeamID] then
		spDestroyUnit(unitID, false, true)
	end
end

function gadget:GameFrame(frame)
	if frame % CHECK_FRAMES == 0 then
		UpdateCardActivation()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))
	UpdateCardActivation()
end
