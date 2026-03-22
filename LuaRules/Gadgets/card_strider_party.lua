function gadget:GetInfo()
	return {
		name = "Card Effect - Strider Party",
		desc = "Applies the Strider Party card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 109
local EFFECT_KEY = "zk_cards_strider_party"
local HEALTH_MULT = 0.2
local COST_MULT = 0.4
local SCALE_MULT = 0.4

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo

local gaiaAllyTeam
local striderHubDefID = UnitDefNames.striderhub and UnitDefNames.striderhub.id
local allyTeamActive = {}
local eligibleDefs = {}

if striderHubDefID then
	local buildOptions = UnitDefs[striderHubDefID].buildOptions or {}
	for i = 1, #buildOptions do
		local unitDefID = buildOptions[i]
		if not UnitDefs[unitDefID].isImmobile then
			eligibleDefs[unitDefID] = true
		end
	end
end

local function GetTeamAllyTeam(teamID)
	return select(6, spGetTeamInfo(teamID, false))
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
		end
	end
end

local function ApplyPartyEffect(unitID)
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, EFFECT_KEY, {
			healthMult = HEALTH_MULT,
			cost = COST_MULT,
			static = true,
		})
	end
	if GG.SetColvolScales then
		GG.SetColvolScales(unitID, {SCALE_MULT, SCALE_MULT, SCALE_MULT})
	end
	if GG.UnitModelRescale then
		GG.UnitModelRescale(unitID, SCALE_MULT)
	end
end

function gadget:UnitFromFactory(unitID, unitDefID, unitTeam, facID, facDefID)
	if facDefID ~= striderHubDefID or not eligibleDefs[unitDefID] then
		return
	end
	local allyTeamID = GetTeamAllyTeam(unitTeam)
	if allyTeamActive[allyTeamID] then
		ApplyPartyEffect(unitID)
	end
end

function gadget:GameFrame(frame)
	if frame % 30 == 0 then
		UpdateCardActivation()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
