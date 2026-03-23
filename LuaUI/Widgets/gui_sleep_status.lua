function widget:GetInfo()
	return {
		name = "Sleep Status",
		desc = "Shows the Sleep card status bar above sleeping units",
		author = "Codex",
		layer = 1,
		enabled = true,
	}
end

local SLEEP_BAR_WIDTH = 28
local SLEEP_BAR_HEIGHT = 4
local BAR_Y_OFFSET = 22
local SLEEP_DURATION_FRAMES = 30 * Game.gameSpeed

local spGetGameFrame = Spring.GetGameFrame
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitPosition = Spring.GetUnitPosition
local spGetUnitRulesParam = Spring.GetUnitRulesParam
local spGetVisibleUnits = Spring.GetVisibleUnits

local glBillboard = gl.Billboard
local glColor = gl.Color
local glPopMatrix = gl.PopMatrix
local glPushMatrix = gl.PushMatrix
local glRect = gl.Rect
local glText = gl.Text
local glTranslate = gl.Translate

local function Clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

function widget:DrawWorld()
	local gameFrame = spGetGameFrame()
	for _, unitID in ipairs(spGetVisibleUnits(-1, nil, false) or {}) do
		if spGetUnitRulesParam(unitID, "zk_cards_sleeping") == 1 then
			local endFrame = spGetUnitRulesParam(unitID, "zk_cards_sleep_end")
			local unitDefID = spGetUnitDefID(unitID)
			local x, y, z = spGetUnitPosition(unitID)
			if endFrame and unitDefID and x then
				local scale = spGetUnitRulesParam(unitID, "currentModelScale") or 1
				local height = (UnitDefs[unitDefID].height or 24) * scale
				local remaining = math.max(0, endFrame - gameFrame)
				local progress = Clamp(remaining / SLEEP_DURATION_FRAMES, 0, 1)

				glPushMatrix()
				glTranslate(x, y + height + BAR_Y_OFFSET, z)
				glBillboard()

				glColor(0, 0, 0, 0.55)
				glRect(-SLEEP_BAR_WIDTH, 0, SLEEP_BAR_WIDTH, SLEEP_BAR_HEIGHT + 8)

				glColor(0.18, 0.27, 0.52, 0.95)
				glRect(-SLEEP_BAR_WIDTH + 1, 1, SLEEP_BAR_WIDTH - 1, SLEEP_BAR_HEIGHT + 1)

				glColor(0.55, 0.74, 1.0, 0.95)
				glRect(-SLEEP_BAR_WIDTH + 1, 1, -SLEEP_BAR_WIDTH + 1 + (2 * (SLEEP_BAR_WIDTH - 1) * progress), SLEEP_BAR_HEIGHT + 1)

				glColor(1, 1, 1, 0.9)
				glText("Sleep " .. math.ceil(remaining / Game.gameSpeed) .. "s", 0, SLEEP_BAR_HEIGHT + 2, 5, "oc")

				glPopMatrix()
			end
		end
	end
end
