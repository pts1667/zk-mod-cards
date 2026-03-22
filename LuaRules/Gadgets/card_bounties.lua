function gadget:GetInfo()
	return {
		name = "Card Effect - Bounties",
		desc = "Applies the Bounties card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 307
local UPDATE_FRAMES = 30
local PROVIDER_UPDATE_FRAMES = 15
local REVEAL_RADIUS = 900
local HIGH_VALUE_COST = 700
local BOUNTY_INTERVAL_FRAMES = 5 * 60 * Game.gameSpeed
local BONUS_DURATION_FRAMES = 5 * 60 * Game.gameSpeed
local PENALTY_DURATION_FRAMES = 3 * 60 * Game.gameSpeed

local spCreateUnit = Spring.CreateUnit
local spDestroyUnit = Spring.DestroyUnit
local spEditUnitCmdDesc = Spring.EditUnitCmdDesc
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spSetGameRulesParam = Spring.SetGameRulesParam
local spSetUnitBlocking = Spring.SetUnitBlocking
local spSetUnitCollisionVolumeData = Spring.SetUnitCollisionVolumeData
local spSetUnitLosMask = Spring.SetUnitLosMask
local spSetUnitLosState = Spring.SetUnitLosState
local spSetUnitNeutral = Spring.SetUnitNeutral
local spSetUnitNoDraw = Spring.SetUnitNoDraw
local spSetUnitNoMinimap = Spring.SetUnitNoMinimap
local spSetUnitNoSelect = Spring.SetUnitNoSelect
local spSetUnitPosition = Spring.SetUnitPosition
local spSetUnitSensorRadius = Spring.SetUnitSensorRadius
local spSendMessageToTeam = Spring.SendMessageToTeam
local spValidUnitID = Spring.ValidUnitID

local gaiaAllyTeam
local fakeLosDefID = UnitDefNames.fakeunit_los and UnitDefNames.fakeunit_los.id
local allyTeamCardActive = {}
local bountyStateByAllyTeam = {}
local modifiersByAllyTeam = {}
local allyTeamCardMultiplier = {}
local baseIncomeMult = {}
local originalUnitHandicap = {}
local modifierSequence = 0

local function GetTeamAllyTeam(teamID)
	return select(6, spGetTeamInfo(teamID, false))
end

local function GetLivingAllyTeams()
	local allyTeams = {}
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam then
			for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
				local _, _, isDead = spGetTeamInfo(teamID, false)
				if not isDead then
					allyTeams[#allyTeams + 1] = allyTeamID
					break
				end
			end
		end
	end
	return allyTeams
end

local function GetLivingTeamForAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		local _, _, isDead = spGetTeamInfo(teamID, false)
		if not isDead then
			return teamID
		end
	end
	return nil
end

local function BroadcastMessage(message)
	for _, allyTeamID in ipairs(GetLivingAllyTeams()) do
		for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
			spSendMessageToTeam(teamID, message)
		end
	end
end

local function EnsureIncomeTable()
	GG.unit_handicap = GG.unit_handicap or {}
	GG.allyTeamIncomeMult = GG.allyTeamIncomeMult or {}
	spSetGameRulesParam("econ_mult_enabled", 1)
end

local function SetProviderState(providerID)
	spSetUnitSensorRadius(providerID, "los", REVEAL_RADIUS)
	spSetUnitSensorRadius(providerID, "airLos", REVEAL_RADIUS)
	spSetUnitSensorRadius(providerID, "sonar", REVEAL_RADIUS)
	spSetUnitSensorRadius(providerID, "radarJammer", 0)
	spSetUnitSensorRadius(providerID, "sonarJammer", 0)
	spSetUnitNeutral(providerID, true)
	spSetUnitBlocking(providerID, false, false, false, false, false, false, false)
	spSetUnitNoSelect(providerID, true)
	spSetUnitNoDraw(providerID, true)
	spSetUnitNoMinimap(providerID, true)
	spSetUnitCollisionVolumeData(providerID, 0, 0, 0, 0, 0, 0, 0, 1, 0)
end

local function SetTargetReveal(state, enabled)
	if not state.targetID or not spValidUnitID(state.targetID) then
		return
	end
	for i = 1, #(state.enemyAllyTeams or {}) do
		local allyTeamID = state.enemyAllyTeams[i]
		if enabled then
			spSetUnitLosMask(state.targetID, allyTeamID, 15)
			spSetUnitLosState(state.targetID, allyTeamID, 15)
		else
			spSetUnitLosState(state.targetID, allyTeamID, 0)
			spSetUnitLosMask(state.targetID, allyTeamID, 0)
		end
	end
end

local function DestroyProviders(state)
	if not state.providers then
		return
	end
	for _, providerID in pairs(state.providers) do
		if spValidUnitID(providerID) then
			spDestroyUnit(providerID, false, true)
		end
	end
	state.providers = {}
end

local function ClearBountyState(state, nextEligibleFrame)
	if not state then
		return
	end
	SetTargetReveal(state, false)
	DestroyProviders(state)
	state.targetID = nil
	state.targetTeamID = nil
	state.targetName = nil
	state.enemyAllyTeams = {}
	state.nextEligibleFrame = nextEligibleFrame or (spGetGameFrame() + BOUNTY_INTERVAL_FRAMES)
end

local function SetUnitHandicap(unitID, allyTeamID)
	if not spValidUnitID(unitID) then
		return
	end
	local multiplier = allyTeamCardMultiplier[allyTeamID] or 1
	if multiplier == 1 then
		local base = originalUnitHandicap[unitID]
		if base ~= nil then
			GG.unit_handicap[unitID] = (base ~= 1) and base or nil
			originalUnitHandicap[unitID] = nil
			if GG.UpdateUnitAttributes then
				GG.UpdateUnitAttributes(unitID)
			end
		end
		return
	end

	if originalUnitHandicap[unitID] == nil then
		originalUnitHandicap[unitID] = GG.unit_handicap[unitID] or 1
	end
	GG.unit_handicap[unitID] = originalUnitHandicap[unitID] * multiplier
	if GG.UpdateUnitAttributes then
		GG.UpdateUnitAttributes(unitID)
	end
end

local function RefreshAllyTeamMultiplier(allyTeamID)
	EnsureIncomeTable()

	local baseMult = baseIncomeMult[allyTeamID]
	if baseMult == nil then
		baseMult = GG.allyTeamIncomeMult[allyTeamID] or 1
		baseIncomeMult[allyTeamID] = baseMult
	end

	local totalMult = 1
	for _, modifier in pairs(modifiersByAllyTeam[allyTeamID] or {}) do
		totalMult = totalMult * modifier.mult
	end
	allyTeamCardMultiplier[allyTeamID] = totalMult
	GG.allyTeamIncomeMult[allyTeamID] = baseMult * totalMult
	spSetGameRulesParam("econ_mult_" .. allyTeamID, GG.allyTeamIncomeMult[allyTeamID])

	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			SetUnitHandicap(unitID, allyTeamID)
		end
	end
end

local function AddModifier(allyTeamID, mult, durationFrames)
	modifierSequence = modifierSequence + 1
	modifiersByAllyTeam[allyTeamID] = modifiersByAllyTeam[allyTeamID] or {}
	modifiersByAllyTeam[allyTeamID][modifierSequence] = {
		mult = mult,
		endFrame = spGetGameFrame() + durationFrames,
	}
	RefreshAllyTeamMultiplier(allyTeamID)
end

local function UpdateModifiers(frame)
	for allyTeamID, modifierTable in pairs(modifiersByAllyTeam) do
		local dirty = false
		for id, modifier in pairs(modifierTable) do
			if frame >= modifier.endFrame then
				modifierTable[id] = nil
				dirty = true
			end
		end
		if dirty then
			RefreshAllyTeamMultiplier(allyTeamID)
		end
	end
end

local function GetTargetOwnerName(teamID)
	local _, leaderPlayerID = spGetTeamInfo(teamID, false)
	if not leaderPlayerID or leaderPlayerID < 0 then
		return "Unknown"
	end
	local playerName = spGetPlayerInfo(leaderPlayerID, false)
	return playerName or "Unknown"
end

local function PickTargetForAllyTeam(allyTeamID)
	local candidates = {}
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			local unitDefID = spGetUnitDefID(unitID)
			if unitDefID then
				local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
				if buildProgress == 1 then
					local cost = Spring.Utilities.GetUnitCost(unitID, unitDefID)
					if cost >= HIGH_VALUE_COST then
						candidates[#candidates + 1] = {
							unitID = unitID,
							teamID = teamID,
							name = UnitDefs[unitDefID].humanName or UnitDefs[unitDefID].name or "unit",
						}
					end
				end
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[math.random(#candidates)]
end

local function CreateProvidersForState(state)
	local x, _, z = spGetUnitPosition(state.targetID)
	if not x then
		return false
	end
	state.providers = {}
	state.enemyAllyTeams = {}

	for _, otherAllyTeamID in ipairs(GetLivingAllyTeams()) do
		if otherAllyTeamID ~= state.allyTeamID then
			local teamID = GetLivingTeamForAllyTeam(otherAllyTeamID)
			if teamID and fakeLosDefID then
				local providerID = spCreateUnit("fakeunit_los", x, 10000, z, 0, teamID)
				if providerID then
					SetProviderState(providerID)
					state.providers[otherAllyTeamID] = providerID
					state.enemyAllyTeams[#state.enemyAllyTeams + 1] = otherAllyTeamID
				end
			end
		end
	end

	SetTargetReveal(state, true)
	return true
end

local function OpenBountyForAllyTeam(allyTeamID, state)
	local target = PickTargetForAllyTeam(allyTeamID)
	if not target then
		state.nextEligibleFrame = spGetGameFrame() + BOUNTY_INTERVAL_FRAMES
		return
	end

	state.targetID = target.unitID
	state.targetTeamID = target.teamID
	state.targetName = target.name
	if not CreateProvidersForState(state) then
		ClearBountyState(state, spGetGameFrame() + BOUNTY_INTERVAL_FRAMES)
		return
	end

	BroadcastMessage("Bounty: if " .. GetTargetOwnerName(target.teamID) .. "'s " .. target.name .. " is destroyed, everyone gets an economy bonus.")
end

local function UpdateBountyActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	local frame = spGetGameFrame()
	for _, allyTeamID in ipairs(GetLivingAllyTeams()) do
		if GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamCardActive[allyTeamID] = true
			if not bountyStateByAllyTeam[allyTeamID] then
				bountyStateByAllyTeam[allyTeamID] = {
					allyTeamID = allyTeamID,
					nextEligibleFrame = frame + BOUNTY_INTERVAL_FRAMES,
					targetID = nil,
					targetTeamID = nil,
					targetName = nil,
					providers = {},
					enemyAllyTeams = {},
				}
			end
		end
	end
end

local function UpdateBounties(frame)
	for allyTeamID, state in pairs(bountyStateByAllyTeam) do
		if allyTeamCardActive[allyTeamID] then
			if state.targetID then
				local targetTeamID = spGetUnitTeam(state.targetID)
				if not targetTeamID or GetTeamAllyTeam(targetTeamID) ~= allyTeamID then
					ClearBountyState(state, frame + BOUNTY_INTERVAL_FRAMES)
				elseif frame % PROVIDER_UPDATE_FRAMES == 0 then
					local x, y, z = spGetUnitPosition(state.targetID)
					if x then
						for _, providerID in pairs(state.providers) do
							if spValidUnitID(providerID) then
								spSetUnitPosition(providerID, x, y + 10000, z)
							end
						end
					end
				end
			elseif frame >= state.nextEligibleFrame then
				OpenBountyForAllyTeam(allyTeamID, state)
			end
		end
	end
end

function gadget:UnitDestroyed(unitID)
	for allyTeamID, state in pairs(bountyStateByAllyTeam) do
		if state.targetID == unitID then
			AddModifier(allyTeamID, 0.5, PENALTY_DURATION_FRAMES)
			for _, otherAllyTeamID in ipairs(GetLivingAllyTeams()) do
				if otherAllyTeamID ~= allyTeamID then
					AddModifier(otherAllyTeamID, 1.3, BONUS_DURATION_FRAMES)
				end
			end
			ClearBountyState(state, spGetGameFrame() + BOUNTY_INTERVAL_FRAMES)
			return
		end
	end
	if originalUnitHandicap[unitID] ~= nil then
		originalUnitHandicap[unitID] = nil
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamCardMultiplier[allyTeamID] and allyTeamCardMultiplier[allyTeamID] ~= 1 then
		SetUnitHandicap(unitID, allyTeamID)
	end
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	local allyTeamID = GetTeamAllyTeam(newTeamID)
	SetUnitHandicap(unitID, allyTeamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	local oldAllyTeamID = GetTeamAllyTeam(oldTeamID)
	local newAllyTeamID = GetTeamAllyTeam(newTeamID)
	if oldAllyTeamID ~= newAllyTeamID and originalUnitHandicap[unitID] ~= nil then
		GG.unit_handicap[unitID] = (originalUnitHandicap[unitID] ~= 1) and originalUnitHandicap[unitID] or nil
		originalUnitHandicap[unitID] = nil
		if GG.UpdateUnitAttributes then
			GG.UpdateUnitAttributes(unitID)
		end
	end
	SetUnitHandicap(unitID, newAllyTeamID)
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateBountyActivation()
		UpdateModifiers(frame)
		UpdateBounties(frame)
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateBountyActivation()
end

function gadget:Shutdown()
	for _, state in pairs(bountyStateByAllyTeam) do
		ClearBountyState(state, state.nextEligibleFrame)
	end
	for unitID, base in pairs(originalUnitHandicap) do
		GG.unit_handicap[unitID] = (base ~= 1) and base or nil
	end
end
