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
local RELOAD_TIME_MULT = 1.25
local RANGE_FLOOR = 0.01
local EFFECT_KEY_PREFIX = "zk_cards_point_defense_"

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitWeaponTarget = Spring.GetUnitWeaponTarget

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}
local TARGET_TYPE_UNIT = 1
local TARGET_TYPE_POS = 2
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
	mahlazer = true,
	raveparty = true,
	shieldfelon = true,
	shipaa = true,
	shipassault = true,
	shipcarrier = true,
	slicer = true,
	staticnuke = true,
	striderbantha = true,
	striderdante = true,
	striderdetriment = true,
	tankheavyassault = true,
	turretheavy = true,
	zenith = true,
}
local forcedMainWeaponByDefName = {
}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function IsFiniteNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
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

local function GetWeaponHoldFrames(weaponDef)
	if not weaponDef then
		return 0
	end

	local beamTime = tonumber(weaponDef.beamTime or weaponDef.beamtime) or 0
	local beamTtl = tonumber(weaponDef.beamttl) or 0
	local holdFrames = math.max(beamTime * Game.gameSpeed, beamTtl)
	if not IsFiniteNumber(holdFrames) or holdFrames <= 0 then
		return 0
	end
	return math.ceil(holdFrames)
end

local function GetWeaponVolleyFrames(weaponDef)
	if not weaponDef then
		return 0
	end

	local customParams = weaponDef.customParams or weaponDef.customparams
	local salvoSize = tonumber((customParams and customParams.script_burst) or weaponDef.salvoSize) or 1
	local salvoDelay = tonumber(weaponDef.salvoDelay) or 0
	if salvoSize <= 1 or salvoDelay <= 0 then
		return 0
	end

	local volleyFrames = (salvoSize - 1) * salvoDelay * Game.gameSpeed
	if not IsFiniteNumber(volleyFrames) or volleyFrames <= 0 then
		return 0
	end
	return math.ceil(volleyFrames)
end

