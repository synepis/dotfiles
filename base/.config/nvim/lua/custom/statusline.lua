local M = {}

local function make_mode_config(label, label_short, highlight_group)
	return { label = label, label_short = label_short, highlight_group = highlight_group }
end

local mode_configs = {
	-- Normal Modes
	["n"] = make_mode_config("NORMAL", "N", "StatusModeNormal"),
	["niI"] = make_mode_config("NORMAL", "N", "StatusModeNormal"),
	["niR"] = make_mode_config("NORMAL", "N", "StatusModeNormal"),
	["niV"] = make_mode_config("NORMAL", "N", "StatusModeNormal"),
	["nt"] = make_mode_config("N-TERM", "N-T", "StatusModeNormal"),
	["ntT"] = make_mode_config("N-TERM", "N-T", "StatusModeNormal"),

	-- Operator-Pending
	["no"] = make_mode_config("N-OPERATOR", "NO", "StatusModeNormal"),
	["nov"] = make_mode_config("N-OPERATOR", "NO", "StatusModeNormal"),
	["noV"] = make_mode_config("N-OPERATOR", "NO", "StatusModeNormal"),
	["no\22"] = make_mode_config("N-OPERATOR", "NO", "StatusModeNormal"),

	-- Visual Modes
	["v"] = make_mode_config("VISUAL", "V", "StatusModeVisual"),
	["vs"] = make_mode_config("VISUAL", "V", "StatusModeVisual"),
	["V"] = make_mode_config("V-LINE", "V-L", "StatusModeVisual"),
	["Vs"] = make_mode_config("V-LINE", "V-L", "StatusModeVisual"),
	["\22"] = make_mode_config("V-BLOCK", "V-B", "StatusModeVisual"),
	["\22s"] = make_mode_config("V-BLOCK", "V-B", "StatusModeVisual"),

	-- Select Modes
	["s"] = make_mode_config("SELECT", "S", "StatusModeSelect"),
	["S"] = make_mode_config("S-LINE", "S-L", "StatusModeSelect"),
	["\19"] = make_mode_config("S-BLOCK", "S-B", "StatusModeSelect"),

	-- Insert Modes
	["i"] = make_mode_config("INSERT", "I", "StatusModeInsert"),
	["ic"] = make_mode_config("INSERT", "I", "StatusModeInsert"),
	["ix"] = make_mode_config("INSERT", "I", "StatusModeInsert"),

	-- Replace Modes
	["R"] = make_mode_config("REPLACE", "R", "StatusModeReplace"),
	["Rc"] = make_mode_config("REPLACE", "R", "StatusModeReplace"),
	["Rx"] = make_mode_config("REPLACE", "R", "StatusModeReplace"),
	["Rv"] = make_mode_config("V-REPLACE", "V-R", "StatusModeReplace"),
	["Rvc"] = make_mode_config("V-REPLACE", "V-R", "StatusModeReplace"),
	["Rvx"] = make_mode_config("V-REPLACE", "V-R", "StatusModeReplace"),

	-- Command & Ex Modes
	["c"] = make_mode_config("COMMAND", "C", "StatusModeCommand"),
	["cv"] = make_mode_config("VIM EX", "VX", "StatusModeCommand"),
	["ce"] = make_mode_config("EX", "X", "StatusModeCommand"),

	-- Prompt / Confirm / System
	["r"] = make_mode_config("PROMPT", "P", "StatusModeCommand"),
	["rm"] = make_mode_config("MORE", "M", "StatusModeCommand"),
	["r?"] = make_mode_config("CONFIRM", "CFM", "StatusModeCommand"),
	["!"] = make_mode_config("SHELL", "SH", "StatusModeCommand"),
	["t"] = make_mode_config("TERMINAL", "TERM", "StatusModeInsert"),
}
local mode_config_map = {}

local function setup_modes_map()
	for key, cfg in pairs(mode_configs) do
		mode_config_map[key] = "%#" .. cfg.highlight_group .. "# " .. cfg.label .. " %*"
		mode_config_map[key .. "-short"] = "%#" .. cfg.highlight_group .. "# " .. cfg.label_short .. " %*"
	end

	mode_config_map["unknown"] = "%#StatusModeNormal# UNKOWN %*"
	mode_config_map["unknown-short"] = "%#StatusModeNormal# UKNW %*"
