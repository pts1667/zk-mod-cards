function gadget:GetInfo()
	return {
		name = "Card Effect - No Cloak",
		desc = "Applies the No Cloak card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 314
local UPDATE_FRAMES = 15
local CMD_CLOAK = CMD.CLOAK
local CMD_WANT_CLOAK = Spring.Utilities.CMD.WANT_CLOAK
local INLOS_ACCESS = {inlos = true}

local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetAllUnits = Spring.GetAllUnits
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetTeamInfo = Spring.GetTeamInfo
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetUnitTeam = Spring.GetUnitTeam
local spSetUnitCloak = Spring.SetUnitCloak
local spSetUnitRulesParam = Spring.SetUnitRulesParam

local gaiaAllyTeam
local allyTeamActive = {}
local forcedUnits = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function ForceNoCloak(unitID)
	local data = forcedUnits[unitID]
	if not data then
		data = {
			previousCannotCloak = spGetUnitRulesParam(unitID, "cannotcloak") or 0,
		}
		forcedUnits[unitID] = data
	end
	spSetUnitRulesParam(unitID, "wantcloak", 0, INLOS_ACCESS)
	spSetUnitRulesParam(unitID, "cannotcloak", 1, INLOS_ACCESS)
	spSetUnitCloak(unitID, 0)
end

local function RestoreCloak(unitID)
	local data = forcedUnits[unitID]
	if not data then
		return
	end
	spSetUnitRulesParam(unitID, "cannotcloak", data.previousCannotCloak, INLOS_ACCESS)
	forcedUnits[unitID] = nil
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam then
			allyTeamActive[allyTeamID] = GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) or false
		end
	end
end

function gadget:AllowCommand_GetWantedCommand()
	return {
		[CMD_CLOAK] = true,
		[CMD_WANT_CLOAK] = true,
	}
end

function gadget:AllowCommand(unitID, unitDefID, teamID, cmdID, cmdParams, cmdOptions)
	if cmdID ~= CMD_CLOAK and cmdID ~= CMD_WANT_CLOAK then
		return true
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if not allyTeamActive[allyTeamID] then
		return true
	end
	ForceNoCloak(unitID)
	return false
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES ~= 0 then
		return
	end

	UpdateCardActivation()
	for _, unitID in ipairs(spGetAllUnits()) do
		local teamID = spGetUnitTeam(unitID)
		local unitDefID = spGetUnitDefID(unitID)
		if teamID and unitDefID then
			local allyTeamID = GetTeamAllyTeam(teamID)
			if allyTeamActive[allyTeamID] then
				ForceNoCloak(unitID)
			else
				RestoreCloak(unitID)
			end
		end
	end
end

function gadget:UnitDestroyed(unitID)
	forcedUnits[unitID] = nil
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
	for _, unitID in ipairs(spGetAllUnits()) do
		local teamID = spGetUnitTeam(unitID)
		local unitDefID = spGetUnitDefID(unitID)
		if teamID and unitDefID and allyTeamActive[GetTeamAllyTeam(teamID)] then
			ForceNoCloak(unitID)
		end
	end
end

function gadget:Shutdown()
	for _, unitID in ipairs(spGetAllUnits()) do
		RestoreCloak(unitID)
	end
end
