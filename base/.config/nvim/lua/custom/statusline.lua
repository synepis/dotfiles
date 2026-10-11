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

	mode_config_map["unknown"] = "%#StatusModeNormal# UNKNOWN %*"
	mode_config_map["unknown-short"] = "%#StatusModeNormal# UNKN %*"
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
	return "%#StatusGeneralSection#  " .. branch .. " %*"
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

---------------------------------------------------------------------------
-- Cached LSP / diagnostics state
--
-- Everything below is updated from autocommands. The statusline itself only
-- reads these tables, so redraws never query LSP or diagnostics directly.
---------------------------------------------------------------------------

local severity = vim.diagnostic.severity

-- { severity, highlight group, icon }
local diag_kinds = {
	{ severity.ERROR, "StatusDiagError", "󰅚" },
	{ severity.WARN, "StatusDiagWarn", "󰀪" },
	{ severity.INFO, "StatusDiagInfo", "󰋽" },
	{ severity.HINT, "StatusDiagHint", "󰌶" },
}

local cache = {
	diag_buf = {}, -- bufnr -> pre-rendered string
	lsp = {}, -- bufnr -> { names = "lua_ls,stylua", ids = { [id] = true } }
	busy = {}, -- client_id -> true while an LSP progress task is running
}

local function render_counts(counts)
	local out = {}
	for _, kind in ipairs(diag_kinds) do
		local n = counts[kind[1]]
		if n and n > 0 then
			table.insert(out, "%#" .. kind[2] .. "#" .. kind[3] .. n .. " ")
		end
	end
	if #out == 0 then
		return ""
	else
		table.insert(out, 1, "%#StatusDiagError# %*") -- Add space infront for a better look
	end
	return table.concat(out) .. "%*"
end

-- Coalesce many events (DiagnosticChanged / LspProgress can fire in bursts)
-- into a single statusline redraw per event-loop tick.
local redraw_pending = false

local function request_redraw()
	if redraw_pending then
		return
	end
	redraw_pending = true
	vim.schedule(function()
		vim.cmd.redrawstatus()
		redraw_pending = false
	end)
end

local function update_diagnostics(bufnr)
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		cache.diag_buf[bufnr] = render_counts(vim.diagnostic.count(bufnr))
	end
	request_redraw()
end

local function update_lsp_clients(bufnr, detaching_id)
	local names, ids = {}, {}
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		-- During LspDetach the client is still listed, so skip it explicitly.
		if client.id ~= detaching_id then
			table.insert(names, client.name)
			ids[client.id] = true
		end
	end
	cache.lsp[bufnr] = #names > 0 and { names = table.concat(names, ","), ids = ids } or nil
	request_redraw()
end

local function get_diagnostics(bufnr)
	return cache.diag_buf[bufnr] or ""
end

local function get_lsp_status(bufnr, is_small)
	local entry = cache.lsp[bufnr]
	if not entry then
		return ""
	end

	local busy = false
	for id in pairs(entry.ids) do
		if cache.busy[id] then
			busy = true
			break
		end
	end

	local icon = busy and "󰔟 " or " "
	if is_small then
		return "%#StatusGeneralSection# " .. icon .. "%*"
	end
	return "%#StatusGeneralSection# " .. icon .. entry.names .. " %*"
end

local function setup_lsp_autocommands()
	local group = vim.api.nvim_create_augroup("NativeStatusLsp", { clear = true })

	vim.api.nvim_create_autocmd("DiagnosticChanged", {
		group = group,
		callback = function(args)
			update_diagnostics(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = group,
		callback = function(args)
			update_lsp_clients(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("LspDetach", {
		group = group,
		callback = function(args)
			local id = args.data and args.data.client_id
			if id then
				cache.busy[id] = nil
			end
			update_lsp_clients(args.buf, id)
		end,
	})

	-- Neovim 0.10+: fires on $/progress notifications (indexing, loading workspace, ...)
	vim.api.nvim_create_autocmd("LspProgress", {
		group = group,
		callback = function(args)
			local data = args.data
			local value = data and data.params and data.params.value
			if not (data and data.client_id and type(value) == "table") then
				return
			end
			if value.kind == "end" then
				cache.busy[data.client_id] = nil
			else
				cache.busy[data.client_id] = true
			end
			request_redraw()
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(args)
			cache.diag_buf[args.buf] = nil
			cache.lsp[args.buf] = nil
		end,
	})
end

---------------------------------------------------------------------------

-- Global function to be called by vim.opt.statusline
_G.create_status_line = function(winid)
	local is_focused = (winid == vim.api.nvim_get_current_win())
	return vim.api.nvim_win_call(winid, function()
		if not is_focused then
			return ""
		end

		local bufnr = vim.api.nvim_get_current_buf()
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
			get_diagnostics(bufnr),
			get_lsp_status(bufnr, is_small),
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

	-- Diagnostics (same bg as the general section so they read as one block)
	vim.api.nvim_set_hl(0, "StatusDiagError", { fg = "#f38ba8", bg = "#363646" })
	vim.api.nvim_set_hl(0, "StatusDiagWarn", { fg = "#f9e2af", bg = "#363646" })
	vim.api.nvim_set_hl(0, "StatusDiagInfo", { fg = "#89dceb", bg = "#363646" })
	vim.api.nvim_set_hl(0, "StatusDiagHint", { fg = "#b4befe", bg = "#363646" })
end

local function setup_git_branch_autocommand()
	vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "DirChanged" }, {
		group = vim.api.nvim_create_augroup("NativeGitBranch", { clear = true }),
		callback = function(args)
			-- Capture the buffer now: by the time git returns, the user may be in another buffer.
			local bufnr = args.buf
			vim.system({ "git", "branch", "--show-current" }, { text = true }, function(out)
				local branch = (out.code == 0 and out.stdout) and out.stdout:gsub("%s+", "") or ""
				vim.schedule(function()
					if vim.api.nvim_buf_is_valid(bufnr) then
						vim.b[bufnr].git_branch = branch
					end
				end)
			end)
		end,
	})
end

function M.setup()
	setup_highlight_groups()
	setup_modes_map()
	setup_git_branch_autocommand()
	setup_lsp_autocommands()
	vim.opt.statusline = "%!v:lua.create_status_line(g:statusline_winid)"
end

return M
