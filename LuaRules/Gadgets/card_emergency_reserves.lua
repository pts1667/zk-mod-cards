function gadget:GetInfo()
	return {
		name = "Card Effect - Emergency Reserves",
		desc = "Applies the Emergency Reserves card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 206
local UPDATE_FRAMES = 30
local THRESHOLD = 0.2
local DURATION_FRAMES = 30 * Game.gameSpeed
local COOLDOWN_FRAMES = 10 * 60 * Game.gameSpeed
local METAL_MULT = 1.5
local ENERGY_MULT = 1.5
local EFFECT_KEY_PREFIX = "zk_cards_emergency_reserves_"

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamResources = Spring.GetTeamResources
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID

local gaiaAllyTeam
local allyTeamActive = {}
local unitAllyTeam = {}
local reserveState = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID, resourceName)
	return EFFECT_KEY_PREFIX .. resourceName .. "_" .. unitID
end

local function ApplyResourceEffect(unitID, resourceName)
	if not GG.Attributes then
		return
	end
	if resourceName == "metal" then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID, resourceName), {
			econ = METAL_MULT,
			energy = 1 / METAL_MULT,
			static = true,
		})
	else
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID, resourceName), {
			econ = 1,
			energy = ENERGY_MULT,
			static = true,
		})
	end
end

local function RemoveResourceEffect(unitID, resourceName)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID, resourceName))
	end
end

local function ForEachAllyTeamUnit(allyTeamID, func)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			func(unitID)
		end
	end
end

local function SetResourceActive(allyTeamID, resourceName, active)
	ForEachAllyTeamUnit(allyTeamID, function(unitID)
		if active then
			ApplyResourceEffect(unitID, resourceName)
		else
			RemoveResourceEffect(unitID, resourceName)
		end
	end)
end

local function EnsureReserveState(allyTeamID)
	reserveState[allyTeamID] = reserveState[allyTeamID] or {
		metal = {activeEnd = 0, cooldownEnd = 0},
		energy = {activeEnd = 0, cooldownEnd = 0},
	}
	return reserveState[allyTeamID]
end

local function GetAllyTeamResources(allyTeamID, resourceName)
	local current = 0
	local storage = 0
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		local teamCurrent, teamStorage = spGetTeamResources(teamID, resourceName)
		current = current + (teamCurrent or 0)
		storage = storage + (teamStorage or 0)
	end
	return current, storage
end

local function TriggerReserve(allyTeamID, resourceName, frame)
	local state = EnsureReserveState(allyTeamID)[resourceName]
	state.activeEnd = frame + DURATION_FRAMES
	state.cooldownEnd = frame + COOLDOWN_FRAMES
	SetResourceActive(allyTeamID, resourceName, true)
end

local function UpdateResourceState(allyTeamID, resourceName, frame)
	local state = EnsureReserveState(allyTeamID)[resourceName]
	if state.activeEnd > 0 and frame >= state.activeEnd then
		state.activeEnd = 0
		SetResourceActive(allyTeamID, resourceName, false)
	end
	if state.activeEnd > frame or state.cooldownEnd > frame then
		return
	end
	local current, storage = GetAllyTeamResources(allyTeamID, resourceName)
	if storage > 0 and current / storage < THRESHOLD then
		TriggerReserve(allyTeamID, resourceName, frame)
	end
end

local function SweepActivation(allyTeamID)
	EnsureReserveState(allyTeamID)
	ForEachAllyTeamUnit(allyTeamID, function(unitID)
		unitAllyTeam[unitID] = allyTeamID
	end)
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam and not allyTeamActive[allyTeamID] and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
			SweepActivation(allyTeamID)
		end
	end
end

local function UpdateAllReserves(frame)
	for allyTeamID in pairs(allyTeamActive) do
		UpdateResourceState(allyTeamID, "metal", frame)
		UpdateResourceState(allyTeamID, "energy", frame)
	end
end

local function TrackUnit(unitID, teamID)
	local allyTeamID = GetTeamAllyTeam(teamID)
	if not allyTeamID or allyTeamID == gaiaAllyTeam then
		return
	end
	unitAllyTeam[unitID] = allyTeamID
	if allyTeamActive[allyTeamID] then
		local state = EnsureReserveState(allyTeamID)
		if state.metal.activeEnd > spGetGameFrame() then
			ApplyResourceEffect(unitID, "metal")
		end
		if state.energy.activeEnd > spGetGameFrame() then
			ApplyResourceEffect(unitID, "energy")
		end
	end
end

local function UntrackUnit(unitID)
	RemoveResourceEffect(unitID, "metal")
	RemoveResourceEffect(unitID, "energy")
	unitAllyTeam[unitID] = nil
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackUnit(unitID, teamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	UntrackUnit(unitID)
	TrackUnit(unitID, newTeamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	UntrackUnit(unitID)
	TrackUnit(unitID, newTeamID)
end

function gadget:UnitDestroyed(unitID)
	UntrackUnit(unitID)
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		UpdateAllReserves(frame)
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
