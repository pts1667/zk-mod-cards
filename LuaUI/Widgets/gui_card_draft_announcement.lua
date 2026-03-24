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
		return
	end

	local rawAllyTeams = Spring.GetAllyTeamList() or {}
	local lines = {"Card picks:"}
	for i = 1, #rawAllyTeams do
		local allyTeamID = rawAllyTeams[i]
		local cardID = Spring.GetGameRulesParam(PREFIX .. "_announce_" .. allyTeamID .. "_card")
		local cardDef = cardID and cardData.byID[cardID]
		if cardDef then
			lines[#lines + 1] = string.format("%s picked %s", GetAllyTeamLabel(allyTeamID), cardDef.name)
		end
	end

	lastAnnouncementSeq = announcementSeq
	if #lines > 1 then
		SetAnnouncement(table.concat(lines, "\n"))
	end
end

function widget:Initialize()
	WG.ZKCardsDraftAnnouncement = SetAnnouncement
	RefreshFromRulesParams()
end

function widget:Shutdown()
	if WG.ZKCardsDraftAnnouncement == SetAnnouncement then
		WG.ZKCardsDraftAnnouncement = nil
	end
end

function widget:DrawScreen()
	RefreshFromRulesParams()

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
