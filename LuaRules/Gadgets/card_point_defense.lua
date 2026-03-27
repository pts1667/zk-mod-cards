function gadget:GetInfo()
	return {
		name = "Card Effect - Point Defense",
		desc = "Applies the Point Defense card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 115
local UPDATE_FRAMES = 1
local SWEEP_FRAMES = 30
local FAST_RELOAD_FRAMES = 2
local RANGE_FLOOR = 0.01
local EFFECT_KEY_PREFIX = "zk_cards_point_defense_"

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitWeaponState = Spring.GetUnitWeaponState

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}
local helperNamePatterns = {
	"^FAKE",
	"^BOGUS",
	"^TARGET",
	"^RELAY",
	"^SHIELD_CHECK",
	"^LANDING$",
	"^TAKEOFF$",
	"^FOOTCRATER$",
	"^CARRIERTARGETING$",
}
local excludedUnitDefs = {
	assaultcruiser = true,
	gunshipkrow = true,
	jumpaa = true,
	raveparty = true,
	shieldfelon = true,
	shipaa = true,
	shipassault = true,
	shipcarrier = true,
	slicer = true,
	striderbantha = true,
	striderdante = true,
	striderdetriment = true,
	tankheavyassault = true,
	turretheavy = true,
}
local forcedMainWeaponByDefName = {
}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function IsHelperWeaponDef(defName, weaponDef)
	if not weaponDef then
		return true
	end

	local upperDefName = defName and string.upper(defName) or ""
	for i = 1, #helperNamePatterns do
		if upperDefName:match(helperNamePatterns[i]) then
			return true
		end
	end

	local weaponName = string.upper(weaponDef.name or "")
	if weaponName:find("FAKE", 1, true) or weaponName:find("BOGUS", 1, true) then
		return true
	end

	local customParams = weaponDef.customParams or weaponDef.customparams
	if customParams then
		if customParams.bogus or customParams.fake_weapon then
			return true
		end
	end

	return false
end

local function GetWeaponDamageScore(weaponDef)
	local damage = weaponDef.damages or weaponDef.damage
	if type(damage) ~= "table" then
		return 0
	end

	local best = 0
	for _, value in pairs(damage) do
		if type(value) == "number" and value > best then
			best = value
		end
	end
	return best
end

local function GetWeaponPriority(unitDef, weaponNum, weaponDef)
	local score = 0
	local customParams = weaponDef.customParams or weaponDef.customparams

	score = score + math.min(weaponDef.range or 0, 10000) * 0.01
	score = score + math.min(weaponDef.reload or 0, 60) * 2
	score = score + math.min(GetWeaponDamageScore(weaponDef), 5000) * 0.02

	if weaponDef.stockpile then
		score = score - 1000
	end
	if weaponDef.isShield then
		score = score - 1000
	end
	if customParams and (customParams.shield_radius or customParams.shield_power) then
		score = score - 1000
	end
	if customParams and (customParams.stats_damage or customParams.extra_damage) then
		score = score + math.min(tonumber(customParams.stats_damage or customParams.extra_damage) or 0, 5000) * 0.02
	end

	local onlyTargetCategory = unitDef.weapons and unitDef.weapons[weaponNum] and unitDef.weapons[weaponNum].onlyTargetCategory or ""
	if onlyTargetCategory == "NONE" then
		score = score - 500
	end

	return score
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

