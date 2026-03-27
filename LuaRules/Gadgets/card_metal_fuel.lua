function gadget:GetInfo()
	return {
		name = "Card Effect - Metal Fuel",
		desc = "Applies the Metal Fuel card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 102
local DISCOUNT_EFFECT_PREFIX = "zk_cards_metal_fuel_discount_"
local DEBT_LOCK_EFFECT_PREFIX = "zk_cards_metal_fuel_debt_lock_"
local BUILD_STALL_EFFECT_PREFIX = "zk_cards_metal_fuel_build_stall_"
local TEAM_DEBT_RULES_PARAM = "zk_cards_metal_fuel_debt"
local COST_MULT = 0.1
local DEBT_MOVE_MULT = 0
local DEBT_RELOAD_MULT = 0.25
local FUEL_CHECK_FRAMES = 3 * Game.gameSpeed
local MAP_TRAVERSE_FUEL_RATIO = 0.50
local MIN_MOVED_DISTANCE = 8
local MAP_REFERENCE_DISTANCE = math.max(Game.mapSizeX or 1, Game.mapSizeZ or 1)
local ALLIED_VISIBLE = {allied = true}

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetFeatureDefID = Spring.GetFeatureDefID
local spGetFeatureResources = Spring.GetFeatureResources
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetFeaturesInCylinder = Spring.GetFeaturesInCylinder
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamResources = Spring.GetTeamResources
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spSetFeatureResources = Spring.SetFeatureResources
local spSetTeamRulesParam = Spring.SetTeamRulesParam
local spUseTeamResource = Spring.UseTeamResource

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}
local builderUnits = {}
local allyTeamMetalDebt = {}
local pendingWreckAdjustments = {}

local function GetDiscountKey(unitID)
	return DISCOUNT_EFFECT_PREFIX .. unitID
end

local function GetDebtLockKey(unitID)
	return DEBT_LOCK_EFFECT_PREFIX .. unitID
end

local function GetBuildStallKey(unitID)
	return BUILD_STALL_EFFECT_PREFIX .. unitID
end

