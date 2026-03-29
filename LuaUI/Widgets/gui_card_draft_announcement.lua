function widget:GetInfo()
	return {
		name = "Card Draft Announcement",
		desc = "Shows transient on-screen announcements for resolved card drafts",
		author = "Codex",
		layer = 5,
		enabled = true,
	}
end

local constants = VFS.Include("LuaRules/Configs/Cards/card_constants.lua")
local cardData = VFS.Include("LuaRules/Configs/Cards/card_defs.lua")

local PREFIX = constants.PREFIX
local glColor = gl.Color
local glText = gl.Text

local announcementText = false
local expireAt = 0
local lastAnnouncementSeq = 0
local lastBountyAnnouncementSeq = 0
local DISPLAY_SECONDS = 7
local HEADLINE_SIZE = 34
local BODY_SIZE = 22

local function SetAnnouncement(text)
	announcementText = text
	expireAt = os.clock() + DISPLAY_SECONDS
end

function ZKCardsDraftAnnouncement(text)
	SetAnnouncement(text)
end

function widget:ZKCardsDraftAnnouncement(text)
	SetAnnouncement(text)
end

local function GetAllyTeamLabel(allyTeamID)
	local teamList = Spring.GetTeamList(allyTeamID) or {}
	local names = {}

	for i = 1, #teamList do
		local teamID = teamList[i]
		if teamID ~= Spring.GetGaiaTeamID() then
			local _, leaderID, _, isAI = Spring.GetTeamInfo(teamID, false)
			if isAI then
				local _, aiName, _, shortName = Spring.GetAIInfo(teamID)
				names[#names + 1] = shortName or aiName or ("AI " .. teamID)
			else
				names[#names + 1] = Spring.GetPlayerInfo(leaderID, false) or ("Team " .. teamID)
			end
		end
	end

	if #names == 0 then
		return string.format("Ally %d", allyTeamID)
	end

	return string.format("Ally %d | %s", allyTeamID, table.concat(names, ", "))
end

local function RefreshFromRulesParams()
	local announcementSeq = Spring.GetGameRulesParam(PREFIX .. "_announce_seq") or 0
	if announcementSeq <= 0 or announcementSeq == lastAnnouncementSeq then
		return false
	end

	local rawAllyTeams = Spring.GetAllyTeamList() or {}
	local lines = {"Card picks:"}
	for i = 1, #rawAllyTeams do
		local allyTeamID = rawAllyTeams[i]
		local cardID = Spring.GetGameRulesParam(PREFIX .. "_announce_" .. allyTeamID .. "_card")
		local cardDef = cardID and cardData.byID[cardID]
		if cardDef then
			local line = string.format("%s picked %s", GetAllyTeamLabel(allyTeamID), cardDef.name)
			local extraCount = Spring.GetGameRulesParam(PREFIX .. "_announce_" .. allyTeamID .. "_extra_count") or 0
			if extraCount > 0 then
				local extraNames = {}
				for extraIndex = 1, extraCount do
					local extraCardID = Spring.GetGameRulesParam(PREFIX .. "_announce_" .. allyTeamID .. "_extra_" .. extraIndex)
					local extraCardDef = extraCardID and cardData.byID[extraCardID]
					if extraCardDef then
						extraNames[#extraNames + 1] = extraCardDef.name
					end
				end
				if #extraNames > 0 then
					line = string.format("%s (%s)", line, table.concat(extraNames, ", "))
				end
			end
			lines[#lines + 1] = line
		end
	end

	lastAnnouncementSeq = announcementSeq
	if #lines > 1 then
		SetAnnouncement(table.concat(lines, "\n"))
		return true
	end
	return false
end

local function RefreshBountyAnnouncement()
	local announcementSeq = Spring.GetGameRulesParam(PREFIX .. "_bounty_announce_seq") or 0
	if announcementSeq <= 0 or announcementSeq == lastBountyAnnouncementSeq then
		return false
	end

	local teamID = Spring.GetGameRulesParam(PREFIX .. "_bounty_announce_team")
	local unitDefID = Spring.GetGameRulesParam(PREFIX .. "_bounty_announce_unitdef")
	local unitDef = unitDefID and UnitDefs[unitDefID]
	if not (teamID and unitDef) then
		lastBountyAnnouncementSeq = announcementSeq
		return false
	end

	lastBountyAnnouncementSeq = announcementSeq
	local ownerName = "Unknown"
	local _, leaderPlayerID = Spring.GetTeamInfo(teamID, false)
	if leaderPlayerID and leaderPlayerID >= 0 then
		ownerName = Spring.GetPlayerInfo(leaderPlayerID, false) or ownerName
	end
	SetAnnouncement(string.format(
		"Bounty:\nIf %s's %s is destroyed, everyone gets an economy bonus.",
		ownerName,
		unitDef.humanName or unitDef.name or "unit"
	))
	return true
end

function widget:Initialize()
	WG.ZKCardsDraftAnnouncement = SetAnnouncement
	RefreshFromRulesParams()
	RefreshBountyAnnouncement()
end

function widget:Shutdown()
	if WG.ZKCardsDraftAnnouncement == SetAnnouncement then
		WG.ZKCardsDraftAnnouncement = nil
	end
end

function widget:DrawScreen()
	if not RefreshFromRulesParams() then
		RefreshBountyAnnouncement()
	end

	if not announcementText then
		return
	end

	local remaining = expireAt - os.clock()
	if remaining <= 0 then
		announcementText = false
		return
	end

	local vsx, vsy = Spring.GetViewGeometry()
	local alpha = math.min(1, remaining)
	local y2 = math.floor(vsy * 0.74)

	local title, body = announcementText:match("([^\n]+)\n?(.*)")
	glColor(1, 0.86, 0.40, alpha)
	glText(title or "", vsx * 0.5, y2 - 42, HEADLINE_SIZE, "con")

	glColor(1, 1, 1, alpha)
	glText(body or "", vsx * 0.5, y2 - 78, BODY_SIZE, "con")
end
