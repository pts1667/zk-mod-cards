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
	RemoveWeaponEffect(unitID, weaponData.weaponNum)
	weaponData.lastReloadState = false
	weaponData.lastShotFrame = false
end

local function ApplyWeaponUpdate(unitID, weaponData, gameFrame)
	local reloadState = spGetUnitWeaponState(unitID, weaponData.weaponNum, "reloadState")
	if reloadState then
		if weaponData.lastReloadState and reloadState > weaponData.lastReloadState + 0.5 then
			weaponData.lastShotFrame = gameFrame
		elseif not weaponData.lastReloadState and reloadState > gameFrame then
			weaponData.lastShotFrame = gameFrame
		end
		weaponData.lastReloadState = reloadState
	end

	local rangeMult = 1
	if weaponData.lastShotFrame then
		local elapsed = math.max(0, gameFrame - weaponData.lastShotFrame)
		local progress = math.min(1, elapsed / (weaponData.baseReload * Game.gameSpeed))
		rangeMult = RANGE_FLOOR + (1 - RANGE_FLOOR) * progress
	end

	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID, weaponData.weaponNum), {
			weaponNum = weaponData.weaponNum,
			range = rangeMult,
			static = true,
		})
	end

	spSetUnitWeaponState(unitID, weaponData.weaponNum, {
		reloadTime = FAST_RELOAD_FRAMES / Game.gameSpeed + HALF_FRAME,
	})
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
			trackedUnits[unitID] = nil
		else
			local allyTeamID = GetTeamAllyTeam(teamID)
			for i = 1, #data.weapons do
				if allyTeamActive[allyTeamID] then
					ApplyWeaponUpdate(unitID, data.weapons[i], frame)
				else
					RestoreWeapon(unitID, data.weapons[i], frame)
				end
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
	end
end
