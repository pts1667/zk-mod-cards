function gadget:GetInfo()
	return {
		name = "Card Effect - Siege Doctrine",
		desc = "Applies the Siege Doctrine card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 111
local EFFECT_KEY_PREFIX = "zk_cards_siege_doctrine_"
local RANGE_MULT = 1.5
local MOVE_MULT = 0.75
local REAIM_MULT = 4 / 3

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spSetUnitWeaponState = Spring.SetUnitWeaponState
local spGetUnitWeaponState = Spring.GetUnitWeaponState

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function ResetReaim(unitID, data)
	if not (data and data.reaim) then
		return
	end
	for weaponNum, baseValue in pairs(data.reaim) do
		spSetUnitWeaponState(unitID, weaponNum, {reaimTime = baseValue})
	end
	data.reaim = nil
end

local function ApplyStaticReaim(unitID, unitDefID, data)
	local weapons = UnitDefs[unitDefID].weapons or {}
	if #weapons == 0 then
		return
	end
	data.reaim = {}
	for weaponNum = 1, #weapons do
		local current = spGetUnitWeaponState(unitID, weaponNum, "reaimTime")
		if current then
			data.reaim[weaponNum] = current
			spSetUnitWeaponState(unitID, weaponNum, {reaimTime = math.max(1, current * REAIM_MULT)})
		end
	end
	if next(data.reaim) == nil then
		data.reaim = nil
	end
end

local function ApplyUnitEffect(unitID, unitDefID, data)
	if not GG.Attributes then
		return
	end
	if data.immobile then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			range = RANGE_MULT,
			static = true,
		})
		if UnitDefs[unitDefID].maxWeaponRange and UnitDefs[unitDefID].maxWeaponRange > 0 then
			ApplyStaticReaim(unitID, unitDefID, data)
		end
	else
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			move = MOVE_MULT,
			static = true,
		})
	end
end

local function RemoveUnitEffect(unitID, data)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
	ResetReaim(unitID, data)
end

local function UntrackUnit(unitID)
	local data = trackedUnits[unitID]
	if data then
		RemoveUnitEffect(unitID, data)
		trackedUnits[unitID] = nil
	end
end

local function TrackUnit(unitID, unitDefID, teamID)
	UntrackUnit(unitID)
	if not unitDefID then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	local unitDef = UnitDefs[unitDefID]
	if not unitDef then
		return
	end
	local data = {
		allyTeamID = allyTeamID,
		immobile = unitDef.isImmobile and not (unitDef.customParams and unitDef.customParams.mobilebuilding),
	}
	trackedUnits[unitID] = data
	if allyTeamActive[allyTeamID] then
		ApplyUnitEffect(unitID, unitDefID, data)
	end
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			TrackUnit(unitID, spGetUnitDefID(unitID), teamID)
		end
	end
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam and not allyTeamActive[allyTeamID] and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
			SweepAllyTeam(allyTeamID)
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackUnit(unitID, unitDefID, teamID)
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	TrackUnit(unitID, unitDefID, teamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitDestroyed(unitID)
	UntrackUnit(unitID)
end

function gadget:GameFrame(frame)
	if frame % 30 == 0 then
		UpdateCardActivation()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
