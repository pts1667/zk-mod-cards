function gadget:GetInfo()
	return {
		name = "Card Effect - Fragile Munitions",
		desc = "Applies the Fragile Munitions card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 303
local UPDATE_FRAMES = 15
local MISFIRE_CHANCE = 0.06
local JAM_CHANCE = 0.25
local JAM_DURATION_FRAMES = math.floor(1.5 * Game.gameSpeed)
local JAM_DAMAGE_MULT = 1.1
local DUD_DAMAGE_MULT = 0.5
local QUEUE_TTL_FRAMES = 5

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitTeam = Spring.GetUnitTeam

local gaiaAllyTeam
local allyTeamActive = {}
local eligibleWeapon = {}
local eligibleWeaponList = {}
local lastScriptFireFrame = {}
local pendingShots = {}
local projectileOutcome = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetBaseDamage(weaponDef)
	return (weaponDef.damages and (weaponDef.damages[0] or weaponDef.damages[1])) or 0
end

for weaponDefID = 1, #WeaponDefs do
	local weaponDef = WeaponDefs[weaponDefID]
	local cp = weaponDef.customParams or {}
	if not cp.bogus and GetBaseDamage(weaponDef) > 0 then
		eligibleWeapon[weaponDefID] = true
		eligibleWeaponList[#eligibleWeaponList + 1] = weaponDefID
	end
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

local function ApplyTemporaryDisarm(unitID)
	if GG.addParalysisDamageToUnit then
		local health = spGetUnitHealth(unitID)
		if health and health > 0 then
			GG.addParalysisDamageToUnit(unitID, health * JAM_DAMAGE_MULT, JAM_DURATION_FRAMES, 0)
		end
	end
end

local function TrimQueue(queue, frame)
	if not queue then
		return nil
	end
	local kept = {}
	for i = 1, #queue do
		local record = queue[i]
		if record.expireFrame >= frame then
			kept[#kept + 1] = record
		end
	end
	return (#kept > 0) and kept or nil
end

local function GetWeaponQueue(unitID, weaponDefID, frame)
	local byWeapon = pendingShots[unitID]
	if not byWeapon then
		return nil
	end
	byWeapon[weaponDefID] = TrimQueue(byWeapon[weaponDefID], frame)
	if not byWeapon[weaponDefID] then
		byWeapon[weaponDefID] = nil
	end
	if next(byWeapon) == nil then
		pendingShots[unitID] = nil
		return nil
	end
	return byWeapon[weaponDefID]
end

local function QueueOutcome(unitID, weaponDefID, mult, frame)
	pendingShots[unitID] = pendingShots[unitID] or {}
	local queue = GetWeaponQueue(unitID, weaponDefID, frame) or {}
	queue[#queue + 1] = {
		mult = mult,
		expireFrame = frame + QUEUE_TTL_FRAMES,
		attached = false,
	}
	pendingShots[unitID][weaponDefID] = queue
end

local function RollMisfire(unitID, weaponDefID, frame)
	if math.random() >= MISFIRE_CHANCE then
		return false
	end

	local mult = DUD_DAMAGE_MULT
	if math.random() < JAM_CHANCE then
		mult = 0
		ApplyTemporaryDisarm(unitID)
	end

	QueueOutcome(unitID, weaponDefID, mult, frame)
	return true
end

local function MarkScriptFire(unitID, weaponDefID, frame)
	lastScriptFireFrame[unitID] = lastScriptFireFrame[unitID] or {}
	lastScriptFireFrame[unitID][weaponDefID] = frame
end

local function GetPendingFallback(attackerID, weaponDefID, frame)
	local queue = GetWeaponQueue(attackerID, weaponDefID, frame)
	if not queue then
		return nil
	end
	for i = 1, #queue do
		local record = queue[i]
		if not record.attached then
			return record
		end
	end
	return nil
end

local function AttachProjectileOutcome(ownerID, weaponDefID, frame, projectileID)
	local record = GetPendingFallback(ownerID, weaponDefID, frame)
	if record then
		record.attached = true
		projectileOutcome[projectileID] = record.mult
		return true
	end
	return false
end

function gadget:ScriptFireWeapon(unitID, unitDefID, weaponNum)
	local weapons = UnitDefs[unitDefID] and UnitDefs[unitDefID].weapons
	local weaponDefID = weapons and weapons[weaponNum] and weapons[weaponNum].weaponDef
	if not eligibleWeapon[weaponDefID] then
		return
	end

	local allyTeamID = GetTeamAllyTeam(spGetUnitTeam(unitID))
	if not allyTeamActive[allyTeamID] then
		return
	end

	local frame = spGetGameFrame()
	MarkScriptFire(unitID, weaponDefID, frame)
	RollMisfire(unitID, weaponDefID, frame)
end

function gadget:ProjectileCreated(projectileID, ownerID, weaponDefID)
	if not (ownerID and eligibleWeapon[weaponDefID]) then
		return
	end

	local teamID = spGetUnitTeam(ownerID)
	local allyTeamID = GetTeamAllyTeam(teamID)
	if not allyTeamActive[allyTeamID] then
		return
	end

	local frame = spGetGameFrame()
	if AttachProjectileOutcome(ownerID, weaponDefID, frame, projectileID) then
		return
	end

	if lastScriptFireFrame[ownerID] and lastScriptFireFrame[ownerID][weaponDefID] == frame then
		return
	end

	if RollMisfire(ownerID, weaponDefID, frame) and AttachProjectileOutcome(ownerID, weaponDefID, frame, projectileID) then
		return
	end
end

function gadget:ProjectileDestroyed(projectileID)
	projectileOutcome[projectileID] = nil
end

function gadget:UnitPreDamaged_GetWantedWeaponDef()
	return eligibleWeaponList
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage, paralyzer, weaponDefID, attackerID, attackerDefID, attackerTeam, projectileID)
	if not eligibleWeapon[weaponDefID] then
		return damage
	end
	if projectileID and projectileOutcome[projectileID] ~= nil then
		return damage * projectileOutcome[projectileID]
	end
	if attackerID then
		local frame = spGetGameFrame()
		local record = GetPendingFallback(attackerID, weaponDefID, frame)
		if record then
			return damage * record.mult
		end
	end
	return damage
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES ~= 0 then
		return
	end

	UpdateCardActivation()
	for unitID, byWeapon in pairs(pendingShots) do
		for weaponDefID in pairs(byWeapon) do
			byWeapon[weaponDefID] = TrimQueue(byWeapon[weaponDefID], frame)
			if not byWeapon[weaponDefID] then
				byWeapon[weaponDefID] = nil
			end
		end
		if next(byWeapon) == nil then
			pendingShots[unitID] = nil
		end
	end
end

function gadget:UnitDestroyed(unitID)
	pendingShots[unitID] = nil
	lastScriptFireFrame[unitID] = nil
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
	if Script.SetWatchProjectile then
		for i = 1, #eligibleWeaponList do
			Script.SetWatchProjectile(eligibleWeaponList[i], true)
		end
	else
		for i = 1, #eligibleWeaponList do
			Script.SetWatchWeapon(eligibleWeaponList[i], true)
		end
	end
end
