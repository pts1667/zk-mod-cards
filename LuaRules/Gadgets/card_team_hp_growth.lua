function gadget:GetInfo()
	return {
		name = "Card Effect - Team HP Growth",
		desc = "Applies the Reinforced Frames card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 205
local BONUS_PER_TICK = 0.05
local TICK_FRAMES = 60 * Game.gameSpeed

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitHealth = Spring.GetUnitHealth

local gaiaAllyTeam
local allyTeamState = {}
local unitBonusTicks = {}

local function GetEffectKey(unitID)
	return "zk_cards_team_hp_growth_" .. unitID
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

local function UpdateUnitEffect(unitID)
	if not GG.Attributes then
		return
	end

	local tickCount = unitBonusTicks[unitID] or 0
	local effectKey = GetEffectKey(unitID)
	if tickCount <= 0 then
		GG.Attributes.RemoveEffect(unitID, effectKey)
		return
	end

	GG.Attributes.AddEffect(unitID, effectKey, {
		healthMult = 1 + BONUS_PER_TICK * tickCount,
		static = true,
	})
end

local function ApplyBonusTickToAllyTeam(allyTeamID)
	local teamList = spGetTeamList(allyTeamID)
	for i = 1, #teamList do
		local unitList = spGetTeamUnits(teamList[i]) or {}
		for j = 1, #unitList do
			local unitID = unitList[j]
			local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
			if buildProgress == 1 then
				unitBonusTicks[unitID] = (unitBonusTicks[unitID] or 0) + 1
				UpdateUnitEffect(unitID)
			end
		end
	end
end

local function EnsureAllyTeamState(allyTeamID)
	local state = allyTeamState[allyTeamID]
	if state then
		return state
	end

	state = {
		active = false,
		nextTickFrame = nil,
	}
	allyTeamState[allyTeamID] = state
	return state
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard and GG.ZKCards.GetAppliedFrame) then
		return
	end

	local allyTeams = GetLivingAllyTeams()
	for i = 1, #allyTeams do
		local allyTeamID = allyTeams[i]
		local state = EnsureAllyTeamState(allyTeamID)
		if not state.active and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			local appliedFrame = GG.ZKCards.GetAppliedFrame(allyTeamID, CARD_ID)
			if appliedFrame then
				state.active = true
				state.nextTickFrame = appliedFrame + TICK_FRAMES
			end
		end
	end
end

function gadget:GameFrame(frame)
	UpdateCardActivation()

	for allyTeamID, state in pairs(allyTeamState) do
		while state.active and state.nextTickFrame and frame >= state.nextTickFrame do
			ApplyBonusTickToAllyTeam(allyTeamID)
			state.nextTickFrame = state.nextTickFrame + TICK_FRAMES
		end
	end
end

local function ResetUnit(unitID)
	if GG.Attributes then
		GG.Attributes.RemoveEffect(unitID, GetEffectKey(unitID))
	end
	unitBonusTicks[unitID] = nil
end

function gadget:UnitDestroyed(unitID)
	ResetUnit(unitID)
end

function gadget:UnitTaken(unitID)
	ResetUnit(unitID)
end

function gadget:UnitGiven(unitID)
	ResetUnit(unitID)
end

function gadget:Initialize()
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))
	UpdateCardActivation()
end
