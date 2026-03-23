function gadget:GetInfo()
	return {
		name = "Card Effect - Heavy Tanks",
		desc = "Applies the Heavy Tanks card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 114
local UPDATE_FRAMES = 30
local EFFECT_KEY_PREFIX = "zk_cards_heavy_tanks_"
local SCALE_MULT = 2

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}
local eligibleDefs = {}

do
	local factoryDef = UnitDefNames.factorytank
	if factoryDef then
		for _, buildDefID in ipairs(UnitDefs[factoryDef.id].buildOptions or {}) do
			if not UnitDefs[buildDefID].isImmobile then
				eligibleDefs[buildDefID] = true
			end
		end
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

local function ApplyEffect(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
			move = 0.2,
			healthMult = 3,
			projectiles = 3,
			static = true,
		})
	end
	if GG.SetColvolScales then
		GG.SetColvolScales(unitID, {SCALE_MULT, SCALE_MULT, SCALE_MULT})
	end
	if GG.UnitModelRescale then
		GG.UnitModelRescale(unitID, SCALE_MULT)
	end
end

local function ClearEffect(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
end

local function TrackUnit(unitID, unitDefID)
	if eligibleDefs[unitDefID] then
		trackedUnits[unitID] = true
	end
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
	ClearEffect(unitID)
	trackedUnits[unitID] = nil
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		for allyTeamID in pairs(allyTeamActive) do
			SweepAllyTeam(allyTeamID)
		end
		for unitID in pairs(trackedUnits) do
			local unitDefID = spGetUnitDefID(unitID)
			local teamID = spGetUnitTeam(unitID)
			if not unitDefID or not teamID or not eligibleDefs[unitDefID] then
				trackedUnits[unitID] = nil
				ClearEffect(unitID)
			else
				local allyTeamID = GetTeamAllyTeam(teamID)
				if allyTeamActive[allyTeamID] then
					ApplyEffect(unitID)
				else
					ClearEffect(unitID)
				end
			end
		end
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end

function gadget:Shutdown()
	for unitID in pairs(trackedUnits) do
		ClearEffect(unitID)
	end
end