local function IsEligibleMobile(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef and (unitDef.speed or 0) > 0
end

local function IsBuilder(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef and (unitDef.buildSpeed or 0) > 0
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

local function QueueWreckAdjustment(unitID, unitDefID, mult)
	if not spSetFeatureResources or mult == 1 then
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
		mult = mult,
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
						local newMaxMetal = maxMetal * adjustment.mult
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

local function ApplyDiscount(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetDiscountKey(unitID), {
			cost = COST_MULT,
			static = true,
		})
	end
end

local function RemoveDiscount(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetDiscountKey(unitID))
	end
end

local function SetDebtLocked(unitID, locked)
	if not GG.Attributes then
		return
	end
	if locked then
		GG.Attributes.AddEffect(unitID, GetDebtLockKey(unitID), {
			move = DEBT_MOVE_MULT,
			reload = DEBT_RELOAD_MULT,
		})
		spGiveOrderToUnit(unitID, CMD.STOP, {}, 0)
	else
		GG.Attributes.RemoveEffect(unitID, GetDebtLockKey(unitID))
	end
end

local function SetBuildStalled(unitID, stalled)
	if not GG.Attributes then
		return
	end
	if stalled then
		GG.Attributes.AddEffect(unitID, GetBuildStallKey(unitID), {
			build = 0,
			static = true,
		})
	else
		GG.Attributes.RemoveEffect(unitID, GetBuildStallKey(unitID))
	end
end

local function GetLivingAllyTeams()
	local allyTeams = {}
	local rawAllyTeams = spGetAllyTeamList()
	for i = 1, #rawAllyTeams do
		local allyTeamID = rawAllyTeams[i]
		if allyTeamID ~= gaiaAllyTeam then
			local teamList = spGetTeamList(allyTeamID)
			for j = 1, #teamList do
				local _, _, isDead = spGetTeamInfo(teamList[j], false)
				if not isDead then
					allyTeams[#allyTeams + 1] = allyTeamID
					break
				end
			end
		end
	end
	return allyTeams
end

local function TrackBuilder(unitID, unitDefID, teamID)
	if not IsBuilder(unitDefID) then
		SetBuildStalled(unitID, false)
		builderUnits[unitID] = nil
		return
	end

	local allyTeamID = select(6, spGetTeamInfo(teamID, false))
	if allyTeamID == gaiaAllyTeam then
		SetBuildStalled(unitID, false)
		builderUnits[unitID] = nil
		return
	end

	builderUnits[unitID] = {
		allyTeamID = allyTeamID,
	}
	SetBuildStalled(unitID, allyTeamActive[allyTeamID] and (allyTeamMetalDebt[allyTeamID] or 0) > 0)
end

local function TrackMobile(unitID, unitDefID, teamID)
	if not IsEligibleMobile(unitDefID) then
		RemoveDiscount(unitID)
		SetDebtLocked(unitID, false)
		trackedUnits[unitID] = nil
		return
	end

	local allyTeamID = select(6, spGetTeamInfo(teamID, false))
	if allyTeamID == gaiaAllyTeam then
		RemoveDiscount(unitID)
		SetDebtLocked(unitID, false)
		trackedUnits[unitID] = nil
		return
	end

	local x, _, z = spGetUnitPosition(unitID)
	if not x then
		return
	end

	trackedUnits[unitID] = {
		unitDefID = unitDefID,
		teamID = teamID,
		allyTeamID = allyTeamID,
		lastX = x,
		lastZ = z,
	}

	if allyTeamActive[allyTeamID] then
		ApplyDiscount(unitID)
		SetDebtLocked(unitID, (allyTeamMetalDebt[allyTeamID] or 0) > 0)
	else
		RemoveDiscount(unitID)
		SetDebtLocked(unitID, false)
	end
end

local function TrackUnit(unitID, unitDefID, teamID)
	if not unitDefID or not teamID then
		return
	end
	TrackMobile(unitID, unitDefID, teamID)
	TrackBuilder(unitID, unitDefID, teamID)
end

local function UntrackUnit(unitID)
	RemoveDiscount(unitID)
	SetDebtLocked(unitID, false)
	SetBuildStalled(unitID, false)
	trackedUnits[unitID] = nil
	builderUnits[unitID] = nil
end

local function SweepUnitsForAllyTeam(allyTeamID)
	local teamList = spGetTeamList(allyTeamID)
	for i = 1, #teamList do
		local teamID = teamList[i]
		local unitList = spGetTeamUnits(teamID) or {}
		for j = 1, #unitList do
			local unitID = unitList[j]
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID then
				TrackUnit(unitID, unitDefID, teamID)
			end
		end
	end
end

local function SetAllyTeamBuildStalled(allyTeamID, stalled)
	for unitID, data in pairs(builderUnits) do
		if data.allyTeamID == allyTeamID then
			SetBuildStalled(unitID, stalled)
		end
	end
end

local function SetAllyTeamDebtRulesParam(allyTeamID, debt)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		spSetTeamRulesParam(teamID, TEAM_DEBT_RULES_PARAM, debt or 0, ALLIED_VISIBLE)
	end
end

local function SetAllyTeamDebtLocked(allyTeamID, locked)
	for unitID, data in pairs(trackedUnits) do
		if data.allyTeamID == allyTeamID then
			SetDebtLocked(unitID, locked)
		end
	end
end

local function UpdateAllyTeamDebtState(allyTeamID)
	local debt = allyTeamMetalDebt[allyTeamID] or 0
	local locked = debt > 0
	SetAllyTeamDebtRulesParam(allyTeamID, debt)
	SetAllyTeamBuildStalled(allyTeamID, locked)
	SetAllyTeamDebtLocked(allyTeamID, locked)
end

local function AddMetalDebt(allyTeamID, amount)
	if amount <= 0 then
		return
	end
	allyTeamMetalDebt[allyTeamID] = (allyTeamMetalDebt[allyTeamID] or 0) + amount
	UpdateAllyTeamDebtState(allyTeamID)
end

local function RepayMetalDebtForTeam(teamID, allyTeamID)
	local debt = allyTeamMetalDebt[allyTeamID] or 0
	if debt <= 0 then
		return
	end

	local currentMetal = spGetTeamResources(teamID, "metal") or 0
	local payment = math.min(currentMetal, debt)
	if payment > 0 and spUseTeamResource(teamID, "metal", payment) then
		debt = debt - payment
	end

	if debt <= 0.0001 then
		allyTeamMetalDebt[allyTeamID] = nil
	else
		allyTeamMetalDebt[allyTeamID] = debt
	end
	UpdateAllyTeamDebtState(allyTeamID)
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end

	local allyTeams = GetLivingAllyTeams()
	for i = 1, #allyTeams do
		local allyTeamID = allyTeams[i]
		if not allyTeamActive[allyTeamID] and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
			SweepUnitsForAllyTeam(allyTeamID)
			UpdateAllyTeamDebtState(allyTeamID)
		end
	end
end

local function CheckFuel()
	for unitID, data in pairs(trackedUnits) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID then
			UntrackUnit(unitID)
		else
			data.unitDefID = unitDefID
			data.teamID = teamID
			data.allyTeamID = select(6, spGetTeamInfo(teamID, false))
			local x, _, z = spGetUnitPosition(unitID)
			if not x then
				UntrackUnit(unitID)
			else
				if allyTeamActive[data.allyTeamID] then
					RepayMetalDebtForTeam(teamID, data.allyTeamID)
				end
				local dx = x - data.lastX
				local dz = z - data.lastZ
				local movedDistance = math.sqrt(dx * dx + dz * dz)
				local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
				if allyTeamActive[data.allyTeamID] and buildProgress == 1 and movedDistance >= MIN_MOVED_DISTANCE then
					local baseCost = UnitDefs[unitDefID].metalCost or 0
					local requiredMetal = baseCost * MAP_TRAVERSE_FUEL_RATIO * movedDistance / MAP_REFERENCE_DISTANCE
					if requiredMetal > 0 then
						local paid = 0
						local currentMetal = spGetTeamResources(teamID, "metal") or 0
						local immediatePayment = math.min(currentMetal, requiredMetal)
						if immediatePayment > 0 and spUseTeamResource(teamID, "metal", immediatePayment) then
							paid = immediatePayment
						end
						if paid >= requiredMetal then
						else
							AddMetalDebt(data.allyTeamID, requiredMetal - paid)
						end
					end
				end
				data.lastX = x
				data.lastZ = z
				if allyTeamActive[data.allyTeamID] then
					ApplyDiscount(unitID)
					SetDebtLocked(unitID, (allyTeamMetalDebt[data.allyTeamID] or 0) > 0)
				else
					RemoveDiscount(unitID)
					SetDebtLocked(unitID, false)
				end
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackUnit(unitID, unitDefID, teamID)
end

function gadget:UnitDestroyed(unitID, unitDefID)
	local data = trackedUnits[unitID]
	if data and allyTeamActive[data.allyTeamID] then
		QueueWreckAdjustment(unitID, unitDefID or data.unitDefID, COST_MULT)
	end
	UntrackUnit(unitID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	if newTeamID then
		TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
	end
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID, oldTeamID)
	if newTeamID then
		TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
	end
end

function gadget:GameFrame(frame)
	UpdateCardActivation()
	ApplyPendingWreckAdjustments(frame)
	if frame % FUEL_CHECK_FRAMES == 0 then
		CheckFuel()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))
	UpdateCardActivation()
	for _, allyTeamID in ipairs(GetLivingAllyTeams()) do
		SetAllyTeamDebtRulesParam(allyTeamID, allyTeamMetalDebt[allyTeamID] or 0)
	end
end
