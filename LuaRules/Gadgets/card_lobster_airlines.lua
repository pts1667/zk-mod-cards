function gadget:GetInfo()
	return {
		name = "Card Effect - Lobster Airlines",
		desc = "Applies the Lobster Airlines card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 113
local UPDATE_FRAMES = 30
local ROOT_EFFECT_KEY_PREFIX = "zk_cards_lobster_airlines_root_"
local TRANSPORT_EFFECT_KEY_PREFIX = "zk_cards_lobster_airlines_transport_"
local ROOT_MOVE_MULT = 0
local TRANSPORT_HEALTH_MULT = 16

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
local trackedTransports = {}
local rootedDefs = {}
local transportDefs = {}

for unitDefID = 1, #UnitDefs do
	local unitDef = UnitDefs[unitDefID]
	local cp = unitDef.customParams or {}
	local fromFactory = cp.from_factory
	local isTransport = unitDef.isTransport and unitDef.transportCapacity and unitDef.transportCapacity > 0
	if isTransport and (unitDef.name == "gunshiptrans" or unitDef.name == "gunshipheavytrans") then
		transportDefs[unitDefID] = true
	end
	if not unitDef.isImmobile and not unitDef.canFly and not isTransport and fromFactory ~= "factoryhover" and fromFactory ~= "factoryship" then
		rootedDefs[unitDefID] = true
	end
end

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetRootEffectKey(unitID)
	return ROOT_EFFECT_KEY_PREFIX .. unitID
end

local function GetTransportEffectKey(unitID)
	return TRANSPORT_EFFECT_KEY_PREFIX .. unitID
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
			if unitDefID then
				if rootedDefs[unitDefID] then
					trackedUnits[unitID] = true
				elseif transportDefs[unitDefID] then
					trackedTransports[unitID] = true
				end
			end
		end
	end
end

local function ApplyRoot(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetRootEffectKey(unitID), {
			move = ROOT_MOVE_MULT,
			static = true,
		})
	end
end

local function ClearRoot(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetRootEffectKey(unitID))
	end
end

local function ApplyTransportBuff(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetTransportEffectKey(unitID), {
			healthMult = TRANSPORT_HEALTH_MULT,
			static = true,
		})
	end
end

local function ClearTransportBuff(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetTransportEffectKey(unitID))
	end
end

local function TrackUnit(unitID, unitDefID)
	if rootedDefs[unitDefID] then
		trackedUnits[unitID] = true
	elseif transportDefs[unitDefID] then
		trackedTransports[unitID] = true
	end
end

local function UntrackUnit(unitID)
	trackedUnits[unitID] = nil
	trackedTransports[unitID] = nil
	ClearRoot(unitID)
	ClearTransportBuff(unitID)
end

local function UpdateUnits()
	for unitID in pairs(trackedUnits) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or not rootedDefs[unitDefID] then
			trackedUnits[unitID] = nil
			ClearRoot(unitID)
		else
			local allyTeamID = GetTeamAllyTeam(teamID)
			if allyTeamActive[allyTeamID] then
				ApplyRoot(unitID)
			else
				ClearRoot(unitID)
			end
		end
	end

	for unitID in pairs(trackedTransports) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or not transportDefs[unitDefID] then
			trackedTransports[unitID] = nil
			ClearTransportBuff(unitID)
		else
			local allyTeamID = GetTeamAllyTeam(teamID)
			if allyTeamActive[allyTeamID] then
				ApplyTransportBuff(unitID)
			else
				ClearTransportBuff(unitID)
			end
		end
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
	UntrackUnit(unitID)
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		for allyTeamID in pairs(allyTeamActive) do
			SweepAllyTeam(allyTeamID)
		end
		UpdateUnits()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end

function gadget:Shutdown()
	for unitID in pairs(trackedUnits) do
		ClearRoot(unitID)
	end
	for unitID in pairs(trackedTransports) do
		ClearTransportBuff(unitID)
	end
end
