--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:GetInfo()
	return {
		name = "Stockpile",
		desc = "Partial reimplementation of stockpile system.",
		author = "Google Frog, Codex",
		date = "26 Feb, 2013",
		license = "GNU GPL, v2 or later",
		layer = -1,
		enabled = true,
	}
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if not gadgetHandler:IsSyncedCode() then
	return false
end

include("LuaRules/Configs/constants.lua")

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local PERIOD = 6

local spGetUnitStockpile = Spring.GetUnitStockpile
local spSetUnitStockpile = Spring.SetUnitStockpile
local spGetUnitIsStunned = Spring.GetUnitIsStunned
local spUseUnitResource = Spring.UseUnitResource
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spSetUnitRulesParam = Spring.SetUnitRulesParam

local stockpileUnitDefID = {}
local units = {data = {}, count = 0}
local unitsByID = {}
local freeStockpile = false

local function MakeStockpileDef(stockTime, stockCost)
	return {
		stockUpdates = stockTime / PERIOD,
		stockCost = stockCost,
		stockDrain = (stockTime > 0 and TEAM_SLOWUPDATE_RATE * stockCost / stockTime) or 0,
		perUpdateCost = (stockTime > 0 and PERIOD * stockCost / stockTime) or 0,
	}
end

for i = 1, #UnitDefs do
	local udef = UnitDefs[i]
	if udef.customParams.stockpiletime then
		local stockTime = tonumber(udef.customParams.stockpiletime) * TEAM_SLOWUPDATE_RATE
		local stockCost = tonumber(udef.customParams.stockpilecost)
		stockpileUnitDefID[i] = MakeStockpileDef(stockTime, stockCost)
	end
end

local function GetStockSpeed(unitID)
	return spGetUnitRulesParam(unitID, "totalBuildPowerChange") or 1
end

local function GetStockpileDef(unitID, unitDefID, teamID)
	local def = stockpileUnitDefID[unitDefID]
	if not def then
		return nil
	end
	if GG.StockpileOverride_Get then
		local override = GG.StockpileOverride_Get(unitID, unitDefID, teamID, def)
		if override then
			local stockTime = override.stockTime or (override.stockUpdates and override.stockUpdates * PERIOD) or (def.stockUpdates * PERIOD)
			local stockCost = override.stockCost ~= nil and override.stockCost or def.stockCost
			local resolved = MakeStockpileDef(stockTime, stockCost)
			if override.stockUpdates then
				resolved.stockUpdates = override.stockUpdates
			end
			if override.stockDrain ~= nil then
				resolved.stockDrain = override.stockDrain
			end
			if override.perUpdateCost ~= nil then
				resolved.perUpdateCost = override.perUpdateCost
			end
			return resolved
		end
	end
	return def
end

local function SyncUnitDefState(unitID, data, def)
	if not data.stockUpdates then
		data.stockUpdates = def.stockUpdates
		data.stockCost = def.stockCost
		return
	end
	if math.abs(data.stockUpdates - def.stockUpdates) < 0.001 then
		if data.stockCost ~= def.stockCost then
			if data.stockCost and data.stockCost > 0 and def.stockCost == 0 and data.stockSpeed ~= 0 then
				GG.StopMiscPriorityResourcing(unitID)
			end
			data.stockCost = def.stockCost
		end
		return
	end
	local progressRatio = (data.stockUpdates > 0) and (data.progress / data.stockUpdates) or 1
	data.stockUpdates = def.stockUpdates
	data.stockCost = def.stockCost
	data.progress = def.stockUpdates * progressRatio
end

