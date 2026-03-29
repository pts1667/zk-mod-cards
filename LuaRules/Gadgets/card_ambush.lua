function gadget:GetInfo()
	return {
		name = "Card Effect - Ambush",
		desc = "Applies the Ambush card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 312
local UPDATE_FRAMES = 15
local DURATION_FRAMES = 5 * Game.gameSpeed
local COOLDOWN_FRAMES = 60 * Game.gameSpeed
local MOVE_MULT = 2.0
local RELOAD_MULT = 1.5
local EFFECT_KEY_PREFIX = "zk_cards_ambush_"

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function ClearAmbush(unitID, data)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
	if data then
		data.expireFrame = nil
	end
end

local function TrackUnit(unitID, teamID)
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedUnits[unitID] = trackedUnits[unitID] or {
		cooldownEndFrame = 0,
	}
	trackedUnits[unitID].allyTeamID = allyTeamID
end

local function UntrackUnit(unitID)
	ClearAmbush(unitID, trackedUnits[unitID])
	trackedUnits[unitID] = nil
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

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackUnit(unitID, teamID)
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	TrackUnit(unitID, teamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	TrackUnit(unitID, newTeamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	TrackUnit(unitID, newTeamID)
end

function gadget:UnitDestroyed(unitID)
	UntrackUnit(unitID)
end

function gadget:UnitDecloaked(unitID, unitDefID, teamID)
	local data = trackedUnits[unitID]
	if not data then
		TrackUnit(unitID, teamID)
		data = trackedUnits[unitID]
	end
	if not data then
		return
	end

	local allyTeamID = GetTeamAllyTeam(teamID)
	data.allyTeamID = allyTeamID
	if not allyTeamActive[allyTeamID] then
		return
	end

	local frame = spGetGameFrame()
	if frame < (data.cooldownEndFrame or 0) then
		return
	end

	data.cooldownEndFrame = frame + COOLDOWN_FRAMES
	data.expireFrame = frame + DURATION_FRAMES
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			move = MOVE_MULT,
			reload = RELOAD_MULT,
		})
	end
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES ~= 0 then
		return
	end

	UpdateCardActivation()
	for unitID, data in pairs(trackedUnits) do
		local teamID = spGetUnitTeam(unitID)
		if not spGetUnitDefID(unitID) or not teamID then
			UntrackUnit(unitID)
		else
			data.allyTeamID = GetTeamAllyTeam(teamID)
			if not allyTeamActive[data.allyTeamID] or (data.expireFrame and frame >= data.expireFrame) then
				ClearAmbush(unitID, data)
			end
		end
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end

function gadget:Shutdown()
	for unitID, data in pairs(trackedUnits) do
		ClearAmbush(unitID, data)
	end
end
