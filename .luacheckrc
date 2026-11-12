-- luacheck configuration for ProcFlare (WoW Forever, Lua 5.1)
std = "lua51"
max_line_length = false
codes = true

-- Reading WoW API globals (113) is not reported: there are too many to list.
-- Writing globals is, so a typo cannot create a new global without notice.
ignore = { "113", "212/self" }

globals = {
	"ProcFlareDB",
	"SLASH_PROCFLARE1",
	"SLASH_PROCFLARE2",
	"SlashCmdList",
	"ProcFlare_OnCompartmentClick",
	-- set only on clients without SetupColorPickerAndShow (old colour picker API)
	"ColorPickerFrame",
}

exclude_files = { ".release/**", "Libs/**" }
