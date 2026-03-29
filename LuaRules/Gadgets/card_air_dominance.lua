function gadget:GetInfo()
	return {
		name = "Card Effect - Air Dominance",
		desc = "Applies the Air Dominance card effect",
		author = "Codex",
		layer = -1,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 213
local UPDATE_FRAMES = 15
local EFFECT_KEY_PREFIX = "zk_cards_air_dominance_"
local MOVE_MULT = 0.5
local HEALTH_MULT = 3.0
local INLOS_ACCESS = {inlos = true}
local CMD_REARM = Spring.Utilities.CMD.REARM

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitTeam = Spring.GetUnitTeam
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spSetUnitRulesParam = Spring.SetUnitRulesParam

local gaiaAllyTeam
local allyTeamActive = {}
local trackedAirUnits = {}
local rearmFramesByDefID = {}

for unitDefID = 1, #UnitDefs do
	local unitDef = UnitDefs[unitDefID]
	local movetype = Spring.Utilities.getMovetype(unitDef)
	if movetype == 0 or movetype == 1 then
		local cp = unitDef.customParams or {}
		if cp.reammoseconds then
			rearmFramesByDefID[unitDefID] = tonumber(cp.reammoseconds) * Game.gameSpeed
		end
	end
end

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function IsAirUnit(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	if not unitDef then
		return false
	end
	local movetype = Spring.Utilities.getMovetype(unitDef)
	return movetype == 0 or movetype == 1
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function CompleteInAirRearm(unitID)
	local scriptEnv = Spring.UnitScript.GetScriptEnv(unitID)
	local reammoComplete = scriptEnv and scriptEnv.ReammoComplete
	if reammoComplete then
		Spring.UnitScript.CallAsUnit(unitID, reammoComplete)
	end
	spSetUnitRulesParam(unitID, "noammo", 0, INLOS_ACCESS)
	spSetUnitRulesParam(unitID, "reammoProgress", nil, INLOS_ACCESS)
	spSetUnitRulesParam(unitID, "airpadReservation", 0, INLOS_ACCESS)

	local cmdID, _, cmdTag = spGetUnitCurrentCommand(unitID)
	if cmdID == CMD_REARM and cmdTag then
		spGiveOrderToUnit(unitID, CMD.REMOVE, cmdTag, 0)
	end
end

local function EnsureTrackedUnit(unitID, unitDefID, teamID)
	if not IsAirUnit(unitDefID) then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedAirUnits[unitID] = trackedAirUnits[unitID] or {}
	trackedAirUnits[unitID].allyTeamID = allyTeamID
end

local function UntrackUnit(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
	trackedAirUnits[unitID] = nil
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

local function UpdateAirUnits()
	for unitID, data in pairs(trackedAirUnits) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or not IsAirUnit(unitDefID) then
			UntrackUnit(unitID)
		else
			local allyTeamID = GetTeamAllyTeam(teamID)
			data.allyTeamID = allyTeamID
			if allyTeamActive[allyTeamID] then
				if GG.Attributes then
					GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
						move = MOVE_MULT,
						healthMult = HEALTH_MULT,
						static = true,
					})
				end
				local rearmFrames = rearmFramesByDefID[unitDefID]
				if rearmFrames then
					local noAmmo = spGetUnitRulesParam(unitID, "noammo")
					if noAmmo == 1 then
						data.rearmProgress = data.rearmProgress or 0
						spSetUnitRulesParam(unitID, "noammo", 2, INLOS_ACCESS)
						spSetUnitRulesParam(unitID, "airpadReservation", 0, INLOS_ACCESS)
					end
					if spGetUnitRulesParam(unitID, "noammo") == 2 then
						data.rearmProgress = (data.rearmProgress or 0) + UPDATE_FRAMES
						local progress = math.min(1, data.rearmProgress / rearmFrames)
						spSetUnitRulesParam(unitID, "reammoProgress", progress, INLOS_ACCESS)
						if progress >= 1 then
							data.rearmProgress = nil
							CompleteInAirRearm(unitID)
						end
					else
						data.rearmProgress = nil
					end
				end
			else
				if GG.Attributes then
					GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
				end
				data.rearmProgress = nil
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
	UntrackUnit(unitID)
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		UpdateAirUnits()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
	UpdateAirUnits()
end

function gadget:Shutdown()
	for unitID in pairs(trackedAirUnits) do
		UntrackUnit(unitID)
	end
end