local function GetMainWeaponData(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	if not unitDef then
		return nil
	end
	if excludedUnitDefs[unitDef.name] then
		return nil
	end

	local forcedWeaponNum = forcedMainWeaponByDefName[unitDef.name]
	if forcedWeaponNum and unitDef.weapons and unitDef.weapons[forcedWeaponNum] then
		local weaponDefID = unitDef.weapons[forcedWeaponNum].weaponDef
		local weaponDef = WeaponDefs[weaponDefID]
		if weaponDef and (weaponDef.range or 0) > 0 and (weaponDef.reload or 0) > 0 then
			return {
				mainWeaponNum = forcedWeaponNum,
				baseReload = weaponDef.reload,
			}
		end
	end

	local bestCandidate
	local bestFallback
	for weaponNum = 1, #(unitDef.weapons or {}) do
		local weaponSlot = unitDef.weapons[weaponNum]
		local weaponDefID = weaponSlot.weaponDef
		local weaponDef = WeaponDefs[weaponDefID]
		if weaponDef and not weaponDef.stockpile and (weaponDef.range or 0) > 0 and (weaponDef.reload or 0) > 0 then
			local defName = weaponSlot.name or weaponSlot.def or (WeaponDefNames and WeaponDefNames[weaponDefID] and WeaponDefNames[weaponDefID].name)
			local candidate = {
				mainWeaponNum = weaponNum,
				baseReload = weaponDef.reload,
				score = GetWeaponPriority(unitDef, weaponNum, weaponDef),
			}
			if not bestFallback or candidate.score > bestFallback.score then
				bestFallback = candidate
			end
			if not IsHelperWeaponDef(defName, weaponDef) and (not bestCandidate or candidate.score > bestCandidate.score) then
				bestCandidate = candidate
			end
		end
	end

	if bestCandidate then
		return {
			mainWeaponNum = bestCandidate.mainWeaponNum,
			baseReload = bestCandidate.baseReload,
		}
	end
	if bestFallback then
		return {
			mainWeaponNum = bestFallback.mainWeaponNum,
			baseReload = bestFallback.baseReload,
		}
	end

	return nil
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID and not trackedUnits[unitID] then
				local weaponData = GetMainWeaponData(unitDefID)
				if weaponData then
					trackedUnits[unitID] = {
						unitDefID = unitDefID,
						mainWeaponNum = weaponData.mainWeaponNum,
						baseReload = weaponData.baseReload,
						appliedReloadMult = false,
						lastReloadState = false,
						lastShotFrame = false,
						wasReady = false,
						initialized = false,
					}
				end
			end
		end
	end
end

local function RemoveUnitEffect(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
end

local function GetExternalReloadMult(unitID)
	local totalReloadMult = spGetUnitRulesParam(unitID, "totalReloadSpeedChange") or 1
	return math.max(totalReloadMult, 0.0001)
end

local function RestoreUnit(unitID, data)
	RemoveUnitEffect(unitID)
	data.appliedReloadMult = false
	data.lastShotFrame = false
end

local function ApplyUnitUpdate(unitID, data, gameFrame)
	local targetReloadSeconds = FAST_RELOAD_FRAMES / Game.gameSpeed
	local currentReloadTime = spGetUnitWeaponState(unitID, data.mainWeaponNum, "reloadTime") or (data.baseReload / GetExternalReloadMult(unitID))
	local mainReloadSeconds = currentReloadTime * (data.appliedReloadMult or 1)
	local reloadMult = math.max(mainReloadSeconds / targetReloadSeconds, 1)

	local reloadState = spGetUnitWeaponState(unitID, data.mainWeaponNum, "reloadState")
	if reloadState then
		local isReady = reloadState <= gameFrame + 0.5
		if data.lastReloadState and reloadState > data.lastReloadState + 0.5 then
			data.lastShotFrame = gameFrame
		elseif data.wasReady and not isReady then
			data.lastShotFrame = gameFrame
		elseif not data.initialized then
			data.lastShotFrame = gameFrame
		end
		data.wasReady = isReady
		data.lastReloadState = reloadState
	end
	data.initialized = true

	local elapsed = math.max(0, gameFrame - (data.lastShotFrame or gameFrame))
	local progress = math.min(1, elapsed / math.max(mainReloadSeconds * Game.gameSpeed, 1))
	local rangeMult = RANGE_FLOOR + (1 - RANGE_FLOOR) * progress

	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			reload = reloadMult,
			range = rangeMult,
		})
	end

	data.appliedReloadMult = reloadMult
end

local function TrackUnit(unitID, unitDefID)
	if trackedUnits[unitID] then
		return
	end
	local weaponData = GetMainWeaponData(unitDefID)
	if weaponData then
		trackedUnits[unitID] = {
			unitDefID = unitDefID,
			mainWeaponNum = weaponData.mainWeaponNum,
			baseReload = weaponData.baseReload,
			appliedReloadMult = false,
			lastReloadState = false,
			lastShotFrame = false,
			wasReady = false,
			initialized = false,
		}
	end
end

function gadget:UnitCreated(unitID, unitDefID)
	TrackUnit(unitID, unitDefID)
end

function gadget:UnitFinished(unitID, unitDefID)
	TrackUnit(unitID, unitDefID)
end

function gadget:UnitGiven(unitID, unitDefID)
	TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID))
end

function gadget:UnitTaken(unitID, unitDefID)
	TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID))
end

function gadget:UnitDestroyed(unitID)
	if trackedUnits[unitID] then
		RemoveUnitEffect(unitID)
		trackedUnits[unitID] = nil
	end
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES ~= 0 then
		return
	end

	UpdateCardActivation()
	if frame % SWEEP_FRAMES == 0 then
		for allyTeamID in pairs(allyTeamActive) do
			SweepAllyTeam(allyTeamID)
		end
	end

	for unitID, data in pairs(trackedUnits) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or unitDefID ~= data.unitDefID then
			RemoveUnitEffect(unitID)
			trackedUnits[unitID] = nil
		else
			local allyTeamID = GetTeamAllyTeam(teamID)
			if allyTeamActive[allyTeamID] then
				ApplyUnitUpdate(unitID, data, frame)
			else
				RestoreUnit(unitID, data)
			end
		end
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end

function gadget:Shutdown()
	for unitID in pairs(trackedUnits) do
		RemoveUnitEffect(unitID)
	end
end
