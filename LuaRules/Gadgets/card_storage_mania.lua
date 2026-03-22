function gadget:GetInfo()
	return {
		name = "Card Effect - Storage Mania",
		desc = "Applies the Storage Mania card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 202
local UPDATE_FRAMES = Game.gameSpeed
local BONUS_PER_STORAGE = 0.01
local STORAGE_STEP = 250

local spAddTeamResource = Spring.AddTeamResource
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamResources = Spring.GetTeamResources
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitTeam = Spring.GetUnitTeam

local gaiaAllyTeam
local allyTeamActive = {}
local trackedMexes = {}

local function IsMex(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	local customParams = unitDef and unitDef.customParams
	return customParams and (customParams.ismex or customParams.metal_extractor_mult) and true or false
end

local function GetLivingAllyTeams()
	local allyTeams = {}
	local rawAllyTeams = spGetAllyTeamList()
	for i = 1, #rawAllyTeams do
		local allyTeamID = rawAllyTeams[i]
		if allyTeamID ~= gaiaAllyTeam then
			local teamList = spGetTeamList(allyTeamID)
			for j = 1, #teamList do
				local _, _, isDead = spGetTeamInfo(teamList[j], false)
				if not isDead then
					allyTeams[#allyTeams + 1] = allyTeamID
					break
				end
			end
		end
	end
	return allyTeams
end

local function TrackMex(unitID, unitDefID, teamID)
	if not IsMex(unitDefID) then
		return
	end

	local allyTeamID = select(6, spGetTeamInfo(teamID, false))
	if allyTeamID == gaiaAllyTeam then
		return
	end

	trackedMexes[unitID] = {
		unitDefID = unitDefID,
		teamID = teamID,
		allyTeamID = allyTeamID,
	}
end

local function SweepMexesForAllyTeam(allyTeamID)
	local teamList = spGetTeamList(allyTeamID)
	for i = 1, #teamList do
		local teamID = teamList[i]
		local unitList = spGetTeamUnits(teamID) or {}
		for j = 1, #unitList do
			local unitID = unitList[j]
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID then
				TrackMex(unitID, unitDefID, teamID)
			end
		end
	end
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end

	local allyTeams = GetLivingAllyTeams()
	for i = 1, #allyTeams do
		local allyTeamID = allyTeams[i]
		if not allyTeamActive[allyTeamID] and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
			SweepMexesForAllyTeam(allyTeamID)
		end
	end
end

local function ApplyStorageBonus()
	local bonusByAllyTeam = {}
	local allyTeams = GetLivingAllyTeams()
	for i = 1, #allyTeams do
		local allyTeamID = allyTeams[i]
		if allyTeamActive[allyTeamID] then
			local storedMetal = 0
			local teamList = spGetTeamList(allyTeamID)
			for j = 1, #teamList do
				storedMetal = storedMetal + (spGetTeamResources(teamList[j], "metal") or 0)
			end
			bonusByAllyTeam[allyTeamID] = math.floor(storedMetal / STORAGE_STEP) * BONUS_PER_STORAGE
		end
	end

	for unitID, data in pairs(trackedMexes) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID or not IsMex(unitDefID) then
			trackedMexes[unitID] = nil
		else
			data.unitDefID = unitDefID
			data.teamID = teamID
			data.allyTeamID = select(6, spGetTeamInfo(teamID, false))
			local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
			local bonus = bonusByAllyTeam[data.allyTeamID] or 0
			if bonus > 0 and buildProgress == 1 then
				local mexIncome = spGetUnitRulesParam(unitID, "mexIncome") or tonumber(UnitDefs[unitDefID].customParams.metal_extractor_mult) or 0
				if mexIncome > 0 then
					spAddTeamResource(teamID, "metal", mexIncome * bonus)
				end
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackMex(unitID, unitDefID, teamID)
end

function gadget:UnitDestroyed(unitID)
	trackedMexes[unitID] = nil
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	if newTeamID then
		TrackMex(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
	end
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID, oldTeamID)
	if newTeamID then
		TrackMex(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
	end
end

function gadget:GameFrame(frame)
	UpdateCardActivation()
	if frame % UPDATE_FRAMES == 0 then
		ApplyStorageBonus()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))
	UpdateCardActivation()
end
