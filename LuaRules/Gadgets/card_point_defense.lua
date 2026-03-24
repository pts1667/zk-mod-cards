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
local UPDATE_FRAMES = 3
local FAST_RELOAD_FRAMES = 2
local RANGE_FLOOR = 0.01
local EFFECT_KEY_PREFIX = "zk_cards_point_defense_"
local HALF_FRAME = 1 / (2 * Game.gameSpeed)

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitWeaponState = Spring.GetUnitWeaponState
local spSetUnitWeaponDamages = Spring.SetUnitWeaponDamages
local spSetUnitWeaponState = Spring.SetUnitWeaponState
local spValidUnitID = Spring.ValidUnitID

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID, weaponNum)
	return EFFECT_KEY_PREFIX .. unitID .. "_" .. weaponNum
end

local function GetUnitEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID .. "_unit"
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

local function BuildWeaponData(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	if not unitDef then
		return nil
	end
	local weapons = {}
	for weaponNum = 1, #(unitDef.weapons or {}) do
		local weaponDef = WeaponDefs[unitDef.weapons[weaponNum].weaponDef]
		if weaponDef and not weaponDef.stockpile and (weaponDef.range or 0) > 0 and (weaponDef.reload or 0) > 0 then
			weapons[#weapons + 1] = {
				weaponNum = weaponNum,
				baseReload = weaponDef.reload,
				baseRange = weaponDef.range,
				baseBurstRate = weaponDef.salvoDelay,
				usesScriptReload = weaponDef.customParams and (weaponDef.customParams.script_reload or weaponDef.customParams.script_burst),
				lastReloadState = false,
				lastShotFrame = false,
			}
		end
	end
	if #weapons == 0 then
		return nil
	end
	return weapons
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID and not trackedUnits[unitID] then
				local weapons = BuildWeaponData(unitDefID)
				if weapons then
					trackedUnits[unitID] = {
						unitDefID = unitDefID,
						weapons = weapons,
					}
				end
			end
		end
	end
end

local function RemoveWeaponEffect(unitID, weaponNum)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID, weaponNum))
	end
end

local function RemoveUnitEffect(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetUnitEffectKey(unitID))
	end
end

local function RestoreWeapon(unitID, weaponData, gameFrame)
	local reloadState = spGetUnitWeaponState(unitID, weaponData.weaponNum, "reloadState")
	local reloadTime = spGetUnitWeaponState(unitID, weaponData.weaponNum, "reloadTime")
	local nextReload = reloadState
	if reloadState and reloadTime and reloadTime > 0 then
		nextReload = gameFrame + (reloadState - gameFrame) * weaponData.baseReload / reloadTime
	end
	spSetUnitWeaponState(unitID, weaponData.weaponNum, {
		reloadTime = weaponData.baseReload + HALF_FRAME,
		reloadState = nextReload or reloadState,
	})
	if weaponData.baseBurstRate then
		spSetUnitWeaponState(unitID, weaponData.weaponNum, "burstRate", weaponData.baseBurstRate + HALF_FRAME)
	end
	if weaponData.appliedRangeMult then
		local currentRange = spGetUnitWeaponState(unitID, weaponData.weaponNum, "range") or weaponData.baseRange
		local restoredRange = currentRange / weaponData.appliedRangeMult
		spSetUnitWeaponState(unitID, weaponData.weaponNum, "range", restoredRange)
		spSetUnitWeaponDamages(unitID, weaponData.weaponNum, "dynDamageRange", restoredRange)
	end
	RemoveWeaponEffect(unitID, weaponData.weaponNum)
	weaponData.lastReloadState = false
	weaponData.lastShotFrame = false
	weaponData.wasReady = false
	weaponData.appliedRangeMult = false
	weaponData.initialized = false
end

