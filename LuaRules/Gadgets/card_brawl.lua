function gadget:GetInfo()
	return {
		name = "Card Effect - Brawl",
		desc = "Applies the Brawl card effect",
		author = "Codex",
		layer = -1,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 313
local UPDATE_FRAMES = 15
local EFFECT_KEY_PREFIX = "zk_cards_brawl_"
local MELEE_RANGE = 300
local MELEE_HEALTH_MULT = 6.0
local OTHER_HEALTH_MULT = 0.5

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetAllUnits = Spring.GetAllUnits
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}
local brawlHealthMultByUnitDefID = {}

for unitDefID = 1, #UnitDefs do
	local unitDef = UnitDefs[unitDefID]
	local range = unitDef and unitDef.maxWeaponRange or 0
	if range > 0 and range < MELEE_RANGE then
		brawlHealthMultByUnitDefID[unitDefID] = MELEE_HEALTH_MULT
	else
		brawlHealthMultByUnitDefID[unitDefID] = OTHER_HEALTH_MULT
	end
end

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function ClearEffect(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
end

local function TrackUnit(unitID, teamID)
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam then
		return
	end
	trackedUnits[unitID] = allyTeamID
end

local function UntrackUnit(unitID)
	ClearEffect(unitID)
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

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES ~= 0 then
		return
	end

	UpdateCardActivation()
	for unitID, allyTeamID in pairs(trackedUnits) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID then
			UntrackUnit(unitID)
		else
			allyTeamID = GetTeamAllyTeam(teamID)
			trackedUnits[unitID] = allyTeamID
			if allyTeamActive[allyTeamID] then
				if GG.Attributes then
					GG.Attributes.AddEffect(unitID, GetEffectKey(unitID), {
						healthMult = brawlHealthMultByUnitDefID[unitDefID] or OTHER_HEALTH_MULT,
						static = true,
					})
				end
			else
				ClearEffect(unitID)
			end
		end
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	for _, unitID in ipairs(spGetAllUnits()) do
		local teamID = spGetUnitTeam(unitID)
		if teamID then
			TrackUnit(unitID, teamID)
		end
	end
	UpdateCardActivation()
end

function gadget:Shutdown()
	for unitID in pairs(trackedUnits) do
		ClearEffect(unitID)
	end
end
