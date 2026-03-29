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
local spGetAIInfo = Spring.GetAIInfo
local spGetModOptions = Spring.GetModOptions
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetPlayerList = Spring.GetPlayerList
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spIsCheatingEnabled = Spring.IsCheatingEnabled
local spGetPlayerRulesParam = Spring.GetPlayerRulesParam
local spSetGameRulesParam = Spring.SetGameRulesParam
local spSetPlayerRulesParam = Spring.SetPlayerRulesParam
local spSetTeamRulesParam = Spring.SetTeamRulesParam

local VOTE_STAGE_KEY = PREFIX .. "_vote_stage_seq"
local VOTE_SLOT_KEY = PREFIX .. "_vote_slot"

local gaiaAllyTeam
local BAD_TIME_CARD_ID = 315
local BAD_TIME_DURATION_FRAMES = 10 * 60 * constants.GAME_SPEED
local BAD_TIME_EXTRA_CARD_COUNT = 2
local BAD_TIME_TEMP_POOL = {
	301,
	302,
	303,
	304,
	305,
	306,
	308,
	309,
	311,
	314,
}

local appliedByAllyTeam = {}
local badTimeAnnouncementByAllyTeam = {}
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
local ApplyCardToAllyTeam

local modOptions = spGetModOptions() or {}

local function ClampNumberOption(value, default, minimum, maximum)
	value = tonumber(value)
	if not value then
		return default
	end
	return math.max(minimum, math.min(maximum, value))
end

local FIRST_DRAFT_FRAME = ClampNumberOption(modOptions.zk_cards_first_draft_seconds, constants.FIRST_DRAFT_FRAME / constants.GAME_SPEED, 0, 36000) * constants.GAME_SPEED
local SECOND_DRAFT_FRAME = ClampNumberOption(modOptions.zk_cards_second_draft_seconds, constants.SECOND_DRAFT_FRAME / constants.GAME_SPEED, 0, 36000) * constants.GAME_SPEED
local THIRD_DRAFT_FRAME = ClampNumberOption(modOptions.zk_cards_third_draft_seconds, constants.THIRD_DRAFT_FRAME / constants.GAME_SPEED, 0, 36000) * constants.GAME_SPEED
local REPEAT_DRAFT_INTERVAL_FRAMES = ClampNumberOption(modOptions.zk_cards_repeat_draft_interval_seconds, constants.REPEAT_DRAFT_INTERVAL_FRAMES / constants.GAME_SPEED, 1, 36000) * constants.GAME_SPEED
local OFFERS_PER_DRAFT = ClampNumberOption(modOptions.zk_cards_offers_per_draft, constants.OFFERS_PER_DRAFT, 1, constants.MAX_OFFERS_PER_DRAFT)
local CATEGORY_WEIGHTS = {
	[CATEGORY.NEUTRAL] = ClampNumberOption(modOptions.zk_cards_neutral_weight, constants.CATEGORY_WEIGHT_NEUTRAL, 0, 1000),
	[CATEGORY.GOOD] = ClampNumberOption(modOptions.zk_cards_good_weight, constants.CATEGORY_WEIGHT_GOOD, 0, 1000),
	[CATEGORY.BAD] = ClampNumberOption(modOptions.zk_cards_bad_weight, constants.CATEGORY_WEIGHT_BAD, 0, 1000),
}

local function ChooseWeightedCategory()
	local total = CATEGORY_WEIGHTS[CATEGORY.NEUTRAL] + CATEGORY_WEIGHTS[CATEGORY.GOOD] + CATEGORY_WEIGHTS[CATEGORY.BAD]
	if total <= 0 then
		return CATEGORY.NEUTRAL
	end
	local pick = math.random() * total
	local running = CATEGORY_WEIGHTS[CATEGORY.NEUTRAL]
	if pick <= running then
		return CATEGORY.NEUTRAL
	end
	running = running + CATEGORY_WEIGHTS[CATEGORY.GOOD]
	if pick <= running then
		return CATEGORY.GOOD
	end
	return CATEGORY.BAD
end

stage.nextOpenFrame = FIRST_DRAFT_FRAME

