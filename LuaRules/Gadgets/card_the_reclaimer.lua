function gadget:GetInfo()
	return {
		name = "Card Effect - The Reclaimer",
		desc = "Applies the The Reclaimer card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 204
local CLEANUP_RADIUS = 128

local spAddTeamResource = Spring.AddTeamResource
local spDestroyFeature = Spring.DestroyFeature
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetFeatureDefID = Spring.GetFeatureDefID
local spGetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetUnitPosition = Spring.GetUnitPosition

local allyTeamActive = {}
local pendingCleanup = {}
local gaiaAllyTeam

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

local function QueueCleanup(unitID, unitDefID)
	local x, _, z = spGetUnitPosition(unitID)
	if not x then
		return
	end
	pendingCleanup[#pendingCleanup + 1] = {
		frame = spGetGameFrame() + 1,
		x = x,
		z = z,
		defs = GetCorpseFeatureDefs(unitDefID),
	}
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam and not allyTeamActive[allyTeamID] and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
		end
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam, attackerID, attackerDefID, attackerTeam)
	if not attackerTeam or attackerTeam < 0 or attackerTeam == unitTeam then
		return
	end

	local victimAllyTeamID = select(6, spGetTeamInfo(unitTeam, false))
	local attackerAllyTeamID = select(6, spGetTeamInfo(attackerTeam, false))
	if not attackerAllyTeamID or attackerAllyTeamID == gaiaAllyTeam or attackerAllyTeamID == victimAllyTeamID then
		return
	end
	if not allyTeamActive[attackerAllyTeamID] then
		return
	end

	local metalValue = (UnitDefs[unitDefID] and UnitDefs[unitDefID].metalCost or 0) * (GG.att_CostMult and GG.att_CostMult[unitID] or 1)
	if metalValue > 0 then
		spAddTeamResource(attackerTeam, "metal", metalValue)
	end
	QueueCleanup(unitID, unitDefID)
end

function gadget:GameFrame(frame)
	UpdateCardActivation()

	local i = 1
	while i <= #pendingCleanup do
		local cleanup = pendingCleanup[i]
		if frame >= cleanup.frame then
			for _, featureID in ipairs(spGetFeaturesInCylinder(cleanup.x, cleanup.z, CLEANUP_RADIUS) or {}) do
				if cleanup.defs[spGetFeatureDefID(featureID)] then
					spDestroyFeature(featureID)
				end
			end
			pendingCleanup[i] = pendingCleanup[#pendingCleanup]
			pendingCleanup[#pendingCleanup] = nil
		else
			i = i + 1
		end
	end
end

function gadget:Initialize()
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))
	UpdateCardActivation()
end
