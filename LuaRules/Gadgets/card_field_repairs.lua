function gadget:GetInfo()
	return {
		name = "Card Effect - Field Repairs",
		desc = "Applies the Field Repairs card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 208
local UPDATE_FRAMES = 15
local REPAIR_DELAY_FRAMES = 10 * Game.gameSpeed
local HEAL_FRACTION_PER_TICK = 0.005

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitCommandCount = Spring.GetUnitCommandCount
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spSetUnitHealth = Spring.SetUnitHealth
local spGetUnitIsStunned = Spring.GetUnitIsStunned

local gaiaAllyTeam
local allyTeamActive = {}
local trackedMobiles = {}
local lastDamagedFrame = {}
local currentFrame = 0

local function IsMobile(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef and not unitDef.isImmobile and true or false
end

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function TrackMobile(unitID, unitDefID, teamID)
	if not IsMobile(unitDefID) then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedMobiles[unitID] = allyTeamID
	lastDamagedFrame[unitID] = currentFrame
end

local function UntrackMobile(unitID)
	trackedMobiles[unitID] = nil
	lastDamagedFrame[unitID] = nil
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID and IsMobile(unitDefID) then
				TrackMobile(unitID, unitDefID, teamID)
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

local function IsEligibleForHeal(unitID)
	local stunnedOrInBuild, _, inBuild = spGetUnitIsStunned(unitID)
	if stunnedOrInBuild or inBuild or spGetUnitRulesParam(unitID, "disarmed") == 1 then
		return false
	end
	if (spGetUnitCommandCount(unitID) or 0) > 0 then
		return false
	end
	return true
end

local function UpdateHealing()
	for unitID, allyTeamID in pairs(trackedMobiles) do
		local unitDefID = spGetUnitDefID(unitID)
		if not unitDefID or not IsMobile(unitDefID) then
			UntrackMobile(unitID)
		elseif allyTeamActive[allyTeamID] and (lastDamagedFrame[unitID] or currentFrame) + REPAIR_DELAY_FRAMES <= currentFrame and IsEligibleForHeal(unitID) then
			local health, maxHealth = spGetUnitHealth(unitID)
			if health and maxHealth and health < maxHealth then
				local regenMult = (GG.att_RegenChange and GG.att_RegenChange[unitID]) or 1
				spSetUnitHealth(unitID, health + maxHealth * HEAL_FRACTION_PER_TICK * regenMult)
			end
		end
	end
end

function gadget:UnitDamaged(unitID)
	if trackedMobiles[unitID] then
		lastDamagedFrame[unitID] = currentFrame
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackMobile(unitID, unitDefID, teamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	UntrackMobile(unitID)
	TrackMobile(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	UntrackMobile(unitID)
	TrackMobile(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitDestroyed(unitID)
	UntrackMobile(unitID)
end

function gadget:GameFrame(frame)
	currentFrame = frame
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		UpdateHealing()
	end
end

function gadget:Initialize()
	currentFrame = spGetGameFrame()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
