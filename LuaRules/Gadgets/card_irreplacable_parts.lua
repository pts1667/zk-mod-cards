function gadget:GetInfo()
	return {
		name = "Card Effect - Irreplacable Parts",
		desc = "Applies the Irreplacable Parts card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 301
local UPDATE_FRAMES = math.max(5, math.floor(Game.gameSpeed / 2))

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetTeamResources = Spring.GetTeamResources
local spGetUnitCurrentBuildPower = Spring.GetUnitCurrentBuildPower
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitTeam = Spring.GetUnitTeam
local spSetUnitHealth = Spring.SetUnitHealth
local spUseTeamResource = Spring.UseTeamResource

local gaiaAllyTeam
local allyTeamActive = {}
local trackedUnits = {}

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

local function TrackUnit(unitID, unitDefID, teamID)
	local allyTeamID = select(6, spGetTeamInfo(teamID, false))
	if allyTeamID == gaiaAllyTeam then
		return
	end

	local health, maxHealth = spGetUnitHealth(unitID)
	if not health or not maxHealth then
		return
	end

	trackedUnits[unitID] = {
		unitDefID = unitDefID,
		teamID = teamID,
		allyTeamID = allyTeamID,
		lastHealth = health,
		lastMaxHealth = maxHealth,
	}
end

local function SweepUnitsForAllyTeam(allyTeamID)
	local teamList = spGetTeamList(allyTeamID)
	for i = 1, #teamList do
		local teamID = teamList[i]
		local unitList = spGetTeamUnits(teamID) or {}
		for j = 1, #unitList do
			local unitID = unitList[j]
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID then
				TrackUnit(unitID, unitDefID, teamID)
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
			SweepUnitsForAllyTeam(allyTeamID)
		end
	end
end

local function ClampRepairCosts()
	for unitID, data in pairs(trackedUnits) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if not unitDefID or not teamID then
			trackedUnits[unitID] = nil
		else
			data.unitDefID = unitDefID
			data.teamID = teamID
			data.allyTeamID = select(6, spGetTeamInfo(teamID, false))
			local health, maxHealth, _, _, buildProgress = spGetUnitHealth(unitID)
			if not health or not maxHealth then
				trackedUnits[unitID] = nil
			else
				local buildPower = spGetUnitCurrentBuildPower(unitID) or 0
				if allyTeamActive[data.allyTeamID] and buildProgress == 1 and buildPower > 0 and health > data.lastHealth + 0.01 then
					local repairedHealth = health - data.lastHealth
					local baseCost = UnitDefs[unitDefID].metalCost or 0
					local requiredMetal = baseCost * repairedHealth / math.max(maxHealth, 1)
					if requiredMetal > 0 then
						local currentMetal = spGetTeamResources(teamID, "metal") or 0
						if currentMetal >= requiredMetal and spUseTeamResource(teamID, "metal", requiredMetal) then
							-- paid in full
						else
							local paidMetal = math.min(currentMetal, requiredMetal)
							if paidMetal > 0 then
								spUseTeamResource(teamID, "metal", paidMetal)
							end
							local paidRatio = (requiredMetal > 0) and (paidMetal / requiredMetal) or 0
							local clampedHealth = data.lastHealth + repairedHealth * paidRatio
							spSetUnitHealth(unitID, clampedHealth)
							health = clampedHealth
						end
					end
				end
				data.lastHealth = health
				data.lastMaxHealth = maxHealth
			end
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackUnit(unitID, unitDefID, teamID)
end

function gadget:UnitDestroyed(unitID)
	trackedUnits[unitID] = nil
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	if newTeamID then
		TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
	end
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID, oldTeamID)
	if newTeamID then
		TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
	end
end

function gadget:GameFrame(frame)
	UpdateCardActivation()
	if frame % UPDATE_FRAMES == 0 then
		ClampRepairCosts()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))
	UpdateCardActivation()
end
