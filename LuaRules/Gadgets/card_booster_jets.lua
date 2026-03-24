function gadget:GetInfo()
	return {
		name = "Card Effect - Booster Jets",
		desc = "Applies the Booster Jets card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 215
local UPDATE_FRAMES = 5
local CHECK_FRAMES = 15
local BOOST_DURATION = 4 * Game.gameSpeed
local BOOST_COOLDOWN = 30 * Game.gameSpeed
local BOOST_MOVE_MULT = 2.5
local BOOST_IMPULSE = 3.2
local BOOST_SEARCH_MULT = 1.5
local EFFECT_KEY_PREFIX = "zk_cards_booster_jets_"
local ACTIVE_RULES_PARAM = "zk_cards_booster_jets_active"
local INLOS_ACCESS = {inlos = true}

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitIsStunned = Spring.GetUnitIsStunned
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitsInSphere = Spring.GetUnitsInSphere
local spGetUnitTransporter = Spring.GetUnitTransporter
local spAddUnitImpulse = Spring.AddUnitImpulse
local spSetUnitRulesParam = Spring.SetUnitRulesParam

local CMD_ATTACK = CMD.ATTACK
local CMD_MOVE = CMD.MOVE
local CMD_FIGHT = CMD.FIGHT

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}
local boostState = {}
local eligibleDefs = {}

for _, name in ipairs({
	"amphassault",
	"amphriot",
	"cloakassault",
	"cloakriot",
	"jumpassault",
	"shieldassault",
	"shieldriot",
	"spiderassault",
	"spiderriot",
	"spideranarchid",
	"vehassault",
	"vehriot",
	"tankassault",
	"tankriot",
	"tankheavyassault",
	"tankheavyraid",
	"slicer",
	"striderdante",
}) do
	local unitDef = UnitDefNames[name]
	if unitDef then
		eligibleDefs[unitDef.id] = true
	end
end

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
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

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID and eligibleDefs[unitDefID] then
				trackedUnits[unitID] = true
			end
		end
	end
end

local function IsDisabled(unitID)
	return spGetUnitTransporter(unitID) or spGetUnitIsStunned(unitID) or spGetUnitRulesParam(unitID, "disarmed") == 1
end

local function ApplyBoostEffect(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			move = BOOST_MOVE_MULT,
			static = true,
		})
	end
	spSetUnitRulesParam(unitID, ACTIVE_RULES_PARAM, 1, INLOS_ACCESS)
end

local function ClearBoostEffect(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
	spSetUnitRulesParam(unitID, ACTIVE_RULES_PARAM, 0, INLOS_ACCESS)
end

local function GetNearbyEnemy(unitID, teamID, searchRange)
	local x, y, z = spGetUnitPosition(unitID)
	if not x then
		return false
	end
	for _, otherID in ipairs(spGetUnitsInSphere(x, y, z, searchRange) or {}) do
		local otherTeam = spGetUnitTeam(otherID)
		if otherTeam and otherTeam ~= teamID and not Spring.AreTeamsAllied(teamID, otherTeam) then
			return true
		end
	end
	return false
end

local function GetGoalVector(unitID)
	local ux, uy, uz = spGetUnitPosition(unitID)
	if not ux then
		return nil
	end
	local cmdID, _, _, cp1, cp2, cp3 = spGetUnitCurrentCommand(unitID)
	if not cmdID then
		return nil
	end

	if cmdID == CMD_ATTACK and cp1 and not cp2 and cp1 > 0 then
		local tx, ty, tz = spGetUnitPosition(cp1)
		if tx then
			return tx - ux, tz - uz, cp1
		end
	elseif (cmdID == CMD_ATTACK or cmdID == CMD_MOVE or cmdID == CMD_FIGHT) and cp1 and cp3 then
		return cp1 - ux, cp3 - uz, false
	end

	return nil
end

local function ShouldTriggerBoost(unitID, unitDefID, teamID, frame)
	local state = boostState[unitID]
	if state and state.cooldownUntil and state.cooldownUntil > frame then
		return false
	end
	if IsDisabled(unitID) then
		return false
	end

	local dx, dz, targetID = GetGoalVector(unitID)
	if not dx then
		return false
	end

	local maxRange = UnitDefs[unitDefID].maxWeaponRange or 0
	if maxRange <= 0 then
		return false
	end
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance <= maxRange then
		return false
	end

	if targetID then
		return true
	end

	return GetNearbyEnemy(unitID, teamID, maxRange * BOOST_SEARCH_MULT)
end

local function StartBoost(unitID, frame)
	boostState[unitID] = boostState[unitID] or {}
	boostState[unitID].activeUntil = frame + BOOST_DURATION
	boostState[unitID].cooldownUntil = frame + BOOST_COOLDOWN
	ApplyBoostEffect(unitID)
end

local function UpdateActiveBoosts(frame)
	for unitID, state in pairs(boostState) do
		if state.activeUntil and state.activeUntil > frame then
			local dx, dz = GetGoalVector(unitID)
			if dx and dz and not IsDisabled(unitID) then
				local magnitude = math.sqrt(dx * dx + dz * dz)
				if magnitude > 0.001 then
					spAddUnitImpulse(unitID, (dx / magnitude) * BOOST_IMPULSE, 0, (dz / magnitude) * BOOST_IMPULSE)
				end
			end
			ApplyBoostEffect(unitID)
		else
			state.activeUntil = nil
			ClearBoostEffect(unitID)
			if not state.cooldownUntil or state.cooldownUntil <= frame then
				boostState[unitID] = nil
			end
		end
	end
end

local function TrackUnit(unitID, unitDefID)
	if eligibleDefs[unitDefID] then
		trackedUnits[unitID] = true
	end
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam, damage)
	local state = boostState[unitID]
	if state and state.activeUntil and state.activeUntil > Spring.GetGameFrame() then
		return damage * 0.5
	end
	return damage
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
	trackedUnits[unitID] = nil
	boostState[unitID] = nil
	ClearBoostEffect(unitID)
end

function gadget:GameFrame(frame)
	if frame % CHECK_FRAMES == 0 then
		UpdateCardActivation()
		for allyTeamID in pairs(allyTeamActive) do
			SweepAllyTeam(allyTeamID)
		end
		for unitID in pairs(trackedUnits) do
			local unitDefID = spGetUnitDefID(unitID)
			local teamID = spGetUnitTeam(unitID)
			if not unitDefID or not teamID or not eligibleDefs[unitDefID] then
				trackedUnits[unitID] = nil
				boostState[unitID] = nil
				ClearBoostEffect(unitID)
			else
				local allyTeamID = GetTeamAllyTeam(teamID)
				if allyTeamActive[allyTeamID] and ShouldTriggerBoost(unitID, unitDefID, teamID, frame) then
					StartBoost(unitID, frame)
				end
			end
		end
	end

	if frame % UPDATE_FRAMES == 0 then
		UpdateActiveBoosts(frame)
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end

function gadget:Shutdown()
	for unitID in pairs(trackedUnits) do
		ClearBoostEffect(unitID)
	end
end