local function ApplyWeaponUpdate(unitID, weaponData, gameFrame, fastReloadSeconds)
	local reloadState = spGetUnitWeaponState(unitID, weaponData.weaponNum, "reloadState")
	if reloadState then
		local isReady = reloadState <= gameFrame + 0.5
		if weaponData.lastReloadState and reloadState > weaponData.lastReloadState + 0.5 then
			weaponData.lastShotFrame = gameFrame
		elseif weaponData.wasReady and not isReady then
			weaponData.lastShotFrame = gameFrame
		elseif not weaponData.initialized then
			weaponData.lastShotFrame = gameFrame
		end
		weaponData.wasReady = isReady
		weaponData.lastReloadState = reloadState
	end
	weaponData.initialized = true

	local elapsed = math.max(0, gameFrame - (weaponData.lastShotFrame or gameFrame))
	local progress = math.min(1, elapsed / (weaponData.baseReload * Game.gameSpeed))
	local rangeMult = RANGE_FLOOR + (1 - RANGE_FLOOR) * progress
	local currentRange = spGetUnitWeaponState(unitID, weaponData.weaponNum, "range") or weaponData.baseRange
	local baselineRange = currentRange
	if weaponData.appliedRangeMult and weaponData.appliedRangeMult > 0 then
		baselineRange = currentRange / weaponData.appliedRangeMult
	end
	local moddedRange = baselineRange * rangeMult
	spSetUnitWeaponState(unitID, weaponData.weaponNum, "range", moddedRange)
	spSetUnitWeaponDamages(unitID, weaponData.weaponNum, "dynDamageRange", moddedRange)
	weaponData.appliedRangeMult = rangeMult

	spSetUnitWeaponState(unitID, weaponData.weaponNum, {
		reloadTime = fastReloadSeconds + HALF_FRAME,
	})
	if weaponData.baseBurstRate then
		local burstRate = weaponData.baseBurstRate * fastReloadSeconds / weaponData.baseReload
		spSetUnitWeaponState(unitID, weaponData.weaponNum, "burstRate", burstRate + HALF_FRAME)
	end
end

local function TrackUnit(unitID, unitDefID)
	if not trackedUnits[unitID] then
		local weapons = BuildWeaponData(unitDefID)
		if weapons then
			trackedUnits[unitID] = {
				unitDefID = unitDefID,
				weapons = weapons,
			}
		end
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
	local data = trackedUnits[unitID]
	if data then
		for i = 1, #data.weapons do
			RemoveWeaponEffect(unitID, data.weapons[i].weaponNum)
		end
		RemoveUnitEffect(unitID)
		trackedUnits[unitID] = nil
	end
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES ~= 0 then
		return
	end

	UpdateCardActivation()
	for allyTeamID in pairs(allyTeamActive) do
		SweepAllyTeam(allyTeamID)
	end

	for unitID, data in pairs(trackedUnits) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or unitDefID ~= data.unitDefID then
			for i = 1, #(data.weapons or {}) do
				RemoveWeaponEffect(unitID, data.weapons[i].weaponNum)
			end
			RemoveUnitEffect(unitID)
			trackedUnits[unitID] = nil
		else
			local allyTeamID = GetTeamAllyTeam(teamID)
			local fastReloadSeconds = FAST_RELOAD_FRAMES / Game.gameSpeed
			local scriptReloadMult = false
			for i = 1, #data.weapons do
				if allyTeamActive[allyTeamID] then
					local weaponData = data.weapons[i]
					ApplyWeaponUpdate(unitID, weaponData, frame, fastReloadSeconds)
					if weaponData.usesScriptReload then
						local neededMult = weaponData.baseReload / fastReloadSeconds
						scriptReloadMult = math.max(scriptReloadMult or 1, neededMult)
					end
				else
					RestoreWeapon(unitID, data.weapons[i], frame)
				end
			end
			if allyTeamActive[allyTeamID] and scriptReloadMult and GG.Attributes then
				GG.Attributes.AddEffect(unitID, GetUnitEffectKey(unitID), {
					reload = scriptReloadMult,
					static = true,
				})
			else
				RemoveUnitEffect(unitID)
			end
		end
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end

function gadget:Shutdown()
	local gameFrame = spGetGameFrame()
	for unitID, data in pairs(trackedUnits) do
		for i = 1, #data.weapons do
			if spValidUnitID(unitID) then
				RestoreWeapon(unitID, data.weapons[i], gameFrame)
			else
				RemoveWeaponEffect(unitID, data.weapons[i].weaponNum)
			end
		end
		RemoveUnitEffect(unitID)
	end
end
