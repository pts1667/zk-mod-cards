function gadget:GetInfo()
	return {
		name = "Card Draft Announcement Bridge",
		desc = "Bridges synced card draft announcements to LuaUI",
		author = "Codex",
		layer = 0,
		enabled = true,
	}
end

if gadgetHandler:IsSyncedCode() then
	return false
end

local SYNC_ACTION = "ZKCardsDraftAnnouncement"

function gadget:Initialize()
	gadgetHandler:AddSyncAction(SYNC_ACTION, function(_, text)
		if Script.LuaUI(SYNC_ACTION) then
			Script.LuaUI[SYNC_ACTION](text)
		end
	end)
end

function gadget:Shutdown()
	gadgetHandler:RemoveSyncAction(SYNC_ACTION)
end
