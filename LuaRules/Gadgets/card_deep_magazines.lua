function gadget:GetInfo()
	return {
		name = "Card Effect - Deep Magazines",
		desc = "Applies the Deep Magazines card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 209
local UPDATE_FRAMES = 30
local RELOAD_MULT = 2 / 3
local EFFECT_KEY_PREFIX = "zk_cards_deep_magazines_"

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitWeaponState = Spring.GetUnitWeaponState
local spSetUnitWeaponState = Spring.SetUnitWeaponState

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID, weaponNum)
	return EFFECT_KEY_PREFIX .. unitID .. "_" .. weaponNum
end

local function RemoveUnitEffects(unitID, data)
	if not data then
		return
	end
	if GG.Attributes then
		for weaponNum in pairs(data.effects or {}) do
			GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID, weaponNum))
		end
	end
	for weaponNum, baseBurst in pairs(data.baseBurst or {}) do
		spSetUnitWeaponState(unitID, weaponNum, "burst", baseBurst)
	end
end

local function GetBaseBurst(unitID, weaponNum, weaponDef)
	return spGetUnitWeaponState(unitID, weaponNum, "burst") or weaponDef.salvoSize or 1
end

local function ApplyUnitEffects(unitID, unitDefID, data)
	local weapons = UnitDefs[unitDefID].weapons or {}
	data.effects = {}
	data.baseBurst = {}
	for weaponNum = 1, #weapons do
		local weaponDef = WeaponDefs[weapons[weaponNum].weaponDef]
		if weaponDef then
			local baseBurst = GetBaseBurst(unitID, weaponNum, weaponDef)
			local baseProjectiles = weaponDef.projectiles or 1
			local effect = {
				weaponNum = weaponNum,
				reload = RELOAD_MULT,
				static = true,
			}
			if weaponDef.type ~= "BeamLaser" and baseBurst > 1 then
				data.baseBurst[weaponNum] = baseBurst
				spSetUnitWeaponState(unitID, weaponNum, "burst", math.ceil(baseBurst * 1.5))
				data.effects[weaponNum] = true
				if GG.Attributes then
					GG.Attributes.AddEffect(unitID, GetEffectKey(unitID, weaponNum), effect)
				end
			elseif baseProjectiles > 1 then
				effect.projectiles = math.ceil(baseProjectiles * 1.5) / baseProjectiles
				data.effects[weaponNum] = true
				if GG.Attributes then
					GG.Attributes.AddEffect(unitID, GetEffectKey(unitID, weaponNum), effect)
				end
			end
		end
	end
	if next(data.effects) == nil then
		data.effects = nil
	end
	if next(data.baseBurst) == nil then
		data.baseBurst = nil
	end
end

local function UntrackUnit(unitID)
	local data = trackedUnits[unitID]
	if data then
		RemoveUnitEffects(unitID, data)
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
	local data = {
		allyTeamID = allyTeamID,
	}
	trackedUnits[unitID] = data
	if allyTeamActive[allyTeamID] then
		ApplyUnitEffects(unitID, unitDefID, data)
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
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