local function GetScheduledDraftFrame(seq)
	if seq <= 1 then
		return FIRST_DRAFT_FRAME
	elseif seq == 2 then
		return SECOND_DRAFT_FRAME
	elseif seq == 3 then
		return THIRD_DRAFT_FRAME
	end
	return THIRD_DRAFT_FRAME + (seq - 3) * REPEAT_DRAFT_INTERVAL_FRAMES
end

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

local function GetAllyTeamLabel(allyTeamID)
	local teamList = spGetTeamList(allyTeamID)
	local names = {}

	for i = 1, #teamList do
		local teamID = teamList[i]
		if teamID ~= spGetGaiaTeamID() then
			local _, leaderID, _, isAI = spGetTeamInfo(teamID, false)
			if isAI then
				local _, aiName, _, shortName = spGetAIInfo(teamID)
				names[#names + 1] = shortName or aiName or ("AI " .. teamID)
			else
				names[#names + 1] = spGetPlayerInfo(leaderID, false) or ("Team " .. teamID)
			end
		end
	end

	if #names == 0 then
		return string.format("Ally %d", allyTeamID)
	end

	return string.format("Ally %d | %s", allyTeamID, table.concat(names, ", "))
end

local function AnnounceResolvedDrafts()
	if not next(stage.drafts) then
		return
	end

	local count = 0
	local rawAllyTeams = spGetAllyTeamList() or {}
	for i = 1, #rawAllyTeams do
		local allyTeamID = rawAllyTeams[i]
		spSetGameRulesParam(PREFIX .. "_announce_" .. allyTeamID .. "_card", 0, PUBLIC_VISIBLE)
		spSetGameRulesParam(PREFIX .. "_announce_" .. allyTeamID .. "_extra_count", 0, PUBLIC_VISIBLE)
		spSetGameRulesParam(PREFIX .. "_announce_" .. allyTeamID .. "_extra_1", 0, PUBLIC_VISIBLE)
		spSetGameRulesParam(PREFIX .. "_announce_" .. allyTeamID .. "_extra_2", 0, PUBLIC_VISIBLE)
	end
	for allyTeamID, draft in pairs(stage.drafts) do
		if draft.resolved and draft.winningCardID then
			count = count + 1
			spSetGameRulesParam(PREFIX .. "_announce_" .. allyTeamID .. "_card", draft.winningCardID, PUBLIC_VISIBLE)
			local extra = badTimeAnnouncementByAllyTeam[allyTeamID]
			if extra and extra.cardIDs and draft.winningCardID == BAD_TIME_CARD_ID then
				spSetGameRulesParam(PREFIX .. "_announce_" .. allyTeamID .. "_extra_count", #extra.cardIDs, PUBLIC_VISIBLE)
				for i = 1, #extra.cardIDs do
					spSetGameRulesParam(PREFIX .. "_announce_" .. allyTeamID .. "_extra_" .. i, extra.cardIDs[i], PUBLIC_VISIBLE)
				end
			end
		end
	end
	if count > 0 then
		spSetGameRulesParam(PREFIX .. "_announce_count", count, PUBLIC_VISIBLE)
		spSetGameRulesParam(PREFIX .. "_announce_seq", spGetGameFrame(), PUBLIC_VISIBLE)
	end
	badTimeAnnouncementByAllyTeam = {}
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
	for slot = 1, constants.MAX_OFFERS_PER_DRAFT do
		spSetTeamRulesParam(teamID, PREFIX .. "_offer_" .. slot .. "_id", 0, ALLIED_VISIBLE)
		spSetTeamRulesParam(teamID, PREFIX .. "_offer_" .. slot .. "_votes", 0, ALLIED_VISIBLE)
	end
end

local function PublishAppliedHistory(allyTeamID)
	local appliedState = appliedByAllyTeam[allyTeamID]
	local teamList = spGetTeamList(allyTeamID)
	local activeCounts = {}
	local activeOrder = {}

	for i = 1, #appliedState.history do
		local entry = appliedState.history[i]
		local remaining = (appliedState.countByCardID[entry.cardID] or 0) - (activeCounts[entry.cardID] or 0)
		if remaining > 0 then
			activeCounts[entry.cardID] = (activeCounts[entry.cardID] or 0) + 1
			activeOrder[#activeOrder + 1] = entry.cardID
		end
	end

	local appliedCount = #activeOrder
	local lastHistoryEntry = appliedState.history[#appliedState.history]
	local lastApplied = lastHistoryEntry and lastHistoryEntry.cardID or 0
	local lastFrame = lastHistoryEntry and lastHistoryEntry.frame or 0

	for i = 1, #teamList do
		local teamID = teamList[i]
		spSetTeamRulesParam(teamID, PREFIX .. "_applied_count", appliedCount, ALLIED_VISIBLE)
		spSetTeamRulesParam(teamID, PREFIX .. "_last_applied_id", lastApplied, ALLIED_VISIBLE)
		spSetTeamRulesParam(teamID, PREFIX .. "_last_applied_frame", lastFrame, ALLIED_VISIBLE)
		for historyIndex = 1, appliedCount do
			spSetTeamRulesParam(teamID, PREFIX .. "_applied_" .. historyIndex .. "_id", activeOrder[historyIndex], ALLIED_VISIBLE)
		end
		for historyIndex = appliedCount + 1, #appliedState.history do
			spSetTeamRulesParam(teamID, PREFIX .. "_applied_" .. historyIndex .. "_id", nil, ALLIED_VISIBLE)
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
			for slot = 1, constants.MAX_OFFERS_PER_DRAFT do
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
			temporary = {},
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
				if #chosen >= OFFERS_PER_DRAFT then
					return
				end
			end
		end
	end

	TakeFromPool(cardData.idsByCategory[category], true)
	if #chosen < OFFERS_PER_DRAFT then
		TakeFromPool(cardData.idsByCategory[category], false)
	end

	return chosen
end

function ApplyEffect.record_only(allyTeamID, cardDef, context)
	return true
end

local function RegisterAppliedCard(allyTeamID, cardID, options)
	local appliedState = appliedByAllyTeam[allyTeamID]
	if not appliedState then
		return
	end

	options = options or {}
	local frame = options.frame or spGetGameFrame()
	appliedState.countByCardID[cardID] = (appliedState.countByCardID[cardID] or 0) + 1
	appliedState.history[#appliedState.history + 1] = {
		cardID = cardID,
		frame = frame,
		stageSeq = options.stageSeq or stage.seq,
		temporary = options.temporary or false,
		expiresFrame = options.expiresFrame,
		sourceCardID = options.sourceCardID,
	}
	if options.temporary then
		appliedState.temporary = appliedState.temporary or {}
		appliedState.temporary[#appliedState.temporary + 1] = {
			cardID = cardID,
			expiresFrame = options.expiresFrame or frame,
		}
	end
	PublishAppliedHistory(allyTeamID)
end

function ApplyEffect.bad_time(allyTeamID, cardDef, context)
	local appliedState = appliedByAllyTeam[allyTeamID]
	if not appliedState then
		return false
	end

	local chosen = {}
	local chosenSet = {
		[BAD_TIME_CARD_ID] = true,
	}
	local shuffled = ShuffleCopy(BAD_TIME_TEMP_POOL)
	for i = 1, #shuffled do
		local candidateID = shuffled[i]
		if not chosenSet[candidateID] and not appliedState.countByCardID[candidateID] then
			chosen[#chosen + 1] = candidateID
			chosenSet[candidateID] = true
			if #chosen >= BAD_TIME_EXTRA_CARD_COUNT then
				break
			end
		end
	end
	if #chosen < BAD_TIME_EXTRA_CARD_COUNT then
		for i = 1, #shuffled do
			local candidateID = shuffled[i]
			if not chosenSet[candidateID] then
				chosen[#chosen + 1] = candidateID
				chosenSet[candidateID] = true
				if #chosen >= BAD_TIME_EXTRA_CARD_COUNT then
					break
				end
			end
		end
	end
	if #chosen == 0 then
		return true
	end

	local frame = context.frame or spGetGameFrame()
	local expiresFrame = frame + BAD_TIME_DURATION_FRAMES
	for i = 1, #chosen do
		ApplyCardToAllyTeam(allyTeamID, chosen[i], {
			frame = frame,
			stageSeq = context.stageSeq,
			temporary = true,
			expiresFrame = expiresFrame,
			sourceCardID = BAD_TIME_CARD_ID,
		})
	end

	badTimeAnnouncementByAllyTeam[allyTeamID] = {
		cardIDs = chosen,
	}
	return true
end

ApplyCardToAllyTeam = function(allyTeamID, cardID, options)
	local appliedState = appliedByAllyTeam[allyTeamID]
	local cardDef = cardData.byID[cardID]
	if not (appliedState and cardDef) then
		return false
	end

	local effectFunc = ApplyEffect[cardDef.effectType] or ApplyEffect.record_only
	options = options or {}
	local frame = options.frame or spGetGameFrame()

	local ok = effectFunc(allyTeamID, cardDef, {
		stageSeq = options.stageSeq or stage.seq,
		frame = frame,
		temporary = options.temporary,
		expiresFrame = options.expiresFrame,
		sourceCardID = options.sourceCardID,
	})
	if not ok then
		return false
	end

	RegisterAppliedCard(allyTeamID, cardID, {
		frame = frame,
		stageSeq = options.stageSeq or stage.seq,
		temporary = options.temporary,
		expiresFrame = options.expiresFrame,
		sourceCardID = options.sourceCardID,
	})
	return true
end

local function EnsureAppliedState(allyTeamID)
	if appliedByAllyTeam[allyTeamID] then
		return true
	end
	if allyTeamID == gaiaAllyTeam then
		return false
	end

	appliedByAllyTeam[allyTeamID] = {
		countByCardID = {},
		history = {},
		temporary = {},
	}
	PublishAppliedHistory(allyTeamID)
	return true
end

local function ExpireTemporaryCards(frame)
	for allyTeamID, appliedState in pairs(appliedByAllyTeam) do
		local temporary = appliedState.temporary
		local changed = false
		if temporary then
			for i = #temporary, 1, -1 do
				local entry = temporary[i]
				if frame >= (entry.expiresFrame or 0) then
					local currentCount = appliedState.countByCardID[entry.cardID] or 0
					if currentCount > 1 then
						appliedState.countByCardID[entry.cardID] = currentCount - 1
					else
						appliedState.countByCardID[entry.cardID] = nil
					end
					table.remove(temporary, i)
					changed = true
				end
			end
		end
		if changed then
			PublishAppliedHistory(allyTeamID)
		end
	end
end

local function TryGrantCard(playerID, targetAllyTeamID, cardID)
	if not spIsCheatingEnabled() then
		return false
	end

	local _, active = spGetPlayerInfo(playerID, false)
	if not active then
		return false
	end

	targetAllyTeamID = tonumber(targetAllyTeamID)
	cardID = tonumber(cardID)
	if not (targetAllyTeamID and cardID and cardData.byID[cardID]) then
		return false
	end
	if not EnsureAppliedState(targetAllyTeamID) then
		return false
	end

	return ApplyCardToAllyTeam(targetAllyTeamID, cardID)
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

	AnnounceResolvedDrafts()

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
	stage.category = ChooseWeightedCategory()
	stage.openFrame = frame
	stage.closeFrame = frame + constants.VOTE_DURATION_FRAMES
	stage.nextOpenFrame = GetScheduledDraftFrame(stage.seq + 1)
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
			voteCounts = {},
			playerVotes = {},
			resolved = false,
			winningSlot = nil,
			winningCardID = nil,
		}
		for slot = 1, #offers do
			draft.voteCounts[slot] = 0
		end
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
	if not message then
		return
	end

	local targetAllyTeamText, grantCardText = message:match("^" .. PREFIX .. ":grant:(%-?%d+):(%d+)$")
	if targetAllyTeamText then
		TryGrantCard(playerID, targetAllyTeamText, grantCardText)
		return
	end

	if not stage.active then
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
	ExpireTemporaryCards(frame)
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
			temporary = {},
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
