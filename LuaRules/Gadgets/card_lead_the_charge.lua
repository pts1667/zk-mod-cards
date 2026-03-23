function gadget:GetInfo()
	return {
		name = "Card Effect - Lead the Charge",
		desc = "Applies the Lead the Charge card effect",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return false
end

local CARD_ID = 210
local UPDATE_FRAMES = 15
local REQUIRED_COUNT = 5
local LEADER_COOLDOWN_FRAMES = 3 * 60 * Game.gameSpeed
local LEADER_SIZE_SCALE = 1.5
local LEADER_RANGE_MULT = 2.0
local LEADER_RELOAD_MULT = 2.0
local LEADER_HEALTH_MULT = 3.0
local AURA_RANGE_MULT = 1.4
local AURA_RELOAD_MULT = 1.4
local LEADER_COLOR = {1.0, 0.62, 0.22}
local LEADER_GLOW = {1.0, 0.72, 0.28, 0.45}
local AURA_COLOR = {1.0, 0.84, 0.58}
local INLOS_ACCESS = {inlos = true}

local spDestroyUnit = Spring.DestroyUnit
local spGetAllyTeamList = Spring.GetAllyTeamList
local spGetGaiaTeamID = Spring.GetGaiaTeamID
local spGetGameFrame = Spring.GetGameFrame
local spGetTeamInfo = Spring.GetTeamInfo
local spGetTeamList = Spring.GetTeamList
local spGetTeamUnits = Spring.GetTeamUnits
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitHealth = Spring.GetUnitHealth
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitTeam = Spring.GetUnitTeam
local spSetUnitRulesParam = Spring.SetUnitRulesParam

local gaiaAllyTeam
local allyTeamActive = {}
local trackedRecords = {}
local destructionQueue = {}

local function GetTeamAllyTeam(teamID)
	return teamID and select(6, spGetTeamInfo(teamID, false)) or nil
end

local function IsMobile(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return unitDef and not unitDef.isImmobile and true or false
end

local function MakeKey(teamID, unitDefID)
	return teamID .. ":" .. unitDefID
end

local function GetLeaderEffectKey(key)
	return "zk_cards_lead_leader_" .. key
end

local function GetAuraEffectKey(key)
	return "zk_cards_lead_aura_" .. key
end

local function EnsureRecord(teamID, unitDefID)
	local key = MakeKey(teamID, unitDefID)
	local record = trackedRecords[key]
	if not record then
		record = {
			key = key,
			teamID = teamID,
			unitDefID = unitDefID,
			members = {},
			auraTargets = {},
			cooldownEndFrame = 0,
		}
		trackedRecords[key] = record
	end
	return record
end

local function ClearLeaderVisuals(unitID)
	if GG.TintUnit then
		GG.TintUnit(unitID)
	end
	if GG.GlowUnit then
		GG.GlowUnit(unitID)
	end
	if GG.UnitModelRescale then
		GG.UnitModelRescale(unitID, 1)
	end
end

local function ApplyLeaderVisuals(unitID)
	if GG.TintUnit then
		GG.TintUnit(unitID, LEADER_COLOR)
	end
	if GG.GlowUnit then
		GG.GlowUnit(unitID, LEADER_GLOW)
	end
	if GG.UnitModelRescale then
		GG.UnitModelRescale(unitID, LEADER_SIZE_SCALE)
	end
end

local function ClearAuraVisuals(unitID)
	if GG.TintUnit then
		GG.TintUnit(unitID)
	end
end

local function ApplyAuraVisuals(unitID)
	if GG.TintUnit then
		GG.TintUnit(unitID, AURA_COLOR)
	end
end

local function RemoveAura(record)
	for unitID in pairs(record.auraTargets) do
		if GG.Attributes then
			GG.Attributes.RemoveEffect(unitID, GetAuraEffectKey(record.key))
		end
		if spGetUnitDefID(unitID) then
			ClearAuraVisuals(unitID)
			spSetUnitRulesParam(unitID, "zk_cards_lead_aura", 0, INLOS_ACCESS)
		end
	end
	record.auraTargets = {}
end

local function RemoveLeader(record)
	if record.leaderID then
		if GG.Attributes then
			GG.Attributes.RemoveEffect(record.leaderID, GetLeaderEffectKey(record.key))
		end
		if spGetUnitDefID(record.leaderID) then
			ClearLeaderVisuals(record.leaderID)
			spSetUnitRulesParam(record.leaderID, "zk_cards_leader", 0, INLOS_ACCESS)
		end
		record.leaderID = nil
	end
	record.leaderPos = nil
	RemoveAura(record)
end

local function ApplyLeader(record, unitID)
	record.leaderID = unitID
	if GG.Attributes then
		GG.Attributes.AddEffect(unitID, GetLeaderEffectKey(record.key), {
			healthMult = LEADER_HEALTH_MULT,
			range = LEADER_RANGE_MULT,
			reload = LEADER_RELOAD_MULT,
			static = true,
		})
	end
	ApplyLeaderVisuals(unitID)
	spSetUnitRulesParam(unitID, "zk_cards_leader", 1, INLOS_ACCESS)
end

local function CountFinishedMembers(record)
	local count = 0
	for unitID in pairs(record.members) do
		local unitDefID = spGetUnitDefID(unitID)
		local teamID = spGetUnitTeam(unitID)
		if unitDefID ~= record.unitDefID or teamID ~= record.teamID then
			record.members[unitID] = nil
		else
			local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
			if buildProgress == 1 then
				count = count + 1
			end
		end
	end
	return count
end

local function PickLeader(record)
	local candidates = {}
	for unitID in pairs(record.members) do
		local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
		if buildProgress == 1 then
			candidates[#candidates + 1] = unitID
		end
	end
	if #candidates >= REQUIRED_COUNT then
		return candidates[math.random(#candidates)]
	end
	return nil
end

local function GetLeaderAuraRange(unitDefID)
	local unitDef = UnitDefs[unitDefID]
	return (unitDef and unitDef.maxWeaponRange or 0) * LEADER_RANGE_MULT
end

local function UpdateAura(record)
	RemoveAura(record)
	local leaderID = record.leaderID
	if not leaderID or not spGetUnitDefID(leaderID) then
		return
	end

	local lx, ly, lz = spGetUnitPosition(leaderID)
	if not lx then
		return
	end
	record.leaderPos = {lx, ly, lz}

	local radius = GetLeaderAuraRange(record.unitDefID)
	local radiusSq = radius * radius
	for unitID in pairs(record.members) do
		if unitID ~= leaderID and spGetUnitDefID(unitID) == record.unitDefID and spGetUnitTeam(unitID) == record.teamID then
			local _, _, _, _, buildProgress = spGetUnitHealth(unitID)
			if buildProgress == 1 then
				local ux, _, uz = spGetUnitPosition(unitID)
				if ux then
					local dx = ux - lx
					local dz = uz - lz
					if dx * dx + dz * dz <= radiusSq then
						record.auraTargets[unitID] = true
						if GG.Attributes then
							GG.Attributes.AddEffect(unitID, GetAuraEffectKey(record.key), {
								range = AURA_RANGE_MULT,
								reload = AURA_RELOAD_MULT,
								static = true,
							})
						end
						ApplyAuraVisuals(unitID)
						spSetUnitRulesParam(unitID, "zk_cards_lead_aura", 1, INLOS_ACCESS)
					end
				end
			end
		end
	end
end

local function QueueLeaderDeathCascade(record, frame)
	local leaderID = record.leaderID
	if not leaderID then
		return
	end
	local leaderPos = record.leaderPos
	local lx, ly, lz = leaderPos and leaderPos[1], leaderPos and leaderPos[2], leaderPos and leaderPos[3]
	if not lx then
		lx, ly, lz = spGetUnitPosition(leaderID)
	end
	if not lx then
		return
	end
	local radius = GetLeaderAuraRange(record.unitDefID)
	local radiusSq = radius * radius
	for unitID in pairs(record.members) do
		if unitID ~= leaderID and spGetUnitDefID(unitID) == record.unitDefID and spGetUnitTeam(unitID) == record.teamID then
			local ux, _, uz = spGetUnitPosition(unitID)
			if ux then
				local dx = ux - lx
				local dz = uz - lz
				if dx * dx + dz * dz <= radiusSq then
					destructionQueue[#destructionQueue + 1] = unitID
				end
			end
		end
	end
	record.cooldownEndFrame = frame + LEADER_COOLDOWN_FRAMES
end

local function TrackUnit(unitID, unitDefID, teamID)
	if not unitDefID or not IsMobile(unitDefID) then
		return
	end
	local allyTeamID = GetTeamAllyTeam(teamID)
	if allyTeamID == gaiaAllyTeam or not allyTeamActive[allyTeamID] then
		return
	end
	local record = EnsureRecord(teamID, unitDefID)
	record.members[unitID] = true
end

local function UntrackUnit(unitID, unitDefID, teamID, wasDestroyed)
	if not unitDefID or not teamID then
		return
	end
	local key = MakeKey(teamID, unitDefID)
	local record = trackedRecords[key]
	if not record then
		return
	end
	record.members[unitID] = nil
	if record.auraTargets[unitID] then
		if GG.Attributes then
			GG.Attributes.RemoveEffect(unitID, GetAuraEffectKey(record.key))
		end
		record.auraTargets[unitID] = nil
		if spGetUnitDefID(unitID) then
			ClearAuraVisuals(unitID)
			spSetUnitRulesParam(unitID, "zk_cards_lead_aura", 0, INLOS_ACCESS)
		end
	end
	if record.leaderID == unitID then
		if wasDestroyed then
			local frame = spGetGameFrame()
			QueueLeaderDeathCascade(record, frame)
		end
		RemoveLeader(record)
	end
end

local function SweepAllyTeam(allyTeamID)
	for _, teamID in ipairs(spGetTeamList(allyTeamID) or {}) do
		for _, unitID in ipairs(spGetTeamUnits(teamID) or {}) do
			TrackUnit(unitID, spGetUnitDefID(unitID), teamID)
		end
	end
end

local function UpdateCardActivation()
	if not (GG.ZKCards and GG.ZKCards.HasAppliedCard) then
		return
	end
	for _, allyTeamID in ipairs(spGetAllyTeamList() or {}) do
		if allyTeamID ~= gaiaAllyTeam and not allyTeamActive[allyTeamID] and GG.ZKCards.HasAppliedCard(allyTeamID, CARD_ID) then
			allyTeamActive[allyTeamID] = true
			SweepAllyTeam(allyTeamID)
		end
	end
end

local function ProcessDestructionQueue()
	for i = 1, #destructionQueue do
		local unitID = destructionQueue[i]
		if spGetUnitDefID(unitID) then
			spDestroyUnit(unitID, false, true)
		end
	end
	destructionQueue = {}
end

local function UpdateRecords(frame)
	for key, record in pairs(trackedRecords) do
		local count = CountFinishedMembers(record)
		if record.leaderID and (not spGetUnitDefID(record.leaderID) or spGetUnitTeam(record.leaderID) ~= record.teamID) then
			RemoveLeader(record)
		end
		if record.leaderID then
			ApplyLeaderVisuals(record.leaderID)
			UpdateAura(record)
		elseif count >= REQUIRED_COUNT and frame >= (record.cooldownEndFrame or 0) then
			local leaderID = PickLeader(record)
			if leaderID then
				ApplyLeader(record, leaderID)
				UpdateAura(record)
			end
		end
		if count == 0 and not record.leaderID then
			trackedRecords[key] = nil
		end
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	TrackUnit(unitID, unitDefID, teamID)
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	TrackUnit(unitID, unitDefID, teamID)
end

function gadget:UnitGiven(unitID, unitDefID, newTeamID, oldTeamID)
	if oldTeamID then
		UntrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), oldTeamID, false)
	end
	TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	if oldTeamID then
		UntrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), oldTeamID, false)
	end
	TrackUnit(unitID, unitDefID or spGetUnitDefID(unitID), newTeamID)
end

function gadget:UnitDestroyed(unitID, unitDefID, teamID)
	UntrackUnit(unitID, unitDefID, teamID, true)
end

function gadget:GameFrame(frame)
	if frame % UPDATE_FRAMES == 0 then
		UpdateCardActivation()
		ProcessDestructionQueue()
		UpdateRecords(frame)
	end
end

function gadget:Initialize()
	gaiaAllyTeam = GetTeamAllyTeam(spGetGaiaTeamID())
	UpdateCardActivation()
end

function gadget:Shutdown()
	for _, record in pairs(trackedRecords) do
		RemoveLeader(record)
	end
end
