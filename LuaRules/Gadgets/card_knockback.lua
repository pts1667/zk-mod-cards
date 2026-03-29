function gadget:GetInfo()
	return {
		name = "Card Effect - Knockback",
		desc = "Applies the Knockback card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 308
local UPDATE_FRAMES = 30
local DAMAGE_CAP = 600
local IMPULSE_PER_DAMAGE = 0.15
local TARGET_UNIT = 1
local TARGET_POS = 2

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitDirection = Spring.GetUnitDirection
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitWeaponTarget = Spring.GetUnitWeaponTarget

local gaiaAllyTeam
local allyTeamActive = {}
local lastProcessedFrame = {}
local eligibleWeapon = {}
local weaponNumByDef = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetBaseDamage(weaponDef)
	return (weaponDef.damages and (weaponDef.damages[0] or weaponDef.damages[1])) or 0
end

for weaponDefID = 1, #WeaponDefs do
	local weaponDef = WeaponDefs[weaponDefID]
	local cp = weaponDef.customParams or {}
	local baseDamage = GetBaseDamage(weaponDef)
	if not cp.bogus and not weaponDef.stockpile and not weaponDef.paralyzer and cp.disarmdamageonly ~= "1" and cp.timeslow_onlyslow ~= "1" and baseDamage > 0 then
		eligibleWeapon[weaponDefID] = {
			damage = math.min(baseDamage, DAMAGE_CAP),
		}
	end
end

for unitDefID = 1, #UnitDefs do
	local weapons = UnitDefs[unitDefID].weapons or {}
	for weaponNum = 1, #weapons do
		local weaponDefID = weapons[weaponNum].weaponDef
		if eligibleWeapon[weaponDefID] then
			weaponNumByDef[unitDefID] = weaponNumByDef[unitDefID] or {}
			weaponNumByDef[unitDefID][weaponDefID] = weaponNumByDef[unitDefID][weaponDefID] or weaponNum
		end
	end
end

local function Normalize(dx, dz)
	local length = math.sqrt(dx * dx + dz * dz)
	if length <= 0.001 then
		return nil
	end
	return dx / length, dz / length
end

local function GetFireDirection(unitID, weaponNum)
	local ux, _, uz = spGetUnitPosition(unitID)
	if not ux then
		return nil
	end

	local targetType, _, target = spGetUnitWeaponTarget(unitID, weaponNum)
	if targetType == TARGET_UNIT and target and Spring.ValidUnitID(target) then
		local tx, _, tz = spGetUnitPosition(target)
		if tx then
			local dx, dz = Normalize(tx - ux, tz - uz)
			if dx then
				return dx, dz
			end
		end
	elseif targetType == TARGET_POS and target then
		local dx, dz = Normalize(target[1] - ux, target[3] - uz)
		if dx then
			return dx, dz
		end
	end

	local dx, _, dz = spGetUnitDirection(unitID)
	if dx or dz then
		local ndx, ndz = Normalize(dx or 0, dz or 0)
		if ndx then
			return ndx, ndz
		end
	end
	return nil
end

local function MarkProcessed(unitID, weaponDefID, frame)
	lastProcessedFrame[unitID] = lastProcessedFrame[unitID] or {}
	lastProcessedFrame[unitID][weaponDefID] = frame
end

local function WasProcessed(unitID, weaponDefID, frame)
	return lastProcessedFrame[unitID] and lastProcessedFrame[unitID][weaponDefID] == frame
end

local function ApplyKnockback(unitID, unitDefID, weaponDefID, weaponNum)
	local weaponData = eligibleWeapon[weaponDefID]
	if not weaponData then
		return
	end
	local teamID = spGetUnitTeam(unitID)
	local allyTeamID = GetTeamAllyTeam(teamID)
	if not allyTeamActive[allyTeamID] then
		return
	end

	local dirX, dirZ = GetFireDirection(unitID, weaponNum)
	if not dirX then
		return
	end

	if GG.AddGadgetImpulse then
		GG.AddGadgetImpulse(unitID, -dirX, 0, -dirZ, weaponData.damage * IMPULSE_PER_DAMAGE, false, true, true, false, unitDefID)
	end
end

local function HandleFire(unitID, unitDefID, weaponDefID, weaponNum)
	local frame = spGetGameFrame()
	if WasProcessed(unitID, weaponDefID, frame) then
		return
	end
	MarkProcessed(unitID, weaponDefID, frame)
	ApplyKnockback(unitID, unitDefID, weaponDefID, weaponNum)
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam then
			allyTeamActive[allyTeamID] = GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) or false
		end
	end
end

function gadget:ScriptFireWeapon(unitID, unitDefID, weaponNum)
	local weapons = UnitDefs[unitDefID] and UnitDefs[unitDefID].weapons
	local weaponDefID = weapons and weapons[weaponNum] and weapons[weaponNum].weaponDef
	if weaponDefID and eligibleWeapon[weaponDefID] then
		HandleFire(unitID, unitDefID, weaponDefID, weaponNum)
	end
end

function gadget:ProjectileCreated(projectileID, ownerID, weaponDefID)
	if not (ownerID and eligibleWeapon[weaponDefID]) then
		return
	end
	local unitDefID = spGetUnitDefID(ownerID)
	local weaponNum = unitDefID and weaponNumByDef[unitDefID] and weaponNumByDef[unitDefID][weaponDefID]
	if unitDefID and weaponNum then
		HandleFire(ownerID, unitDefID, weaponDefID, weaponNum)
	end
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
	if Script.SetWatchProjectile then
		for weaponDefID in pairs(eligibleWeapon) do
			Script.SetWatchProjectile(weaponDefID, true)
		end
	else
		for weaponDefID in pairs(eligibleWeapon) do
			Script.SetWatchWeapon(weaponDefID, true)
		end
	end
end
