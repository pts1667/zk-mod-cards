function gadget:GetInfo()
	return {
		name = "Card Effect - No Terraform",
		desc = "Applies the No Terraform card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 311
local UPDATE_FRAMES = 30
local CMD_TERRAFORM_INTERNAL = 39801

local spDestroyUnit = Spring.DestroyUnit
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetUnitDefID = Spring.GetUnitDefID

local gaiaAllyTeam
local allyTeamActive = {}
local terraunitDefID = UnitDefNames.terraunit and UnitDefNames.terraunit.id

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam and not allyTeamActive[allyTeamID] and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
		end
	end
end

local function DestroyBlockedTerraunit(unitID, unitDefID, teamID)
	if unitDefID ~= terraunitDefID then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamActive[allyTeamID] then
		spDestroyUnit(unitID, false, true)
	end
end

function gadget:AllowCommand_GetWantedCommand()
	return {[CMD_TERRAFORM_INTERNAL] = true}
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID)
	if cmdID ~= CMD_TERRAFORM_INTERNAL then
		return true
	end
	return not allyTeamActive[GetTeamAllyTeam(teamID)]
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	DestroyBlockedTerraunit(unitID, unitDefID, teamID)
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	DestroyBlockedTerraunit(unitID, unitDefID, teamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID)
	DestroyBlockedTerraunit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	DestroyBlockedTerraunit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end
