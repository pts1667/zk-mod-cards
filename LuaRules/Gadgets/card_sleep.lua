function gadget:GetInfo()
	return {
		name = "Card Effect - Sleep",
		desc = "Applies the Sleep card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 309
local UPDATE_FRAMES = 15
local SLEEP_INTERVAL_FRAMES = 5 * 60 * Game.gameSpeed
local SLEEP_DURATION_FRAMES = 30 * Game.gameSpeed
local HEAL_PER_SECOND = 2
local HEAL_PER_TICK = HEAL_PER_SECOND * UPDATE_FRAMES / Game.gameSpeed
local EFFECT_KEY_PREFIX = "zk_cards_sleep_"
local INLOS_ACCESS = {inlos = true}

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitTeam = Spring.GetUnitTeam
local spSetGameRulesParam = Spring.SetGameRulesParam
local spSetUnitHealth = Spring.SetUnitHealth
local spSetUnitRulesParam = Spring.SetUnitRulesParam

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function IsMobile(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef and not unitDef.isImmobile and true or false
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function ClearSleepVisuals(unitID)
	if GG.TintUnit then
		GG.TintUnit(unitID)
	end
	if GG.GlowUnit then
		GG.GlowUnit(unitID)
	end
end

local function ApplySleepVisuals(unitID)
	if GG.TintUnit then
		GG.TintUnit(unitID, 0.62, 0.76, 1.0)
	end
	if GG.GlowUnit then
		GG.GlowUnit(unitID, 0.50, 0.65, 1.0, 0.35)
	end
end

local function ClearSleepState(unitID)
	local data = trackedUnits[unitID]
	if not data then
		return
	end
	data.sleepEndFrame = nil
	data.nextSleepFrame = spGetGameFrame() + SLEEP_INTERVAL_FRAMES
	local alive = spGetUnitDefID(unitID) ~= nil
	if GG.Attributes and alive then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
	if alive then
		ClearSleepVisuals(unitID)
		spSetUnitRulesParam(unitID, "zk_cards_sleeping", 0, INLOS_ACCESS)
		spSetUnitRulesParam(unitID, "zk_cards_sleep_end", -1, INLOS_ACCESS)
	end
end

local function BeginSleep(unitID, frame)
	local data = trackedUnits[unitID]
	if not data then
		return
	end
	data.sleepEndFrame = frame + SLEEP_DURATION_FRAMES
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			move = 0.01,
			reload = 0.01,
			build = 0.01,
			abilityDisabled = true,
			shieldDisabled = true,
		})
	end
	ApplySleepVisuals(unitID)
	spSetUnitRulesParam(unitID, "zk_cards_sleeping", 1, INLOS_ACCESS)
	spSetUnitRulesParam(unitID, "zk_cards_sleep_end", data.sleepEndFrame, INLOS_ACCESS)
end

local function TrackUnit(unitID, unitDefID, teamID)
	if not unitDefID or not IsMobile(unitDefID) then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	local frame = spGetGameFrame()
	trackedUnits[unitID] = trackedUnits[unitID] or {}
	trackedUnits[unitID].allyTeamID = allyTeamID
	trackedUnits[unitID].nextSleepFrame = trackedUnits[unitID].nextSleepFrame or (frame + SLEEP_INTERVAL_FRAMES)
	spSetUnitRulesParam(unitID, "zk_cards_sleeping", 0, INLOS_ACCESS)
	spSetUnitRulesParam(unitID, "zk_cards_sleep_end", -1, INLOS_ACCESS)
end

local function UntrackUnit(unitID)
	ClearSleepState(unitID)
	trackedUnits[unitID] = nil
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

local function UpdateUnits(frame)
	for unitID, data in pairs(trackedUnits) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or not IsMobile(unitDefID) then
			UntrackUnit(unitID)
		else
			data.allyTeamID = GetTeamAllyTeam(teamID)
			local health, maxHealth, _, _, buildProgress = spGetUnitHealth(unitID)
			if not health or not maxHealth then
				UntrackUnit(unitID)
			elseif data.sleepEndFrame then
				if frame >= data.sleepEndFrame then
					ClearSleepState(unitID)
				elseif buildProgress == 1 then
					spSetUnitHealth(unitID, math.min(maxHealth, health + HEAL_PER_TICK))
				end
			elseif allyTeamActive[data.allyTeamID] and buildProgress == 1 and frame >= (data.nextSleepFrame or 0) then
				BeginSleep(unitID, frame)
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackUnit(unitID, unitDefID, teamID)
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	TrackUnit(unitID, unitDefID, teamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitDestroyed(unitID)
	UntrackUnit(unitID)
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		UpdateUnits(frame)
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	spSetGameRulesParam("zk_cards_sleep_duration", SLEEP_DURATION_FRAMES)
	UpdateCardActivation()
end

function gadget:Shutdown()
	for unitID in pairs(trackedUnits) do
		UntrackUnit(unitID)
	end
end