local function GetWeaponCycleData(weaponDef)
	if not weaponDef then
		return 0, 0, false
	end

	local customParams = weaponDef.customParams or weaponDef.customparams
	local salvoSize = tonumber((customParams and customParams.script_burst) or weaponDef.salvoSize) or 1
	return GetWeaponHoldFrames(weaponDef), GetWeaponVolleyFrames(weaponDef), (salvoSize > 1)
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
			local holdFrames, volleyFrames, useBurstEnd = GetWeaponCycleData(weaponDef)
			return {
				mainWeaponNum = forcedWeaponNum,
				mainWeaponDefID = weaponDefID,
				baseReload = weaponDef.reload,
				baseRange = weaponDef.range,
				holdFrames = holdFrames,
				volleyFrames = volleyFrames,
				useBurstEnd = useBurstEnd,
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
		local weaponDef = WeaponDefs[unitDef.weapons[bestCandidate.mainWeaponNum].weaponDef]
		local holdFrames, volleyFrames, useBurstEnd = GetWeaponCycleData(weaponDef)
		return {
			mainWeaponNum = bestCandidate.mainWeaponNum,
			mainWeaponDefID = unitDef.weapons[bestCandidate.mainWeaponNum].weaponDef,
			baseReload = bestCandidate.baseReload,
			baseRange = weaponDef.range,
			holdFrames = holdFrames,
			volleyFrames = volleyFrames,
			useBurstEnd = useBurstEnd,
		}
	end
	if bestFallback then
		local weaponDef = WeaponDefs[unitDef.weapons[bestFallback.mainWeaponNum].weaponDef]
		local holdFrames, volleyFrames, useBurstEnd = GetWeaponCycleData(weaponDef)
		return {
			mainWeaponNum = bestFallback.mainWeaponNum,
			mainWeaponDefID = unitDef.weapons[bestFallback.mainWeaponNum].weaponDef,
			baseReload = bestFallback.baseReload,
			baseRange = weaponDef.range,
			holdFrames = holdFrames,
			volleyFrames = volleyFrames,
			useBurstEnd = useBurstEnd,
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
						mainWeaponDefID = weaponData.mainWeaponDefID,
						baseReload = weaponData.baseReload,
						baseRange = weaponData.baseRange,
						holdFrames = weaponData.holdFrames or 0,
						volleyFrames = weaponData.volleyFrames or 0,
						useBurstEnd = weaponData.useBurstEnd or false,
						appliedReloadMult = false,
						lastShotFrame = false,
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

local function GetExternalReloadMult(unitID, ownReloadMult)
	local totalReloadMult = spGetUnitRulesParam(unitID, "totalReloadSpeedChange") or 1
	if not IsFiniteNumber(totalReloadMult) or totalReloadMult <= 0 then
		totalReloadMult = 1
	end

	local appliedReloadMult = ownReloadMult
	if not IsFiniteNumber(appliedReloadMult) or appliedReloadMult <= 0 then
		appliedReloadMult = 1
	end

	local externalReloadMult = totalReloadMult / appliedReloadMult
	if not IsFiniteNumber(externalReloadMult) or externalReloadMult <= 0 then
		externalReloadMult = 1
	end

	return math.max(externalReloadMult, 0.0001)
end

local function RestoreUnit(unitID, data)
	RemoveUnitEffect(unitID)
	data.appliedReloadMult = false
	data.lastShotFrame = false
end

local function GetCurrentTargetDistanceFrac(unitID, weaponNum, baseRange)
	if not unitID or not weaponNum or not IsFiniteNumber(baseRange) or baseRange <= 0 then
		return nil
	end

	local ux, _, uz = spGetUnitPosition(unitID)
	if not ux or not uz then
		return nil
	end

	local targetType, _, targetData = spGetUnitWeaponTarget(unitID, weaponNum)
	local tx, tz
	if targetType == TARGET_TYPE_UNIT then
		tx, _, tz = spGetUnitPosition(targetData)
	elseif targetType == TARGET_TYPE_POS and type(targetData) == "table" then
		tx, tz = targetData[1], targetData[3]
	end

	if not tx or not tz then
		return nil
	end

	local dx = tx - ux
	local dz = tz - uz
	local distance = math.sqrt(dx * dx + dz * dz)
	if not IsFiniteNumber(distance) then
		return nil
	end

	return math.min(math.max(distance / baseRange, RANGE_FLOOR), 1)
end

local function ApplyUnitUpdate(unitID, data, gameFrame)
	local targetReloadSeconds = FAST_RELOAD_FRAMES / Game.gameSpeed
	local fallbackReloadSeconds = data.baseReload / GetExternalReloadMult(unitID, data.appliedReloadMult)
	local mainReloadSeconds = fallbackReloadSeconds
	if not IsFiniteNumber(mainReloadSeconds) or mainReloadSeconds <= 0 then
		mainReloadSeconds = fallbackReloadSeconds
	end
	local rampReloadSeconds = mainReloadSeconds * RELOAD_TIME_MULT
	if not IsFiniteNumber(rampReloadSeconds) or rampReloadSeconds <= 0 then
		rampReloadSeconds = fallbackReloadSeconds * RELOAD_TIME_MULT
	end

	local targetDistanceFrac = GetCurrentTargetDistanceFrac(unitID, data.mainWeaponNum, data.baseRange)
	local desiredReloadSeconds = targetReloadSeconds
	if targetDistanceFrac then
		desiredReloadSeconds = math.max(targetReloadSeconds, rampReloadSeconds * targetDistanceFrac)
	end

	local reloadMult = mainReloadSeconds / desiredReloadSeconds
	if not IsFiniteNumber(reloadMult) or reloadMult <= 0 then
		reloadMult = 1
	end

	if not data.lastShotFrame then
		data.lastShotFrame = gameFrame - math.ceil(math.max(rampReloadSeconds * Game.gameSpeed, 1))
	end

	local shotResetFrame = (data.lastShotFrame or gameFrame) + (data.holdFrames or 0)
	local rangeMult
	if gameFrame < shotResetFrame then
		rangeMult = 1
	else
		local elapsed = math.max(0, gameFrame - shotResetFrame)
		local progress = math.min(1, elapsed / math.max(rampReloadSeconds * Game.gameSpeed, 1))
		rangeMult = RANGE_FLOOR + (1 - RANGE_FLOOR) * progress
	end
	if not IsFiniteNumber(rangeMult) or rangeMult <= 0 then
		rangeMult = 1
	end

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
			mainWeaponDefID = weaponData.mainWeaponDefID,
			baseReload = weaponData.baseReload,
			baseRange = weaponData.baseRange,
			holdFrames = weaponData.holdFrames or 0,
			volleyFrames = weaponData.volleyFrames or 0,
			useBurstEnd = weaponData.useBurstEnd or false,
			appliedReloadMult = false,
			lastShotFrame = false,
		}
	end
end

local function MarkWeaponCycle(unitID, data, frame)
	local triggerWindowFrames = math.max(data.holdFrames or 0, data.volleyFrames or 0)
	if data.lastShotFrame and frame <= data.lastShotFrame + triggerWindowFrames then
		return
	end
	data.lastShotFrame = frame
end

function gadget:ScriptFireWeapon(unitID, unitDefID, weaponNum)
	local data = trackedUnits[unitID]
	if not data or unitDefID ~= data.unitDefID or weaponNum ~= data.mainWeaponNum then
		return
	end

	local teamID = spGetUnitTeam(unitID)
	local allyTeamID = GetTeamAllyTeam(teamID)
	if not allyTeamActive[allyTeamID] then
		return
	end

	MarkWeaponCycle(unitID, data, spGetGameFrame())
end

function gadget:ScriptEndBurst(unitID, unitDefID, weaponNum)
	local data = trackedUnits[unitID]
	if not data or unitDefID ~= data.unitDefID or weaponNum ~= data.mainWeaponNum or not data.useBurstEnd then
		return
	end

	local teamID = spGetUnitTeam(unitID)
	local allyTeamID = GetTeamAllyTeam(teamID)
	if not allyTeamActive[allyTeamID] then
		return
	end

	local frame = spGetGameFrame()
	if not data.lastShotFrame or frame > data.lastShotFrame then
		data.lastShotFrame = frame
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

	local unitsToRemove

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
			unitsToRemove = unitsToRemove or {}
			unitsToRemove[#unitsToRemove + 1] = unitID
		else
			local allyTeamID = GetTeamAllyTeam(teamID)
			if allyTeamActive[allyTeamID] then
				ApplyUnitUpdate(unitID, data, frame)
			else
				RestoreUnit(unitID, data)
			end
		end
	end

	if unitsToRemove then
		for i = 1, #unitsToRemove do
			trackedUnits[unitsToRemove[i]] = nil
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
