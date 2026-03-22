function gadget:GetInfo()
	return {
		name = "Card Effect - Salvage Rights",
		desc = "Applies the Salvage Rights card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 110
local UPDATE_FRAMES = 30

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetAllFeatures = Spring.GetAllFeatures
local spGetFeatureDefID = Spring.GetFeatureDefID
local spGetFeatureResources = Spring.GetFeatureResources
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spSetFeatureResources = Spring.SetFeatureResources

local gaiaAllyTeam
local activeStacks = 0
local wreckDefs = {}

for unitDefID = 1, #UnitDefs do
	local corpseName = UnitDefs[unitDefID].corpse
	local corpseDef = corpseName and FeatureDefNames[corpseName]
	while corpseDef do
		wreckDefs[corpseDef.id] = true
		corpseDef = corpseDef.deathFeatureID and FeatureDefs[corpseDef.deathFeatureID] or nil
	end
end

local function GetTeamAllyTeam(teamID)
	return select(6, spGetTeamInfo(teamID, false))
end

local function GetTargetMultiplier()
	return 1 + 0.5 * activeStacks
end

local function ApplyToFeature(featureID)
	if not spSetFeatureResources then
		return
	end
	local featureDefID = spGetFeatureDefID(featureID)
	if not wreckDefs[featureDefID] then
		return
	end

	local currentMetal, maxMetal, currentEnergy, maxEnergy, reclaimLeft, reclaimTime = spGetFeatureResources(featureID)
	if not currentMetal or not maxMetal or maxMetal <= 0 then
		return
	end

	local baseMetal = FeatureDefs[featureDefID].metal or maxMetal
	local newMaxMetal = baseMetal * GetTargetMultiplier()
	if math.abs(newMaxMetal - maxMetal) < 0.001 then
		return
	end

	local metalFraction = currentMetal / maxMetal
	local newCurrentMetal = newMaxMetal * metalFraction
	spSetFeatureResources(
		featureID,
		newCurrentMetal,
		currentEnergy or 0,
		reclaimTime,
		reclaimLeft or metalFraction,
		newMaxMetal,
		maxEnergy or 0
	)
end

local function SweepExistingFeatures()
	for _, featureID in ipairs(spGetAllFeatures() or {}) do
		ApplyToFeature(featureID)
	end
end

local function UpdateActiveStacks()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	local stacks = 0
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			stacks = stacks + 1
		end
	end
	if stacks ~= activeStacks then
		activeStacks = stacks
		SweepExistingFeatures()
	end
end

function gadget:FeatureCreated(featureID)
	if activeStacks > 0 then
		ApplyToFeature(featureID)
	end
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateActiveStacks()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateActiveStacks()
end
