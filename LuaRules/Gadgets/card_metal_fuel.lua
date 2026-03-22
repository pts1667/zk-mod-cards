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
local STALL_EFFECT_PREFIX = "zk_cards_metal_fuel_stall_"
local COST_MULT = 0.1
local STALL_MOVE_MULT = 0.1
local FUEL_CHECK_FRAMES = 3 * Game.gameSpeed
local MAP_TRAVERSE_FUEL_RATIO = 0.50
local MIN_MOVED_DISTANCE = 8
local MAP_REFERENCE_DISTANCE = math.max(Game.mapSizeX or 1, Game.mapSizeZ or 1)

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetGroundHeight = Spring.GetGroundHeight
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spUseTeamResource = Spring.UseTeamResource

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}

local function GetDiscountKey(unitID)
	return DISCOUNT_EFFECT_PREFIX .. unitID
end

local function GetStallKey(unitID)
	return STALL_EFFECT_PREFIX .. unitID
end

local function IsEligibleMobile(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef and (unitDef.speed or 0) > 0
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

local function SetStalled(unitID, stalled)
	if not GG.Attributes then
		return
	end
	if stalled then
		GG.Attributes.AddEffect(unitID, GetStallKey(unitID), {
			move = STALL_MOVE_MULT,
		})
	else
		GG.Attributes.RemoveEffect(unitID, GetStallKey(unitID))
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

local function TrackUnit(unitID, unitDefID, teamID)
	if not IsEligibleMobile(unitDefID) then
		return
	end

	local allyTeamID = select(6, spGetTeamInfo(teamID, false))
	if allyTeamID == gaiaAllyTeam then
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
	else
		RemoveDiscount(unitID)
		SetStalled(unitID, false)
	end
end

local function UntrackUnit(unitID)
	RemoveDiscount(unitID)
	SetStalled(unitID, false)
	trackedUnits[unitID] = nil
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
				local dx = x - data.lastX
				local dz = z - data.lastZ
				local movedDistance = math.sqrt(dx * dx + dz * dz)
				local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
				if allyTeamActive[data.allyTeamID] and buildProgress == 1 and movedDistance >= MIN_MOVED_DISTANCE then
					local baseCost = UnitDefs[unitDefID].metalCost or 0
					local requiredMetal = baseCost * MAP_TRAVERSE_FUEL_RATIO * movedDistance / MAP_REFERENCE_DISTANCE
					if requiredMetal > 0 and spUseTeamResource(teamID, "metal", requiredMetal) then
						SetStalled(unitID, false)
					else
						SetStalled(unitID, true)
					end
				else
					SetStalled(unitID, false)
				end
				data.lastX = x
				data.lastZ = z
				if allyTeamActive[data.allyTeamID] then
					ApplyDiscount(unitID)
				else
					RemoveDiscount(unitID)
				end
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackUnit(unitID, unitDefID, teamID)
end

function gadget:UnitDestroyed(unitID)
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
	if frame % FUEL_CHECK_FRAMES == 0 then
		CheckFuel()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))
	UpdateCardActivation()
end
