function widget:GetInfo()
	return {
		name = "Metal Fuel Debt",
		desc = "Displays Metal Fuel debt near the resource bars",
		author = "Codex",
		layer = 2,
		enabled = true,
	}
end

local TEAM_DEBT_RULES_PARAM = "zk_cards_metal_fuel_debt"

local spGetMyTeamID = Spring.GetMyTeamID
local spGetTeamRulesParam = Spring.GetTeamRulesParam
local spGetViewGeometry = Spring.GetViewGeometry

local glColor = gl.Color
local glRect = gl.Rect
local glText = gl.Text

function widget:DrawScreen()
	local debt = spGetTeamRulesParam(spGetMyTeamID(), TEAM_DEBT_RULES_PARAM) or 0
	if debt <= 0.01 then
		return
	end

	local vsx, vsy = spGetViewGeometry()
	local x = math.floor(vsx * 0.73)
	local y = vsy - 54
	local text = string.format("Metal Debt: %d", math.ceil(debt))

	glColor(0, 0, 0, 0.55)
	glRect(x - 10, y - 6, x + 180, y + 18)

	glColor(0.96, 0.52, 0.22, 1)
	glText(text, x, y, 18, "o")
end