function gadget:GameFrame(n)
	if n % PERIOD ~= 0 then
		return
	end

	for i = 1, units.count do
		local unitID = units.data[i]
		local data = unitsByID[unitID]
		local def = GetStockpileDef(unitID, data.unitDefID, data.teamID)
		if def then
			SyncUnitDefState(unitID, data, def)

			local stocked, queued = spGetUnitStockpile(unitID)
			local stunnedOrInbuild = spGetUnitIsStunned(unitID)
			local disarmed = (spGetUnitRulesParam(unitID, "disarmed") == 1)
			local cmdID = Spring.GetUnitCurrentCommand(unitID)
			local isWaiting = cmdID and (cmdID == CMD.WAIT)

			if not (stunnedOrInbuild or disarmed) and queued ~= 0 and not (isWaiting and (def.stockCost > 0)) then
				if freeStockpile then
					spSetUnitStockpile(unitID, stocked, 1)
					spSetUnitRulesParam(unitID, "gadgetStockpile", (def.stockUpdates - data.progress) / def.stockUpdates)
				else
					local newStockSpeed = GetStockSpeed(unitID)
					if data.stockSpeed ~= newStockSpeed then
						if def.stockCost > 0 then
							GG.StartMiscPriorityResourcing(unitID, def.stockDrain * newStockSpeed)
						elseif data.stockSpeed ~= 0 then
							GG.StopMiscPriorityResourcing(unitID)
						end
						data.stockSpeed = newStockSpeed
					end

					if def.stockCost > 0 then
						local scale = GG.GetMiscPrioritySpendScale(unitID, data.teamID)
						newStockSpeed = newStockSpeed * scale
						data.resTable.m = def.perUpdateCost * newStockSpeed
						data.resTable.e = data.resTable.m
					end

					if newStockSpeed > 0 and ((def.stockCost == 0) or spUseUnitResource(unitID, data.resTable)) then
						data.progress = data.progress - newStockSpeed
						if data.progress <= 0 then
							spSetUnitStockpile(unitID, stocked, 1)
							data.progress = def.stockUpdates
						end
						spSetUnitRulesParam(unitID, "gadgetStockpile", (def.stockUpdates - data.progress) / def.stockUpdates)
					end
				end
			else
				if data.stockSpeed ~= 0 then
					if def.stockCost > 0 then
						GG.StopMiscPriorityResourcing(unitID)
					end
					data.stockSpeed = 0
				end
			end
		end
	end
end

function gadget:StockpileChanged(unitID, unitDefID, unitTeam, weaponNum, oldCount, newCount)
	local scriptFunc = Spring.UnitScript.GetScriptEnv(unitID).StockpileChanged
	if scriptFunc then
		Spring.UnitScript.CallAsUnit(unitID, scriptFunc, newCount)
	end
end

function gadget:UnitCreated(unitID, unitDefID, teamID)
	local def = GetStockpileDef(unitID, unitDefID, teamID)
	if def and not unitsByID[unitID] and def.stockCost > 0 then
		GG.AddMiscPriorityUnit(unitID)
	end
end

function gadget:UnitFinished(unitID, unitDefID, teamID)
	local def = GetStockpileDef(unitID, unitDefID, teamID)
	if def and not unitsByID[unitID] then
		units.count = units.count + 1
		units.data[units.count] = unitID
		unitsByID[unitID] = {
			id = units.count,
			progress = def.stockUpdates,
			unitDefID = unitDefID,
			teamID = teamID,
			stockSpeed = 0,
			stockUpdates = def.stockUpdates,
			stockCost = def.stockCost,
			resTable = {
				m = def.perUpdateCost,
				e = def.perUpdateCost,
			},
		}
	end
end

function gadget:UnitDestroyed(unitID)
	if unitsByID[unitID] then
		units.data[unitsByID[unitID].id] = units.data[units.count]
		unitsByID[units.data[units.count]].id = unitsByID[unitID].id
		units.data[units.count] = nil
		units.count = units.count - 1
		unitsByID[unitID] = nil
	end
end

function gadget:UnitTaken(unitID, unitDefID, oldTeamID, teamID)
	if unitsByID[unitID] then
		unitsByID[unitID].teamID = teamID
		unitsByID[unitID].stockSpeed = 0
	end
end

function GG.SetFreeStockpile(enabled)
	freeStockpile = enabled
end

function gadget:Initialize()
	for _, unitID in ipairs(Spring.GetAllUnits()) do
		local unitDefID = Spring.GetUnitDefID(unitID)
		local teamID = Spring.GetUnitTeam(unitID)
		gadget:UnitCreated(unitID, unitDefID, teamID)
		gadget:UnitFinished(unitID, unitDefID, teamID)
	end
end
