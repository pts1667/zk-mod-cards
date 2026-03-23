function gadget:GetInfo()
	return {
		name = "Card Effect - Mega Lobster",
		desc = "Applies the Mega Lobster card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 211
local EFFECT_KEY = "zk_cards_mega_lobster"
local SCALE_MULT = 2.0
local HEALTH_MULT = 6.0
local RANGE_MULT = 2.0
local INLOS_ACCESS = {inlos = true}

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spSetUnitRulesParam = Spring.SetUnitRulesParam

local gaiaAllyTeam
local allyTeamActive = {}
local trackedLobsters = {}
local lobsterDefID = UnitDefNames.amphlaunch and UnitDefNames.amphlaunch.id

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function ClearLobsterVisuals(unitID)
	if GG.SetColvolScales then
		GG.SetColvolScales(unitID, {1, 1, 1})
	end
	if GG.UnitModelRescale then
		GG.UnitModelRescale(unitID, 1)
	end
end

local function ApplyLobsterBuff(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, EFFECT_KEY, {
			healthMult = HEALTH_MULT,
			range = RANGE_MULT,
			static = true,
		})
	end
	if GG.SetColvolScales then
		GG.SetColvolScales(unitID, {SCALE_MULT, SCALE_MULT, SCALE_MULT})
	end
	if GG.UnitModelRescale then
		GG.UnitModelRescale(unitID, SCALE_MULT)
	end
	spSetUnitRulesParam(unitID, "zk_cards_mega_lobster", 1, INLOS_ACCESS)
end

local function RemoveLobsterBuff(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, EFFECT_KEY)
	end
	if spGetUnitDefID(unitID) then
		ClearLobsterVisuals(unitID)
		spSetUnitRulesParam(unitID, "zk_cards_mega_lobster", 0, INLOS_ACCESS)
	end
end

local function TrackLobster(unitID, unitDefID, teamID)
	if unitDefID ~= lobsterDefID then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedLobsters[unitID] = allyTeamID
	if allyTeamActive[allyTeamID] then
		ApplyLobsterBuff(unitID)
	else
		RemoveLobsterBuff(unitID)
	end
end

local function UntrackLobster(unitID)
	RemoveLobsterBuff(unitID)
	trackedLobsters[unitID] = nil
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			if spGetUnitDefID(unitID) == lobsterDefID then
				TrackLobster(unitID, lobsterDefID, teamID)
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

function gadget:UnitCreated(unitID, unitDefID, teamID)
	if unitDefID == lobsterDefID then
		TrackLobster(unitID, unitDefID, teamID)
	end
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	if (unitDefID or spGetUnitDefID(unitID)) == lobsterDefID then
		TrackLobster(unitID, unitDefID or lobsterDefID, newTeamID)
	end
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	if (unitDefID or spGetUnitDefID(unitID)) == lobsterDefID then
		TrackLobster(unitID, unitDefID or lobsterDefID, newTeamID)
	end
end

function gadget:UnitDestroyed(unitID)
	UntrackLobster(unitID)
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

function gadget:Shutdown()
	for unitID in pairs(trackedLobsters) do
		UntrackLobster(unitID)
	end
end
