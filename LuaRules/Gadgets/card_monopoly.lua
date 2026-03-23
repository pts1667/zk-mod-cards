function gadget:GetInfo()
	return {
		name = "Card Effect - Monopoly",
		desc = "Applies the Monopoly card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 212
local SAMPLE_FRAMES = Game.gameSpeed
local WINDOW_SAMPLES = 180
local BONUS_MULT = 0.5
local EPSILON = 0.001

local spAddTeamResource = Spring.AddTeamResource
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamResources = Spring.GetTeamResources

local gaiaAllyTeam
local allyTeamActive = {}
local incomeHistory = {}

local function GetOrCreateHistory(allyTeamID)
	local history = incomeHistory[allyTeamID]
	if not history then
		history = {
			samples = {},
			index = 1,
			count = 0,
			sum = 0,
			currentAverage = 0,
		}
		incomeHistory[allyTeamID] = history
	end
	return history
end

local function GetLiveAllyTeams()
	local live = {}
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam then
			local teamList = spGetTeamList(allyTeamID) or {}
			for i = 1, #teamList do
				local _, _, isDead = spGetTeamInfo(teamList[i], false)
				if not isDead then
					live[#live + 1] = allyTeamID
					break
				end
			end
		end
	end
	return live
end

local function SampleAllyTeamIncome(allyTeamID)
	local total = 0
	local teamList = spGetTeamList(allyTeamID) or {}
	for i = 1, #teamList do
		local _, _, _, income = spGetTeamResources(teamList[i], "metal")
		total = total + (income or 0)
	end
	return total
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(GetLiveAllyTeams()) do
		if GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
			GetOrCreateHistory(allyTeamID)
		end
	end
end

local function PushSample(history, value)
	if history.count == WINDOW_SAMPLES then
		history.sum = history.sum - history.samples[history.index]
	else
		history.count = history.count + 1
	end
	history.samples[history.index] = value
	history.sum = history.sum + value
	history.index = (history.index % WINDOW_SAMPLES) + 1
	history.currentAverage = history.sum / history.count
end

local function UpdateSamples()
	for _, allyTeamID in ipairs(GetLiveAllyTeams()) do
		PushSample(GetOrCreateHistory(allyTeamID), SampleAllyTeamIncome(allyTeamID))
	end
end

local function ApplyBonus()
	local liveAllyTeams = GetLiveAllyTeams()
	local highestAverage = 0
	for i = 1, #liveAllyTeams do
		local history = incomeHistory[liveAllyTeams[i]]
		if history and history.currentAverage > highestAverage then
			highestAverage = history.currentAverage
		end
	end

	if highestAverage <= 0 then
		return
	end

	for i = 1, #liveAllyTeams do
		local allyTeamID = liveAllyTeams[i]
		local history = incomeHistory[allyTeamID]
		if allyTeamActive[allyTeamID] and history and history.count > 0 and history.currentAverage >= highestAverage - EPSILON then
			local bonusIncome = history.currentAverage * BONUS_MULT
			local teamList = spGetTeamList(allyTeamID) or {}
			local weights = {}
			local totalIncome = 0
			for j = 1, #teamList do
				local _, _, _, income = spGetTeamResources(teamList[j], "metal")
				weights[j] = math.max(0, income or 0)
				totalIncome = totalIncome + weights[j]
			end
			for j = 1, #teamList do
				local weight
				if totalIncome > 0 then
					weight = weights[j] / totalIncome
				else
					weight = 1 / math.max(1, #teamList)
				end
				spAddTeamResource(teamList[j], "metal", bonusIncome * weight)
			end
		end
	end
end

function gadget:GameFrame(frame)
	if frame % SAMPLE_FRAMES == 0 then
		UpdateCardActivation()
		UpdateSamples()
		ApplyBonus()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))
	UpdateCardActivation()
end
