function gadget:GetInfo()
	return {
		name = "Card Effect - Pre-Charged Shields",
		desc = "Applies the Pre-Charged Shields card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 112
local UPDATE_FRAMES = 15
local EFFECT_KEY_PREFIX = "zk_cards_pre_charged_shields_"
local SHIELD_MULT = 10
local INLOS_ACCESS = {inlos = true}

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitTeam = Spring.GetUnitTeam
local spSetUnitRulesParam = Spring.SetUnitRulesParam
local spSetUnitShieldState = Spring.SetUnitShieldState

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function IsTrackableUnitDef(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	if not unitDef then
		return false
	end
	if unitDef.shieldWeaponDef then
		return true
	end
	local cp = unitDef.customParams
	return cp and cp.dynamic_comm and true or false
end

local function GetShieldInfo(unitID, unitDefID)
	local unitDef = UnitDefs[unitDefID]
	if not unitDef then
		return nil
	end

	local shieldWeaponDefID
	local shieldNum = -1
	local cp = unitDef.customParams
	if cp and cp.dynamic_comm and GG.Upgrades_UnitShieldDef then
		shieldWeaponDefID, shieldNum = GG.Upgrades_UnitShieldDef(unitID)
	else
		shieldWeaponDefID = unitDef.shieldWeaponDef
	end

	if not shieldWeaponDefID then
		return nil
	end

	local shieldWeaponDef = WeaponDefs[shieldWeaponDefID]
	if not shieldWeaponDef then
		return nil
	end

	return {
		weaponDefID = shieldWeaponDefID,
		shieldNum = shieldNum,
		maxCharge = shieldWeaponDef.shieldPower or 0,
	}
end

local function ClearShieldOverrides(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
	if spGetUnitDefID(unitID) then
		spSetUnitRulesParam(unitID, "shieldChargeDisabled", 0, INLOS_ACCESS)
		spSetUnitRulesParam(unitID, "zk_cards_disableShieldLink", 0, INLOS_ACCESS)
	end
end

local function EnsureTrackedUnit(unitID, unitDefID, teamID)
	if not IsTrackableUnitDef(unitDefID) then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedUnits[unitID] = trackedUnits[unitID] or {}
	trackedUnits[unitID].allyTeamID = allyTeamID
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID then
				EnsureTrackedUnit(unitID, unitDefID, teamID)
			end
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

local function UpdateTrackedUnits()
	for unitID, data in pairs(trackedUnits) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or not IsTrackableUnitDef(unitDefID) then
			ClearShieldOverrides(unitID)
			trackedUnits[unitID] = nil
		else
			local allyTeamID = GetTeamAllyTeam(teamID)
			data.allyTeamID = allyTeamID
			local shieldInfo = GetShieldInfo(unitID, unitDefID)
			if not (allyTeamActive[allyTeamID] and shieldInfo) then
				ClearShieldOverrides(unitID)
				data.appliedShieldWeaponDefID = nil
			else
				if GG.Attributes then
					GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
						shieldMax = SHIELD_MULT,
						static = true,
					})
				end
				spSetUnitRulesParam(unitID, "shieldChargeDisabled", 1, INLOS_ACCESS)
				spSetUnitRulesParam(unitID, "zk_cards_disableShieldLink", 1, INLOS_ACCESS)

				local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
				if buildProgress == 1 and data.appliedShieldWeaponDefID ~= shieldInfo.weaponDefID then
					spSetUnitShieldState(unitID, shieldInfo.shieldNum, shieldInfo.maxCharge * SHIELD_MULT)
					data.appliedShieldWeaponDefID = shieldInfo.weaponDefID
				end
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	EnsureTrackedUnit(unitID, unitDefID, teamID)
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	EnsureTrackedUnit(unitID, unitDefID, teamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	EnsureTrackedUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	EnsureTrackedUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitDestroyed(unitID)
	ClearShieldOverrides(unitID)
	trackedUnits[unitID] = nil
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		UpdateTrackedUnits()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
	UpdateTrackedUnits()
end

function gadget:Shutdown()
	for unitID in pairs(trackedUnits) do
		ClearShieldOverrides(unitID)
	end
end
