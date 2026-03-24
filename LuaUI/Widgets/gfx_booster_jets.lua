function widget:GetInfo()
	return {
		name = "Booster Jets FX",
		desc = "Adds LUPS exhaust bursts to units boosted by the Booster Jets card",
		author = "Codex",
		layer = 10,
		enabled = true,
	}
end

local UPDATE_FRAMES = 3
local ACTIVE_RULES_PARAM = "zk_cards_booster_jets_active"

local spGetGameFrame = Spring.GetGameFrame
local spGetUnitDirection = Spring.GetUnitDirection
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitRadius = Spring.GetUnitRadius
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetVisibleUnits = Spring.GetVisibleUnits
local spGetWind = Spring.GetWind

local AddParticles

local flameFX = {
	colormap = {
		{1.00, 1.00, 1.00, 0.01},
		{0.80, 0.90, 1.00, 0.06},
		{0.40, 0.75, 1.00, 0.08},
		{1.00, 0.55, 0.15, 0.22},
		{0.20, 0.20, 0.20, 0.08},
		{0.00, 0.00, 0.00, 0.01},
	},
	count = 5,
	life = 10,
	lifeSpread = 4,
	delaySpread = 2,
	force = {0, 0, 0},
	pos = {0, 0, 0},
	partpos = "",
	emitVector = {0, 0, 0},
	emitRotSpread = 18,
	rotSpeed = 1,
	rotSpread = 360,
	speed = 2.5,
	speedSpread = 1.2,
	size = 3,
	sizeSpread = 1.5,
	sizeGrowth = -0.08,
	texture = "bitmaps/GPL/flame.png",
}

local smokeFX = {
	colormap = {
		{0.10, 0.10, 0.10, 0.01},
		{0.30, 0.30, 0.30, 0.06},
		{0.18, 0.18, 0.18, 0.12},
		{0.00, 0.00, 0.00, 0.01},
	},
	count = 4,
	life = 15,
	lifeSpread = 5,
	delaySpread = 3,
	force = {0, 0, 0},
	pos = {0, 0, 0},
	partpos = "",
	emitVector = {0, 0, 0},
	emitRotSpread = 25,
	rotSpeed = 1,
	rotSpread = 360,
	speed = 1.4,
	speedSpread = 0.8,
	size = 5,
	sizeSpread = 2,
	sizeGrowth = 0.14,
	texture = "bitmaps/smoke/smoke04.tga",
}

local function SpawnBoostFx(unitID)
	local x, y, z = spGetUnitPosition(unitID)
	if not x then
		return
	end

	local dx, dy, dz = spGetUnitDirection(unitID)
	if not dx then
		return
	end

	local radius = spGetUnitRadius(unitID) or 18
	local wx, wy, wz = spGetWind()

	local rearX = x - dx * (radius * 0.75)
	local rearY = y + radius * 0.22
	local rearZ = z - dz * (radius * 0.75)

	flameFX.pos[1], flameFX.pos[2], flameFX.pos[3] = rearX, rearY, rearZ
	flameFX.emitVector[1], flameFX.emitVector[2], flameFX.emitVector[3] = -dx, math.max(0.05, -dy + 0.08), -dz
	flameFX.force[1], flameFX.force[2], flameFX.force[3] = wx * 0.02, 0.12 + wy * 0.02, wz * 0.02
	flameFX.partpos = string.format("%0.2f*r,0,%0.2f*r | r=rand()*2-1", dz * radius * 0.18, -dx * radius * 0.18)
	flameFX.size = math.max(3, radius * 0.16)
	flameFX.sizeSpread = flameFX.size * 0.45
	AddParticles("SimpleParticles2", flameFX)

	smokeFX.pos[1], smokeFX.pos[2], smokeFX.pos[3] = rearX, rearY, rearZ
	smokeFX.emitVector[1], smokeFX.emitVector[2], smokeFX.emitVector[3] = -dx * 0.55, 0.16, -dz * 0.55
	smokeFX.force[1], smokeFX.force[2], smokeFX.force[3] = wx * 0.05, 0.08 + wy * 0.02, wz * 0.05
	smokeFX.partpos = flameFX.partpos
	smokeFX.size = math.max(4, radius * 0.22)
	smokeFX.sizeSpread = smokeFX.size * 0.4
	AddParticles("SimpleParticles2", smokeFX)
end

function widget:GameFrame(frame)
	if frame % UPDATE_FRAMES ~= 0 then
		return
	end

	for _, unitID in ipairs(spGetVisibleUnits(-1, nil, false) or {}) do
		if spGetUnitRulesParam(unitID, ACTIVE_RULES_PARAM) == 1 then
			SpawnBoostFx(unitID)
		end
	end
end

function widget:Initialize()
	if not WG.Lups then
		widgetHandler:RemoveCallIn("GameFrame")
		return
	end
	AddParticles = WG.Lups.AddParticles
end

function widget:PlayerChanged()
	if not WG.Lups then
		widgetHandler:RemoveCallIn("GameFrame")
	end
end
