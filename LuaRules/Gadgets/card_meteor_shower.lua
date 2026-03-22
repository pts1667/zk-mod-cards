function gadget:GetInfo()
	return {
		name = "Card Effect - Meteor Shower",
		desc = "Applies the Meteor Shower card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 101
local SOURCE_HEIGHT = 2600
local SOURCE_RADIUS = 700
local TARGET_RADIUS = 450
local MIN_DROP_FRAMES = 18 * Game.gameSpeed
local MAX_DROP_FRAMES = 32 * Game.gameSpeed
local SCRAP_FEATURE = "zk_card_meteor_scrap"

local METEOR_TIERS = {
	{damage = 260, radius = 120, scrapMin = 200, scrapMax = 300},
	{damage = 430, radius = 170, scrapMin = 280, scrapMax = 390},
	{damage = 680, radius = 220, scrapMin = 360, scrapMax = 500},
}

local spAddUnitDamageByTeam = Spring.AddUnitDamageByTeam
local spCreateFeature = Spring.CreateFeature
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetFeatureDefID = Spring.GetFeatureDefID
local spGetGameFrame = Spring.GetGameFrame
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGroundHeight = Spring.GetGroundHeight
local spGetProjectileDefID = Spring.GetProjectileDefID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitsInSphere = Spring.GetUnitsInSphere
local spSetFeatureResources = Spring.SetFeatureResources
local spSpawnProjectile = Spring.SpawnProjectile

local gaiaAllyTeam
local gaiaTeamID
local meteorWeaponDefID = WeaponDefNames.zenith_meteor_uncontrolled.id

local allyTeamState = {}
local projectileTierByID = {}

local function RandomRange(minValue, maxValue)
	return minValue + math.random() * (maxValue - minValue)
end

local function RandomPointAround(x, z, radius)
	local angle = math.random() * math.pi * 2
	local distance = radius * math.sqrt(math.random())
	return x + math.cos(angle) * distance, z + math.sin(angle) * distance
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

local function EnsureAllyTeamState(allyTeamID)
	local state = allyTeamState[allyTeamID]
	if state then
		return state
	end

	state = {
		active = false,
		nextDropFrame = nil,
	}
	allyTeamState[allyTeamID] = state
	return state
end

local function ChooseFinishedAnchor(allyTeamID)
	local candidates = {}
	local teamList = spGetTeamList(allyTeamID)
	for i = 1, #teamList do
		local unitList = spGetTeamUnits(teamList[i]) or {}
		for j = 1, #unitList do
			local unitID = unitList[j]
			local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
			if buildProgress == 1 then
				candidates[#candidates + 1] = unitID
			end
		end
	end

	if #candidates == 0 then
		return nil
	end
	return candidates[math.random(#candidates)]
end

local function ApplyRandomImpactDamage(x, y, z, tier)
	local units = spGetUnitsInSphere(x, y, z, tier.radius) or {}
	for i = 1, #units do
		local unitID = units[i]
		local ux, uy, uz = spGetUnitPosition(unitID)
		if ux and uy and uz then
			local dx = ux - x
			local dy = uy - y
			local dz = uz - z
			local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
			if distance <= tier.radius then
				local scale = 1 - (distance / tier.radius)
				spAddUnitDamageByTeam(unitID, tier.damage * scale, 0, nil, meteorWeaponDefID, gaiaTeamID)
			end
		end
	end
end

local function SpawnMeteorScrap(x, y, z, tier)
	local featureID = spCreateFeature(SCRAP_FEATURE, x, y, z, math.random(0, 3), gaiaTeamID)
	if not featureID then
		return
	end

	local metalAmount = math.floor(RandomRange(tier.scrapMin, tier.scrapMax) + 0.5)
	if spSetFeatureResources and spGetFeatureDefID(featureID) then
		spSetFeatureResources(featureID, metalAmount, 0, nil, 1)
	end
end

local function ScheduleNextDrop(state, frame)
	state.nextDropFrame = frame + math.random(MIN_DROP_FRAMES, MAX_DROP_FRAMES)
end

local function SpawnMeteorForAllyTeam(allyTeamID, frame)
	local anchorID = ChooseFinishedAnchor(allyTeamID)
	if not anchorID then
		return false
	end

	local ax, ay, az = spGetUnitPosition(anchorID)
	if not ax then
		return false
	end

	local targetX, targetZ = RandomPointAround(ax, az, TARGET_RADIUS)
	local sourceX, sourceZ = RandomPointAround(targetX, targetZ, SOURCE_RADIUS)
	local targetY = math.max(0, spGetGroundHeight(targetX, targetZ))
	local sourceY = math.max(ay, targetY) + SOURCE_HEIGHT
	local tier = METEOR_TIERS[math.random(#METEOR_TIERS)]

	local projectileID = spSpawnProjectile(meteorWeaponDefID, {
		pos = {sourceX, sourceY, sourceZ},
		["end"] = {targetX, targetY, targetZ},
		tracking = true,
		speed = {0, -5, 0},
		ttl = 900,
		gravity = -0.12,
		team = gaiaTeamID,
	})
	if projectileID then
		projectileTierByID[projectileID] = tier
	end

	return projectileID ~= nil
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard and GG.ZKCards.GetAppliedFrame) then
		return
	end

	local allyTeams = GetLivingAllyTeams()
	for i = 1, #allyTeams do
		local allyTeamID = allyTeams[i]
		local state = EnsureAllyTeamState(allyTeamID)
		if not state.active and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			local appliedFrame = GG.ZKCards.GetAppliedFrame(allyTeamID, CARD_ID) or spGetGameFrame()
			state.active = true
			ScheduleNextDrop(state, appliedFrame)
		end
	end
end

function gadget:Explosion_GetWantedWeaponDef()
	return {meteorWeaponDefID}
end

function gadget:Explosion(weaponDefID, px, py, pz, ownerID, projectileID)
	if weaponDefID ~= meteorWeaponDefID then
		return false
	end

	local tier = projectileTierByID[projectileID]
	if not tier then
		return false
	end

	projectileTierByID[projectileID] = nil
	ApplyRandomImpactDamage(px, py, pz, tier)
	SpawnMeteorScrap(px, math.max(py, spGetGroundHeight(px, pz)), pz, tier)
	return false
end

function gadget:ProjectileDestroyed(projectileID)
	projectileTierByID[projectileID] = nil
end

function gadget:GameFrame(frame)
	UpdateCardActivation()

	for allyTeamID, state in pairs(allyTeamState) do
		if state.active and state.nextDropFrame and frame >= state.nextDropFrame then
			if SpawnMeteorForAllyTeam(allyTeamID, frame) then
				ScheduleNextDrop(state, frame)
			else
				state.nextDropFrame = frame + Game.gameSpeed * 5
			end
		end
	end
end

function gadget:Initialize()
	gaiaTeamID = spGetGaiaTeamID()
	gaiaAllyTeam = select(6, spGetTeamInfo(gaiaTeamID, false))
	UpdateCardActivation()
end
