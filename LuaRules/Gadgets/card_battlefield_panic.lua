function gadget:GetInfo()
	return {
		name = "Card Effect - Battlefield Panic",
		desc = "Applies the Battlefield Panic card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 306
local UPDATE_FRAMES = 15
local PANIC_RADIUS = 450
local SLOW_DURATION_FRAMES = math.floor(2 * Game.gameSpeed)
local DISARM_DURATION_FRAMES = math.floor(1.25 * Game.gameSpeed)
local DISARM_DAMAGE_MULT = 1.1
local SLOW_MULT = 0.65
local EFFECT_KEY_PREFIX = "zk_cards_battlefield_panic_"

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitsInSphere = Spring.GetUnitsInSphere

local gaiaAllyTeam
local allyTeamActive = {}
local panicState = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function ApplyPanicSlow(unitID, expireFrame)
	panicState[unitID] = expireFrame
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			move = SLOW_MULT,
			reload = SLOW_MULT,
			build = SLOW_MULT,
			static = true,
		})
	end
end

local function RemovePanicSlow(unitID)
	panicState[unitID] = nil
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
end

local function ApplyTemporaryDisarm(unitID)
	if GG.addParalysisDamageToUnit then
		local health = spGetUnitHealth(unitID)
		if health and health > 0 then
			GG.addParalysisDamageToUnit(unitID, health * DISARM_DAMAGE_MULT, DISARM_DURATION_FRAMES, 0)
		end
	end
end

local function IsFinishedUnit(unitID)
	local unitDefID = spGetUnitDefID(unitID)
	if not unitDefID then
		return false
	end
	local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
	return buildProgress == 1
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

local function ExpirePanic(frame)
	for unitID, expireFrame in pairs(panicState) do
		if expireFrame <= frame or not spGetUnitDefID(unitID) then
			RemovePanicSlow(unitID)
		end
	end
end

function gadget:UnitDestroyed(unitID, unitDefID, teamID)
	RemovePanicSlow(unitID)
	local allyTeamID = GetTeamAllyTeam(teamID)
	if not allyTeamActive[allyTeamID] then
		return
	end

	local x, y, z = spGetUnitPosition(unitID)
	if not x then
		return
	end

	local frame = spGetGameFrame()
	for _, otherUnitID in ipairs(spGetUnitsInSphere(x, y, z, PANIC_RADIUS) or {}) do
		if otherUnitID ~= unitID and IsFinishedUnit(otherUnitID) then
			local otherTeamID = spGetUnitTeam(otherUnitID)
			if GetTeamAllyTeam(otherTeamID) == allyTeamID then
				if math.random() < 0.25 then
					ApplyTemporaryDisarm(otherUnitID)
				else
					ApplyPanicSlow(otherUnitID, frame + SLOW_DURATION_FRAMES)
				end
			end
		end
	end
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		ExpirePanic(frame)
	end
end

function gadget:Shutdown()
	for unitID in pairs(panicState) do
		RemovePanicSlow(unitID)
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
