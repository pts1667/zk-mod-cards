function gadget:GetInfo()
	return {
		name = "Card Effect - Builders",
		desc = "Applies the Builders card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 107
local RESOURCE_FRAMES = Game.gameSpeed

local spAddTeamResource = Spring.AddTeamResource
local spEditUnitCmdDesc = Spring.EditUnitCmdDesc
local spFindUnitCmdDesc = Spring.FindUnitCmdDesc
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitTeam = Spring.GetUnitTeam
local spUseTeamResource = Spring.UseTeamResource

local gaiaAllyTeam
local allyTeamActive = {}
local trackedBuilders = {}
local trackedMexes = {}
local builderDefs = {}
local factoryLikeDefs = {}
local constructorBuildDefs = {}

local function IsFactoryLike(unitDef)
	local cp = unitDef and unitDef.customParams or {}
	return unitDef and unitDef.isBuilder and unitDef.buildOptions and #unitDef.buildOptions > 0 and (unitDef.isFactory or cp.factorytab or cp.child_of_factory)
end

local function IsMobileUnit(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef and (not unitDef.isImmobile) and true or false
end

local function CanBuilderCreate(builderDefID, buildDefID)
	if not buildDefID then
		return true
	end
	if not IsMobileUnit(buildDefID) then
		return true
	end
	return factoryLikeDefs[builderDefID] and constructorBuildDefs[buildDefID] or false
end

for unitDefID = 1, #UnitDefs do
	local unitDef = UnitDefs[unitDefID]
	local cp = unitDef.customParams or {}
	if unitDef.isBuilder then
		builderDefs[unitDefID] = true
	end
	if IsFactoryLike(unitDef) then
		factoryLikeDefs[unitDefID] = true
	end
	if unitDef.isBuilder and not IsFactoryLike(unitDef) then
		constructorBuildDefs[unitDefID] = true
	end
	if cp.ismex or cp.metal_extractor_mult then
		trackedMexes[0 - unitDefID] = true
	end
end

local function IsMex(unitDefID)
	return trackedMexes[0 - unitDefID] and true or false
end

local function GetTeamAllyTeam(teamID)
	return select(6, spGetTeamInfo(teamID, false))
end

local function UpdateBuilderCommands(unitID, unitDefID)
	if not builderDefs[unitDefID] then
		return
	end
	local teamID = spGetUnitTeam(unitID)
	if not teamID then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	local active = allyTeamActive[allyTeamID]
	local buildOptions = UnitDefs[unitDefID].buildOptions or {}
	local cmdEditArray = {}
	for i = 1, #buildOptions do
		local buildDefID = buildOptions[i]
		local cmdDescID = spFindUnitCmdDesc(unitID, -buildDefID)
		if cmdDescID then
			cmdEditArray.disabled = active and (not CanBuilderCreate(unitDefID, buildDefID)) or false
			spEditUnitCmdDesc(unitID, cmdDescID, cmdEditArray)
		end
	end
end

local function TrackBuilder(unitID, unitDefID, teamID)
	if not builderDefs[unitDefID] then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedBuilders[unitID] = {
		teamID = teamID,
		allyTeamID = allyTeamID,
	}
	UpdateBuilderCommands(unitID, unitDefID)
end

local function ApplyMexSuppression(unitID, active)
	if not GG.Attributes then
		return
	end
	if active then
		GG.Attributes.AddEffect(unitID, "zk_cards_builders_mex", {
			econ = 0,
			static = true,
		})
	else
		GG.Attributes.RemoveEffect(unitID, "zk_cards_builders_mex")
	end
end

local function TrackMex(unitID, unitDefID, teamID)
	if not IsMex(unitDefID) then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedMexes[unitID] = {
		teamID = teamID,
		allyTeamID = allyTeamID,
	}
	ApplyMexSuppression(unitID, allyTeamActive[allyTeamID])
end

local function SweepExistingUnits(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID then
				TrackBuilder(unitID, unitDefID, teamID)
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
			SweepExistingUnits(allyTeamID)
		end
	end
end

local function ApplyBuilderIncome()
	local countsByTeam = {}
	for unitID, data in pairs(trackedBuilders) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or not builderDefs[unitDefID] then
			trackedBuilders[unitID] = nil
		else
			data.teamID = teamID
			data.allyTeamID = GetTeamAllyTeam(teamID)
			local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
			if allyTeamActive[data.allyTeamID] and buildProgress == 1 then
				countsByTeam[teamID] = (countsByTeam[teamID] or 0) + 1
			end
			UpdateBuilderCommands(unitID, unitDefID)
		end
	end

	for teamID, count in pairs(countsByTeam) do
		spAddTeamResource(teamID, "metal", 0.4 * count)
		spUseTeamResource(teamID, "energy", 1 * count)
	end
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID)
	if cmdID >= 0 or not builderDefs[unitDefID] then
		return true
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if not allyTeamActive[allyTeamID] then
		return true
	end
	return CanBuilderCreate(unitDefID, -cmdID)
end

function gadget:AllowUnitCreation(unitDefID, builderID, builderTeam)
	if not builderID then
		return true
	end
	local builderDefID = spGetUnitDefID(builderID)
	if not builderDefID or not builderDefs[builderDefID] then
		return true
	end
	local allyTeamID = GetTeamAllyTeam(builderTeam)
	if not allyTeamActive[allyTeamID] then
		return true
	end
	return CanBuilderCreate(builderDefID, unitDefID)
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackBuilder(unitID, unitDefID, teamID)
	TrackMex(unitID, unitDefID, teamID)
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	TrackBuilder(unitID, unitDefID, teamID)
	TrackMex(unitID, unitDefID, teamID)
end

function gadget:UnitDestroyed(unitID)
	if trackedBuilders[unitID] then
		trackedBuilders[unitID] = nil
	end
	if trackedMexes[unitID] then
		ApplyMexSuppression(unitID, false)
		trackedMexes[unitID] = nil
	end
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	if trackedMexes[unitID] then
		ApplyMexSuppression(unitID, false)
	end
	TrackBuilder(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
	TrackMex(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	if trackedMexes[unitID] then
		ApplyMexSuppression(unitID, false)
	end
	TrackBuilder(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
	TrackMex(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:GameFrame(frame)
	UpdateCardActivation()
	if frame % RESOURCE_FRAMES == 0 then
		ApplyBuilderIncome()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
