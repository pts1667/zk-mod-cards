function gadget:GetInfo()
	return {
		name = "Card Effect - Strider Party",
		desc = "Applies the Strider Party card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 109
local EFFECT_KEY = "zk_cards_strider_party"
local HEALTH_MULT = 0.2
local COST_MULT = 0.4
local SCALE_MULT = 0.4

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetFeatureDefID = Spring.GetFeatureDefID
local spGetFeatureResources = Spring.GetFeatureResources
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local spGetTeamInfo = Spring.GetTeamInfo
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitPosition = Spring.GetUnitPosition
local spSetFeatureResources = Spring.SetFeatureResources

local gaiaAllyTeam
local striderHubDefID = UnitDefNames.striderhub and UnitDefNames.striderhub.id
local allyTeamActive = {}
local eligibleDefs = {}
local appliedUnits = {}
local pendingWreckAdjustments = {}

if striderHubDefID then
	local buildOptions = UnitDefs[striderHubDefID].buildOptions or {}
	for i = 1, #buildOptions do
		local unitDefID = buildOptions[i]
		if not UnitDefs[unitDefID].isImmobile then
			eligibleDefs[unitDefID] = true
		end
	end
end

local function GetTeamAllyTeam(teamID)
	return select(6, spGetTeamInfo(teamID, false))
end

local function GetCorpseFeatureDefs(unitDefID)
	local featureDefs = {}
	local corpseName = UnitDefs[unitDefID] and UnitDefs[unitDefID].corpse
	local corpseDef = corpseName and FeatureDefNames[corpseName]
	while corpseDef do
		featureDefs[corpseDef.id] = true
		corpseDef = corpseDef.deathFeatureID and FeatureDefs[corpseDef.deathFeatureID] or nil
	end
	return featureDefs
end

local function QueueWreckAdjustment(unitID, unitDefID)
	if not spSetFeatureResources then
		return
	end
	local x, _, z = spGetUnitPosition(unitID)
	if not x then
		return
	end
	pendingWreckAdjustments[#pendingWreckAdjustments + 1] = {
		frame = spGetGameFrame() + 1,
		x = x,
		z = z,
		defs = GetCorpseFeatureDefs(unitDefID),
	}
end

local function ApplyPendingWreckAdjustments(frame)
	if not spSetFeatureResources then
		return
	end

	local i = 1
	while i <= #pendingWreckAdjustments do
		local adjustment = pendingWreckAdjustments[i]
		if frame >= adjustment.frame then
			for _, featureID in ipairs(spGetFeaturesInCylinder(adjustment.x, adjustment.z, 128) or {}) do
				if adjustment.defs[spGetFeatureDefID(featureID)] then
					local currentMetal, maxMetal, currentEnergy, maxEnergy, reclaimLeft, reclaimTime = spGetFeatureResources(featureID)
					if currentMetal and maxMetal and maxMetal > 0 then
						local metalFraction = currentMetal / maxMetal
						local newMaxMetal = maxMetal * COST_MULT
						spSetFeatureResources(
							featureID,
							newMaxMetal * metalFraction,
							currentEnergy or 0,
							reclaimTime,
							reclaimLeft or metalFraction,
							newMaxMetal,
							maxEnergy or 0
						)
					end
				end
			end
			pendingWreckAdjustments[i] = pendingWreckAdjustments[#pendingWreckAdjustments]
			pendingWreckAdjustments[#pendingWreckAdjustments] = nil
		else
			i = i + 1
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

local function ApplyPartyEffect(unitID)
	if appliedUnits[unitID] then
		return
	end

	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, EFFECT_KEY, {
			healthMult = HEALTH_MULT,
			cost = COST_MULT,
			static = true,
		})
	end
	if GG.SetColvolScales then
		GG.SetColvolScales(unitID, {SCALE_MULT, SCALE_MULT, SCALE_MULT})
	end
	if GG.UnitModelRescale then
		GG.UnitModelRescale(unitID, SCALE_MULT)
	end

	appliedUnits[unitID] = true
end

local function TryApplyFromBuilder(unitID, unitDefID, unitTeam, builderID, builderDefID)
	if not (builderID and eligibleDefs[unitDefID]) then
		return
	end
	if not builderDefID then
		builderDefID = spGetUnitDefID(builderID)
	end
	if builderDefID ~= striderHubDefID then
		return
	end

	local allyTeamID = GetTeamAllyTeam(unitTeam)
	if allyTeamActive[allyTeamID] then
		ApplyPartyEffect(unitID)
	end
end

function gadget:UnitFromFactory(unitID, unitDefID, unitTeam, facID, facDefID)
	if facDefID ~= striderHubDefID or not eligibleDefs[unitDefID] then
		return
	end
	local allyTeamID = GetTeamAllyTeam(unitTeam)
	if allyTeamActive[allyTeamID] then
		ApplyPartyEffect(unitID)
	end
end

function gadget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
	TryApplyFromBuilder(unitID, unitDefID, unitTeam, builderID)
end

function gadget:UnitFinished(unitID, unitDefID, unitTeam, builderID)
	TryApplyFromBuilder(unitID, unitDefID, unitTeam, builderID)
end

function gadget:UnitDestroyed(unitID, unitDefID)
	if appliedUnits[unitID] then
		QueueWreckAdjustment(unitID, unitDefID)
	end
	appliedUnits[unitID] = nil
end

function gadget:GameFrame(frame)
	ApplyPendingWreckAdjustments(frame)
	if frame % 30 == 0 then
		UpdateCardActivation()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
