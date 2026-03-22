function gadget:GetInfo()
	return {
		name = "Card Effect - Commanders",
		desc = "Applies the Commanders card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 203
local EFFECT_KEY_PREFIX = "zk_cards_commanders_"

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam

local allyTeamActive = {}
local trackedCommanders = {}
local gaiaAllyTeam

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function IsCommander(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	local cp = unitDef and unitDef.customParams
	return cp and cp.commtype ~= nil
end

local function ApplyCommanderBuff(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			move = 1.5,
			reload = 1.5,
			range = 1.3,
			build = 2.0,
			healthMult = 2.0,
			static = true,
		})
	end
end

local function RemoveCommanderBuff(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
end

local function TrackCommander(unitID, teamID)
	local unitDefID = spGetUnitDefID(unitID)
	if not IsCommander(unitDefID) then
		return
	end
	local allyTeamID = select(6, spGetTeamInfo(teamID, false))
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedCommanders[unitID] = allyTeamID
	if allyTeamActive[allyTeamID] then
		ApplyCommanderBuff(unitID)
	else
		RemoveCommanderBuff(unitID)
	end
end

local function UntrackCommander(unitID)
	RemoveCommanderBuff(unitID)
	trackedCommanders[unitID] = nil
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			if IsCommander(spGetUnitDefID(unitID)) then
				TrackCommander(unitID, teamID)
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
	if IsCommander(unitDefID) then
		TrackCommander(unitID, teamID)
	end
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	if IsCommander(unitDefID or spGetUnitDefID(unitID)) then
		TrackCommander(unitID, newTeamID)
	end
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	if IsCommander(unitDefID or spGetUnitDefID(unitID)) then
		TrackCommander(unitID, newTeamID)
	end
end

function gadget:UnitDestroyed(unitID)
	UntrackCommander(unitID)
end

function gadget:GameFrame(frame)
	if frame % 30 == 0 then
		UpdateCardActivation()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))
	UpdateCardActivation()
end
