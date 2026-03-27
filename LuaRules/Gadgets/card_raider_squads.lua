function gadget:GetInfo()
	return {
		name = "Card Effect - Raider Squads",
		desc = "Applies the Raider Squads card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 201
local MINI_COST_MULT = 0.2
local MINI_SCALE = 0.4
local DEATH_FEATURE_RADIUS = 96
local MINI_EFFECT_KEY = "zk_cards_raider_squads_mini"
local MINI_RULES_PARAM = "zk_cards_raider_squads_mini"
local ELIGIBLE_RAIDER_NAMES = {
	"cloakraid",
	"cloakheavyraid",
	"shieldraid",
	"shieldscout",
	"vehscout",
	"vehraid",
	"amphraid",
	"jumpraid",
	"jumpscout",
	"tankheavyraid",
	"tankraid",
	"hoverraid",
	"hoverheavyraid",
	"spiderscout",
	"shipscout",
	"chicken",
	"chicken_leaper",
}
local eligibleRaiderDefs = {}

for i = 1, #ELIGIBLE_RAIDER_NAMES do
	local unitDef = UnitDefNames[ELIGIBLE_RAIDER_NAMES[i]]
	if unitDef then
		eligibleRaiderDefs[unitDef.id] = true
	end
end

local spCreateUnit = Spring.CreateUnit
local spDestroyFeature = Spring.DestroyFeature
local spDestroyUnit = Spring.DestroyUnit
local spGetFeatureDefID = Spring.GetFeatureDefID
local spGetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetGroundHeight = Spring.GetGroundHeight
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetUnitCommands = Spring.GetUnitCommands
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitHeading = Spring.GetUnitHeading
local spGetUnitStates = Spring.GetUnitStates
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spSetUnitRulesParam = Spring.SetUnitRulesParam

local CMD_RECLAIM = CMD.RECLAIM
local CMD_FIRE_STATE = CMD.FIRE_STATE
local CMD_MOVE_STATE = CMD.MOVE_STATE
local CMD_REPEAT = CMD.REPEAT

local allyTeamActive = {}
local miniUnits = {}
local pendingFeatureCleanup = {}
local pendingSquadReplacements = {}
local spawningMiniUnits = false
local gaiaAllyTeam

local function IsEligibleRaider(unitDefID)
	return eligibleRaiderDefs[unitDefID] and true or false
end

local function GetCorpseFeatureDefs(unitDefID)
	local featureDefs = {}
	local corpseName = UnitDefs[unitDefID] and UnitDefs[unitDefID].corpse
	if not corpseName then
		return featureDefs
	end

	local corpseDef = FeatureDefNames[corpseName]
	while corpseDef do
		featureDefs[corpseDef.id] = true
		corpseDef = corpseDef.deathFeatureID and FeatureDefs[corpseDef.deathFeatureID] or nil
	end
	return featureDefs
end

local function ApplyMiniVisuals(unitID, unitDefID)
	local baseMaxHealth = UnitDefs[unitDefID] and UnitDefs[unitDefID].health or 1
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, MINI_EFFECT_KEY, {
			healthAdd = 1 - baseMaxHealth,
			cost = MINI_COST_MULT,
			static = true,
		})
	end
	if GG.SetColvolScales then
		GG.SetColvolScales(unitID, {MINI_SCALE, MINI_SCALE, MINI_SCALE})
	end
	if GG.UnitModelRescale then
		GG.UnitModelRescale(unitID, MINI_SCALE)
	end
	spSetUnitRulesParam(unitID, MINI_RULES_PARAM, 1, {allied = true})
end

local function QueueDeathFeatureCleanup(unitID, unitDefID)
	local x, _, z = spGetUnitPosition(unitID)
	if not x then
		return
	end

	pendingFeatureCleanup[#pendingFeatureCleanup + 1] = {
		frame = spGetGameFrame() + 1,
		x = x,
		z = z,
		defs = GetCorpseFeatureDefs(unitDefID),
	}
end

