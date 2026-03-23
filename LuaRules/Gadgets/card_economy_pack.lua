function gadget:GetInfo()
	return {
		name = "Card Effect - Economy Pack",
		desc = "Applies the Economy Pack card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 214
local UPDATE_FRAMES = 30
local EFFECT_KEY_PREFIX = "zk_cards_economy_pack_mex_"
local CARD_RULES_PREFIX = "zk_cards_economy_pack_"

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitTeam = Spring.GetUnitTeam
local spSetUnitRulesParam = Spring.SetUnitRulesParam

local gaiaAllyTeam
local allyTeamActive = {}
local trackedMexes = {}
local trackedCommanders = {}
local mexDefs = {}
local commanderDefs = {}
local ALLY_ACCESS = {allied = true}

for unitDefID = 1, #UnitDefs do
	local unitDef = UnitDefs[unitDefID]
	local cp = unitDef.customParams or {}
	if cp.ismex or cp.metal_extractor_mult then
		mexDefs[unitDefID] = true
	end
	if cp.commtype or cp.dynamic_comm then
		commanderDefs[unitDefID] = true
	end
end

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function GetMexEffectKey(unitID)
	return EFFECT_KEY_PREFIX .. unitID
end

local function GetDisplayLevel(unitID)
	local level = (spGetUnitRulesParam(unitID, "comm_level") or 0) + 1
	if level < 1 then
		return 1
	end
	if level > 20 then
		return 20
	end
	return level
end

local function GetTargetIncome(unitID)
	local level = GetDisplayLevel(unitID)
	return 4 + (level - 1) * (16 / 19), 6 + (level - 1) * (14 / 19), level
end

local function ApplyMexSuppression(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetMexEffectKey(unitID), {
			econ = 0,
			static = true,
		})
	end
end

local function ClearMexSuppression(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetMexEffectKey(unitID))
	end
end

local function ClearCommanderDelta(unitID, data)
	if not (data and GG.Overdrive) then
		return
	end
	if data.appliedMetalDelta or data.appliedEnergyDelta then
		GG.Overdrive.AddUnitResourceGeneration(unitID, -(data.appliedMetalDelta or 0), -(data.appliedEnergyDelta or 0), true, false)
	end
	data.appliedMetalDelta = 0
	data.appliedEnergyDelta = 0
	spSetUnitRulesParam(unitID, CARD_RULES_PREFIX .. "level", 0, ALLY_ACCESS)
	spSetUnitRulesParam(unitID, CARD_RULES_PREFIX .. "metal", 0, ALLY_ACCESS)
	spSetUnitRulesParam(unitID, CARD_RULES_PREFIX .. "energy", 0, ALLY_ACCESS)
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
				if mexDefs[unitDefID] then
					trackedMexes[unitID] = true
				end
				if commanderDefs[unitDefID] then
					trackedCommanders[unitID] = trackedCommanders[unitID] or {
						appliedMetalDelta = 0,
						appliedEnergyDelta = 0,
					}
				end
			end
		end
	end
end

local function UpdateMexes()
	for unitID in pairs(trackedMexes) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or not mexDefs[unitDefID] then
			trackedMexes[unitID] = nil
			ClearMexSuppression(unitID)
		else
			local allyTeamID = GetTeamAllyTeam(teamID)
			if allyTeamActive[allyTeamID] then
				ApplyMexSuppression(unitID)
			else
				ClearMexSuppression(unitID)
			end
		end
	end
end

local function UpdateCommanders()
	for unitID, data in pairs(trackedCommanders) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or not commanderDefs[unitDefID] then
			ClearCommanderDelta(unitID, data)
			trackedCommanders[unitID] = nil
		else
			local allyTeamID = GetTeamAllyTeam(teamID)
			if not allyTeamActive[allyTeamID] then
				ClearCommanderDelta(unitID, data)
			else
				local targetMetal, targetEnergy, level = GetTargetIncome(unitID)
				local baseMetal = spGetUnitRulesParam(unitID, "comm_income_metal") or 0
				local baseEnergy = spGetUnitRulesParam(unitID, "comm_income_energy") or 0
				local desiredMetalDelta = targetMetal - baseMetal
				local desiredEnergyDelta = targetEnergy - baseEnergy
				local deltaMetal = desiredMetalDelta - (data.appliedMetalDelta or 0)
				local deltaEnergy = desiredEnergyDelta - (data.appliedEnergyDelta or 0)
				if GG.Overdrive and (deltaMetal ~= 0 or deltaEnergy ~= 0) then
					GG.Overdrive.AddUnitResourceGeneration(unitID, deltaMetal, deltaEnergy, true, false)
				end
				data.appliedMetalDelta = desiredMetalDelta
				data.appliedEnergyDelta = desiredEnergyDelta
				spSetUnitRulesParam(unitID, CARD_RULES_PREFIX .. "level", level, ALLY_ACCESS)
				spSetUnitRulesParam(unitID, CARD_RULES_PREFIX .. "metal", targetMetal, ALLY_ACCESS)
				spSetUnitRulesParam(unitID, CARD_RULES_PREFIX .. "energy", targetEnergy, ALLY_ACCESS)
			end
		end
	end
end

local function TrackUnit(unitID, unitDefID)
	if mexDefs[unitDefID] then
		trackedMexes[unitID] = true
	elseif commanderDefs[unitDefID] then
		trackedCommanders[unitID] = trackedCommanders[unitID] or {
			appliedMetalDelta = 0,
			appliedEnergyDelta = 0,
		}
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
	ClearMexSuppression(unitID)
	if trackedCommanders[unitID] then
		ClearCommanderDelta(unitID, trackedCommanders[unitID])
		trackedCommanders[unitID] = nil
	end
	trackedMexes[unitID] = nil
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		for allyTeamID in pairs(allyTeamActive) do
			SweepAllyTeam(allyTeamID)
		end
		UpdateMexes()
		UpdateCommanders()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end

function gadget:Shutdown()
	for unitID in pairs(trackedMexes) do
		ClearMexSuppression(unitID)
	end
	for unitID, data in pairs(trackedCommanders) do
		ClearCommanderDelta(unitID, data)
	end
end
