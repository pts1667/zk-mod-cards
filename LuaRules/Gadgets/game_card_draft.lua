function gadget:GetInfo()
	return {
		name = "Card Draft",
		desc = "Authoritative side-based card draft flow and vote resolution",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local constants = VFS.Include("LuaRules/Configs/Cards/card_constants.lua")
local cardData = VFS.Include("LuaRules/Configs/Cards/card_defs.lua")

local CATEGORY = constants.CATEGORY
local PREFIX = constants.PREFIX
local ALLIED_VISIBLE = {allied = true}
local PUBLIC_VISIBLE = {public = true}

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGameFrame = Spring.GetGameFrame
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetPlayerList = Spring.GetPlayerList
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetPlayerRulesParam = Spring.GetPlayerRulesParam
local spSetGameRulesParam = Spring.SetGameRulesParam
local spSetPlayerRulesParam = Spring.SetPlayerRulesParam
local spSetTeamRulesParam = Spring.SetTeamRulesParam

local VOTE_STAGE_KEY = PREFIX .. "_vote_stage_seq"
local VOTE_SLOT_KEY = PREFIX .. "_vote_slot"

local gaiaAllyTeam

local appliedByAllyTeam = {}
local stage = {
	seq = 0,
	active = false,
	category = 0,
	openFrame = 0,
	closeFrame = 0,
	nextOpenFrame = constants.FIRST_DRAFT_FRAME,
	drafts = {},
}

local ApplyEffect = {}

local function ShuffleCopy(source)
	local copy = {}
	for i = 1, #source do
		copy[i] = source[i]
	end
	for i = #copy, 2, -1 do
		local j = math.random(i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
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

local function GetHumanPlayersForAllyTeam(allyTeamID)
	local players = {}
	local teamList = spGetTeamList(allyTeamID)
	for i = 1, #teamList do
		local playerList = spGetPlayerList(teamList[i], true) or {}
		for j = 1, #playerList do
			local playerID = playerList[j]
			local _, active, spectator = spGetPlayerInfo(playerID, false)
			if active and not spectator then
				players[#players + 1] = playerID
			end
		end
	end
	return players
end

local function ClearPlayerVote(playerID)
	spSetPlayerRulesParam(playerID, VOTE_STAGE_KEY, nil, ALLIED_VISIBLE)
	spSetPlayerRulesParam(playerID, VOTE_SLOT_KEY, nil, ALLIED_VISIBLE)
end

local function ClearTeamStageParams(teamID)
	spSetTeamRulesParam(teamID, PREFIX .. "_active", 0, ALLIED_VISIBLE)
	spSetTeamRulesParam(teamID, PREFIX .. "_stage_seq", stage.seq, ALLIED_VISIBLE)
	spSetTeamRulesParam(teamID, PREFIX .. "_stage_category", 0, ALLIED_VISIBLE)
	spSetTeamRulesParam(teamID, PREFIX .. "_open_frame", 0, ALLIED_VISIBLE)
	spSetTeamRulesParam(teamID, PREFIX .. "_close_frame", 0, ALLIED_VISIBLE)
	spSetTeamRulesParam(teamID, PREFIX .. "_offer_count", 0, ALLIED_VISIBLE)
	for slot = 1, constants.OFFERS_PER_DRAFT do
		spSetTeamRulesParam(teamID, PREFIX .. "_offer_" .. slot .. "_id", 0, ALLIED_VISIBLE)
		spSetTeamRulesParam(teamID, PREFIX .. "_offer_" .. slot .. "_votes", 0, ALLIED_VISIBLE)
	end
end

local function PublishAppliedHistory(allyTeamID)
	local appliedState = appliedByAllyTeam[allyTeamID]
	local teamList = spGetTeamList(allyTeamID)
	local appliedCount = #appliedState.history
	local lastApplied = appliedCount > 0 and appliedState.history[appliedCount].cardID or 0
	local lastFrame = appliedCount > 0 and appliedState.history[appliedCount].frame or 0

	for i = 1, #teamList do
		local teamID = teamList[i]
		spSetTeamRulesParam(teamID, PREFIX .. "_applied_count", appliedCount, ALLIED_VISIBLE)
		spSetTeamRulesParam(teamID, PREFIX .. "_last_applied_id", lastApplied, ALLIED_VISIBLE)
		spSetTeamRulesParam(teamID, PREFIX .. "_last_applied_frame", lastFrame, ALLIED_VISIBLE)
		for historyIndex = 1, appliedCount do
			spSetTeamRulesParam(teamID, PREFIX .. "_applied_" .. historyIndex .. "_id", appliedState.history[historyIndex].cardID, ALLIED_VISIBLE)
		end
	end
end

local function PublishGlobalStage()
	spSetGameRulesParam(PREFIX .. "_enabled", 1, PUBLIC_VISIBLE)
	spSetGameRulesParam(PREFIX .. "_stage_active", stage.active and 1 or 0, PUBLIC_VISIBLE)
	spSetGameRulesParam(PREFIX .. "_stage_seq", stage.seq, PUBLIC_VISIBLE)
	spSetGameRulesParam(PREFIX .. "_stage_category", stage.category or 0, PUBLIC_VISIBLE)
	spSetGameRulesParam(PREFIX .. "_stage_open_frame", stage.openFrame or 0, PUBLIC_VISIBLE)
	spSetGameRulesParam(PREFIX .. "_stage_close_frame", stage.closeFrame or 0, PUBLIC_VISIBLE)
	spSetGameRulesParam(PREFIX .. "_next_open_frame", stage.nextOpenFrame or 0, PUBLIC_VISIBLE)
end

local function PublishStageForAllyTeam(allyTeamID)
	local draft = stage.drafts[allyTeamID]
	local teamList = spGetTeamList(allyTeamID)
	for i = 1, #teamList do
		local teamID = teamList[i]
		if stage.active and draft then
			spSetTeamRulesParam(teamID, PREFIX .. "_active", draft.resolved and 0 or 1, ALLIED_VISIBLE)
			spSetTeamRulesParam(teamID, PREFIX .. "_stage_seq", stage.seq, ALLIED_VISIBLE)
			spSetTeamRulesParam(teamID, PREFIX .. "_stage_category", stage.category, ALLIED_VISIBLE)
			spSetTeamRulesParam(teamID, PREFIX .. "_open_frame", stage.openFrame, ALLIED_VISIBLE)
			spSetTeamRulesParam(teamID, PREFIX .. "_close_frame", stage.closeFrame, ALLIED_VISIBLE)
			spSetTeamRulesParam(teamID, PREFIX .. "_offer_count", #draft.offers, ALLIED_VISIBLE)
			for slot = 1, constants.OFFERS_PER_DRAFT do
				spSetTeamRulesParam(teamID, PREFIX .. "_offer_" .. slot .. "_id", draft.offers[slot] or 0, ALLIED_VISIBLE)
				spSetTeamRulesParam(teamID, PREFIX .. "_offer_" .. slot .. "_votes", draft.voteCounts[slot] or 0, ALLIED_VISIBLE)
			end
		else
			ClearTeamStageParams(teamID)
		end
	end
end

local function PublishAllStates()
	PublishGlobalStage()
	local allyTeams = GetLivingAllyTeams()
	for i = 1, #allyTeams do
		local allyTeamID = allyTeams[i]
		appliedByAllyTeam[allyTeamID] = appliedByAllyTeam[allyTeamID] or {
			countByCardID = {},
			history = {},
		}
		PublishStageForAllyTeam(allyTeamID)
		PublishAppliedHistory(allyTeamID)
	end
end

local function ChooseOffersForAllyTeam(allyTeamID, category)
	local appliedState = appliedByAllyTeam[allyTeamID]
	local chosen = {}
	local chosenSet = {}

	local function TakeFromPool(pool, excludeApplied)
		local shuffled = ShuffleCopy(pool)
		for i = 1, #shuffled do
			local cardID = shuffled[i]
			if not chosenSet[cardID] and (not excludeApplied or not appliedState.countByCardID[cardID]) then
				chosen[#chosen + 1] = cardID
				chosenSet[cardID] = true
				if #chosen >= constants.OFFERS_PER_DRAFT then
					return
				end
			end
		end
	end

	TakeFromPool(cardData.idsByCategory[category], true)
	if #chosen < constants.OFFERS_PER_DRAFT then
		TakeFromPool(cardData.idsByCategory[category], false)
	end

	return chosen
end

function ApplyEffect.record_only(allyTeamID, cardDef, context)
	return true
end

local function ApplyCardToAllyTeam(allyTeamID, cardID)
	local appliedState = appliedByAllyTeam[allyTeamID]
	local cardDef = cardData.byID[cardID]
	if not (appliedState and cardDef) then
		return false
	end

	local effectFunc = ApplyEffect[cardDef.effectType] or ApplyEffect.record_only

	local ok = effectFunc(allyTeamID, cardDef, {
		stageSeq = stage.seq,
		frame = spGetGameFrame(),
	})
	if not ok then
		return false
	end

	appliedState.countByCardID[cardID] = (appliedState.countByCardID[cardID] or 0) + 1
	appliedState.history[#appliedState.history + 1] = {
		cardID = cardID,
		frame = spGetGameFrame(),
		stageSeq = stage.seq,
	}
	PublishAppliedHistory(allyTeamID)
	return true
end

local function ResolveDraftForAllyTeam(allyTeamID, forcedSlot)
	local draft = stage.drafts[allyTeamID]
	if not draft or draft.resolved then
		return
	end

	local winningSlot = forcedSlot
	if not winningSlot then
		local bestVote = -1
		local topSlots = {}
		for slot = 1, #draft.offers do
			local voteCount = draft.voteCounts[slot] or 0
			if voteCount > bestVote then
				bestVote = voteCount
				topSlots = {slot}
			elseif voteCount == bestVote then
				topSlots[#topSlots + 1] = slot
			end
		end

		if bestVote <= 0 then
			winningSlot = math.random(#draft.offers)
		elseif #topSlots == 1 then
			winningSlot = topSlots[1]
		else
			winningSlot = topSlots[math.random(#topSlots)]
		end
	end

	draft.resolved = true
	draft.winningSlot = winningSlot
	draft.winningCardID = draft.offers[winningSlot]
	ApplyCardToAllyTeam(allyTeamID, draft.winningCardID)
	PublishStageForAllyTeam(allyTeamID)
end

local function AllDraftsResolved()
	for allyTeamID, draft in pairs(stage.drafts) do
		if not draft.resolved then
			return false
		end
	end
	return true
end

local function CloseActiveStage()
	if not stage.active then
		return
	end

	local allyTeams = GetLivingAllyTeams()
	for i = 1, #allyTeams do
		local players = GetHumanPlayersForAllyTeam(allyTeams[i])
		for j = 1, #players do
			ClearPlayerVote(players[j])
		end
	end

	stage.active = false
	stage.category = 0
	stage.openFrame = 0
	stage.closeFrame = 0
	stage.drafts = {}
	PublishAllStates()
end

local function OpenNewStage(frame)
	stage.seq = stage.seq + 1
	stage.active = true
	stage.category = math.random(CATEGORY.NEUTRAL, CATEGORY.BAD)
	stage.openFrame = frame
	stage.closeFrame = frame + constants.VOTE_DURATION_FRAMES
	stage.nextOpenFrame = frame + math.random(constants.MIN_DELAY_FRAMES, constants.MAX_DELAY_FRAMES)
	stage.drafts = {}

	local allyTeams = GetLivingAllyTeams()
	for i = 1, #allyTeams do
		local allyTeamID = allyTeams[i]
		appliedByAllyTeam[allyTeamID] = appliedByAllyTeam[allyTeamID] or {
			countByCardID = {},
			history = {},
		}

		local offers = ChooseOffersForAllyTeam(allyTeamID, stage.category)
		local players = GetHumanPlayersForAllyTeam(allyTeamID)
		local draft = {
			offers = offers,
			voteCounts = {0, 0, 0},
			playerVotes = {},
			resolved = false,
			winningSlot = nil,
			winningCardID = nil,
		}
		stage.drafts[allyTeamID] = draft

		for j = 1, #players do
			ClearPlayerVote(players[j])
			spSetPlayerRulesParam(players[j], VOTE_STAGE_KEY, stage.seq, ALLIED_VISIBLE)
		end

		if #players == 0 and #offers > 0 then
			ResolveDraftForAllyTeam(allyTeamID, math.random(#offers))
		end
	end

	PublishAllStates()
	if AllDraftsResolved() then
		CloseActiveStage()
	end
end

function gadget:RecvLuaMsg(message, playerID)
	if not (message and stage.active) then
		return
	end

	local seqText, slotText = message:match("^" .. PREFIX .. ":vote:(%d+):(%d+)$")
	if not seqText then
		return
	end

	local voteStageSeq = tonumber(seqText)
	local voteSlot = tonumber(slotText)
	if voteStageSeq ~= stage.seq or not voteSlot then
		return
	end

	local _, active, spectator, teamID, allyTeamID = spGetPlayerInfo(playerID, false)
	if spectator or not active then
		return
	end

	local draft = stage.drafts[allyTeamID]
	if not draft or draft.resolved or voteSlot < 1 or voteSlot > #draft.offers then
		return
	end

	local previousSlot = draft.playerVotes[playerID]
	if previousSlot == voteSlot then
		return
	end

	if previousSlot then
		draft.voteCounts[previousSlot] = math.max(0, (draft.voteCounts[previousSlot] or 0) - 1)
	end

	draft.playerVotes[playerID] = voteSlot
	draft.voteCounts[voteSlot] = (draft.voteCounts[voteSlot] or 0) + 1
	spSetPlayerRulesParam(playerID, VOTE_STAGE_KEY, stage.seq, ALLIED_VISIBLE)
	spSetPlayerRulesParam(playerID, VOTE_SLOT_KEY, voteSlot, ALLIED_VISIBLE)
	PublishStageForAllyTeam(allyTeamID)
end

function gadget:GameFrame(frame)
	if stage.active then
		if frame >= stage.closeFrame then
			for allyTeamID in pairs(stage.drafts) do
				ResolveDraftForAllyTeam(allyTeamID)
			end
			CloseActiveStage()
		elseif AllDraftsResolved() then
			CloseActiveStage()
		end
	elseif frame >= stage.nextOpenFrame then
		OpenNewStage(frame)
	end
end

function gadget:Initialize()
	gaiaAllyTeam = select(6, spGetTeamInfo(spGetGaiaTeamID(), false))

	local allyTeams = GetLivingAllyTeams()
	for i = 1, #allyTeams do
		appliedByAllyTeam[allyTeams[i]] = {
			countByCardID = {},
			history = {},
		}
	end

	PublishAllStates()

	GG.ZKCards = GG.ZKCards or {}
	GG.ZKCards.HasAppliedCard = function(allyTeamID, cardID)
		local appliedState = appliedByAllyTeam[allyTeamID]
		return appliedState and appliedState.countByCardID[cardID] and appliedState.countByCardID[cardID] > 0 or false
	end
	GG.ZKCards.GetAppliedFrame = function(allyTeamID, cardID)
		local appliedState = appliedByAllyTeam[allyTeamID]
		if not appliedState then
			return nil
		end
		for i = 1, #appliedState.history do
			if appliedState.history[i].cardID == cardID then
				return appliedState.history[i].frame
			end
		end
		return nil
	end
end

function gadget:PlayerChanged(playerID)
	if not stage.active then
		return
	end

	local voteStageSeq = spGetPlayerRulesParam(playerID, VOTE_STAGE_KEY)
	if voteStageSeq and voteStageSeq ~= stage.seq then
		ClearPlayerVote(playerID)
	end
end

function gadget:TeamDied(teamID)
	if stage.active and AllDraftsResolved() then
		CloseActiveStage()
	end
end