local function CreateMiniSquad(unitID, unitDefID, teamID)
	local x, _, z = spGetUnitPosition(unitID)
	if not x then
		return
	end

	local heading = spGetUnitHeading(unitID) or 0
	local facing = math.floor((heading / 16384) % 4)
	local commands = spGetUnitCommands(unitID, -1) or {}
	local states = spGetUnitStates(unitID) or {}
	local spacing = 36
	local createdUnits = {}

	spawningMiniUnits = true
	for i = 1, 5 do
		local angle = ((i - 1) / 5) * math.pi * 2
		local spawnX = x + math.cos(angle) * spacing
		local spawnZ = z + math.sin(angle) * spacing
		local spawnY = spGetGroundHeight(spawnX, spawnZ)
		local miniID = spCreateUnit(unitDefID, spawnX, spawnY, spawnZ, facing, teamID, false)
		if miniID then
			createdUnits[#createdUnits + 1] = miniID
			miniUnits[miniID] = {
				unitDefID = unitDefID,
			}
			ApplyMiniVisuals(miniID, unitDefID)
		end
	end
	spawningMiniUnits = false

	for i = 1, #createdUnits do
		local miniID = createdUnits[i]
		if states.firestate ~= nil then
			spGiveOrderToUnit(miniID, CMD_FIRE_STATE, {states.firestate}, 0)
		end
		if states.movestate ~= nil then
			spGiveOrderToUnit(miniID, CMD_MOVE_STATE, {states.movestate}, 0)
		end
		if states["repeat"] ~= nil then
			spGiveOrderToUnit(miniID, CMD_REPEAT, {states["repeat"] and 1 or 0}, 0)
		end
		for j = 1, #commands do
			local cmd = commands[j]
			spGiveOrderToUnit(miniID, cmd.id, cmd.params, (cmd.options and cmd.options.coded) or 0)
		end
	end

	spDestroyUnit(unitID, false, true)
end

local function UpdateActivationForUnit(unitID, teamID)
	local allyTeamID = select(6, spGetTeamInfo(teamID, false))
	if allyTeamID and allyTeamID ~= gaiaAllyTeam and GG.ZKCards and GG.ZKCards.HasAppliedCard then
		allyTeamActive[allyTeamID] = allyTeamActive[allyTeamID] or GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID)
	end
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end

	local allyTeams = Spring.GetAllyTeamList()
	for i = 1, #allyTeams do
		local allyTeamID = allyTeams[i]
		if allyTeamID ~= gaiaAllyTeam and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
		end
	end
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams)
	if cmdID ~= CMD_RECLAIM then
		return true
	end
	local targetID = cmdParams and cmdParams[1]
	if targetID and targetID > 0 and miniUnits[targetID] then
		return false
	end
	return true
end

function gadget:AllowUnitBuildStep(builderID, teamID, unitID, unitDefID, step)
	if step < 0 and miniUnits[unitID] then
		return false
	end
	return true
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	UpdateActivationForUnit(unitID, teamID)
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	UpdateCardActivation()
	if spawningMiniUnits or miniUnits[unitID] or not IsEligibleRaider(unitDefID) then
		return
	end

	local allyTeamID = select(6, spGetTeamInfo(teamID, false))
	if not allyTeamActive[allyTeamID] then
		return
	end

	pendingSquadReplacements[unitID] = {
		unitDefID = unitDefID,
		teamID = teamID,
		frame = spGetGameFrame() + 1,
	}
end

function gadget:UnitDestroyed(unitID, unitDefID)
	pendingSquadReplacements[unitID] = nil
	if miniUnits[unitID] then
		QueueDeathFeatureCleanup(unitID, unitDefID)
		miniUnits[unitID] = nil
	end
end

function gadget:UnitTaken(unitID, unitDefID, oldTeam, newTeam)
	UpdateActivationForUnit(unitID, newTeam)
end

function gadget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
	UpdateActivationForUnit(unitID, newTeam)
end

function gadget:GameFrame(frame)
	UpdateCardActivation()

	for unitID, data in pairs(pendingSquadReplacements) do
		if frame >= data.frame then
			pendingSquadReplacements[unitID] = nil
			if spGetUnitDefID(unitID) == data.unitDefID and spGetUnitTeam(unitID) == data.teamID then
				CreateMiniSquad(unitID, data.unitDefID, data.teamID)
			end
		end
	end

	local i = 1
	while i <= #pendingFeatureCleanup do
		local cleanup = pendingFeatureCleanup[i]
		if frame >= cleanup.frame then
			local features = spGetFeaturesInCylinder(cleanup.x, cleanup.z, DEATH_FEATURE_RADIUS) or {}
			for j = 1, #features do
				local featureID = features[j]
				if cleanup.defs[spGetFeatureDefID(featureID)] then
					spDestroyFeature(featureID)
				end
			end
			pendingFeatureCleanup[i] = pendingFeatureCleanup[#pendingFeatureCleanup]
			pendingFeatureCleanup[#pendingFeatureCleanup] = nil
		else
			i = i + 1
		end
	end
end

function gadget:Initialize()
	local gaiaTeamID = spGetGaiaTeamID()
	gaiaAllyTeam = select(6, spGetTeamInfo(gaiaTeamID, false))
	UpdateCardActivation()
end