end

local function get_mode(is_small)
	local current_mode = vim.api.nvim_get_mode().mode
	if is_small then
		return mode_config_map[current_mode .. "-short"] or mode_config_map["unknown-short"]
	else
		return mode_config_map[current_mode] or mode_config_map["unknown"]
	end
end

local function get_git_branch()
	local branch = vim.b.git_branch
	if not branch or branch == "" then
		return ""
	end
	return "%#StatusGeneralSection#  " .. branch .. " %*"
end

local has_devicons, devicons = pcall(require, "nvim-web-devicons")

local function get_file_icon()
	local ft = vim.bo.filetype
	if ft == "" then
		return "📄"
	end

	if has_devicons then
		local filename = vim.fn.expand("%:t")
		local ext = vim.fn.expand("%:e")
		local icon, icon_hl = devicons.get_icon(filename, ext, { default = true })

		if icon then
			return "%#" .. icon_hl .. "#" .. icon .. "%*"
		end
	end
	return "📄"
end

local function get_file_path(is_small)
	local path = vim.fn.expand("%:~:.") -- Relative path or ~/ relative
	if path == "" then
		return "[No Name]"
	end

	if is_small then
		return vim.fn.pathshorten(path)
	end
	return path
end

function create_status_line(winid)
	local is_focused = (winid == vim.api.nvim_get_current_win())
	return vim.api.nvim_win_call(winid, function()
		if not is_focused then
			return ""
		end

		local win_width = vim.api.nvim_win_get_width(winid)
		local is_small = win_width < 100 -- Threshold for compact layout

		local parts = {
			get_mode(is_small),
			get_git_branch(),
			" ",
			get_file_icon(),
			" ",
			get_file_path(is_small),
			" %m", -- Modified flag [+]
			" ",
			"%=", -- Right-alignment separator
			"%#StatusGeneralSection#",
			" %l:%c", -- Line:Column
			"  %p%% ", -- Percentage through file
			"%*",
		}
		return table.concat(parts, "")
	end)
end

local function setup_highlight_groups()
	-- Core Modes
	vim.api.nvim_set_hl(0, "StatusModeNormal", { fg = "#1e1e2e", bg = "#89b4fa", bold = true })
	vim.api.nvim_set_hl(0, "StatusModeInsert", { fg = "#1e1e2e", bg = "#a6e3a1", bold = true })
	vim.api.nvim_set_hl(0, "StatusModeVisual", { fg = "#1e1e2e", bg = "#f9e2af", bold = true })
	vim.api.nvim_set_hl(0, "StatusModeSelect", { fg = "#1e1e2e", bg = "#f2cdcd", bold = true })
	vim.api.nvim_set_hl(0, "StatusModeReplace", { fg = "#1e1e2e", bg = "#f38ba8", bold = true })
	vim.api.nvim_set_hl(0, "StatusModeCommand", { fg = "#1e1e2e", bg = "#fab387", bold = true })
	vim.api.nvim_set_hl(0, "StatusModeTerminal", { fg = "#1e1e2e", bg = "#94e2d5", bold = true })
	vim.api.nvim_set_hl(0, "StatusModePending", { fg = "#1e1e2e", bg = "#b4befe", bold = true })

	-- Non-filename section colors
	vim.api.nvim_set_hl(0, "StatusGeneralSection", { fg = "#8a8a9b", bg = "#363646", bold = false })
end

local function setup_git_branch_autocommand()
	vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "DirChanged" }, {
		group = vim.api.nvim_create_augroup("NativeGitBranch", { clear = true }),
		callback = function()
			vim.system({ "git", "branch", "--show-current" }, { text = true }, function(out)
				if out.code == 0 and out.stdout then
					local branch = out.stdout:gsub("%s+", "")
					vim.schedule(function()
						vim.b.git_branch = branch ~= "" and branch or ""
					end)
				else
					vim.schedule(function()
						vim.b.git_branch = ""
					end)
				end
			end)
		end,
	})
end

function M.setup()
	setup_highlight_groups()
	setup_modes_map()
	setup_git_branch_autocommand()
	vim.opt.statusline = "%!v:lua.create_status_line(g:statusline_winid)"
end

return M
