local M = {}

-- DEBUG --
-- To see logs: `:vsplit | terminal tail -f debug.log`
local function debug_log(msg)
	local file = io.open("debug.log", "a")
	if file then
		local msg_str = type(msg) == "string" and msg or vim.inspect(msg)
		file:write(os.date("[%H:%M:%S] ") .. msg_str .. "\n")
		file:close()
	end
end

local state = {
	tabline = "", -- Keep the string to be rendered
	buffers = {},
	jump_labels = "fjdkslarueiowty",
	jump_mode = false,
	autogroup = vim.api.nvim_create_augroup("Tabline", { clear = true }),
}

local has_devicons, devicons = pcall(require, "nvim-web-devicons")

local function get_buf_icon(bufnr)
	local ft = vim.bo[bufnr].filetype

	if has_devicons then
		local icon, icon_hl = devicons.get_icon_by_filetype(ft, { default = "true" })
		if icon then
			-- return "%#" .. icon_hl .. "#" .. icon .. "%*"
			return icon
		end
	end

	return "📄"
end

local sep_left = vim.fn.nr2char(0xE0BC)
local sep_right = vim.fn.nr2char(0xE0B8)

local function create_tabline_buffer(buffer)
	local buf_icon = get_buf_icon(buffer.bufnr)
	local buf_name = buffer.name
	local jump_label = buffer.jump_label or " "
	local hl_group = "Default"
	local sel_left_hl_group = "Default"
	local sel_right_hl_group = "Default"
	local modified = ""

	if buffer.bufnr == vim.api.nvim_get_current_buf() then
		hl_group = "TablineActive"
		sel_left_hl_group = "TablineSepActiveLeft"
		sel_right_hl_group = "TablineSepActiveRight"
	else
		hl_group = "TablineInactive"
		sel_left_hl_group = "TablineSepInactiveLeft"
		sel_right_hl_group = "TablineSepInactiveRight"
	end

	if vim.bo[buffer.bufnr].modified then
		modified = " ●"
	end

	local chunks = {
		"%#",
		sel_left_hl_group,
		"#",
		sep_left,
		"%*",
		"%#",
		hl_group,
		"#",
		state.jump_mode and jump_label or "",
		not state.jump_mode and buf_icon or "",
		" ",
		buf_name,
		modified,
		"%*",
		"%#",
		sel_right_hl_group,
		"#",
		sep_right,
		-- "%*",
	}

	return table.concat(chunks)
end

--
-- Refresh the tabline after an event happened
local function create_tab_line()
	local tabline = {}
	for _, buf in ipairs(state.buffers) do
		local is_active = buf.bufnr == vim.api.nvim_get_current_buf()

		table.insert(tabline, create_tabline_buffer(buf))
	end
	state.tabline = table.concat(tabline)
end

-- Returns the cached tabline for speed
function get_cached_tabline()
	return state.tabline
end

local function is_relevant_buffer(bufnr)
	return vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted
end

-- Find relevant buffers
local function get_buffers()
	local buffers = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if is_relevant_buffer(bufnr) then
			table.insert(buffers, bufnr)
		end
	end
	return buffers
end

local function find_buffer(bufnr)
	for idx, buf in ipairs(state.buffers) do
		if buf.bufnr == bufnr then
			return buf, idx
		end
	end
	return nil, nil
end

local function delete_buffer(bufnr)
	for idx, buf in ipairs(state.buffers) do
		if buf.bufnr == bufnr then
			table.remove(state.buffers, idx)
			return buf
		end
	end
end

local function acquire_jump_label()
	local jump_label = state.jump_labels:sub(1, 1)
	state.jump_labels = state.jump_labels:sub(2)
	return jump_label
end

local function release_jump_label(jump_label)
	state.jump_labels = jump_label .. state.jump_labels
end

local function setup_highlight_groups()
	-- local colors = {
	-- 	bg = "#202020",
	-- 	inactive = { fg = "#7982a9", bg = "#292e42" },
	-- 	active = { fg = "#1a1b26", bg = "#7aa2f7" },
	-- }
	local colors = {
		bg = "#363646",
		inactive = { fg = "#7982a9", bg = "#292e42" },
		active = { fg = "#1a1b26", bg = "#7aa2f7" },
	}
	--
	--
	-- local colors = {
	-- 	bg = "#000000",
	-- 	inactive = { fg = "#727169", bg = "#2A2A37" }, -- fujiGray on sumiInk4
	-- 	active = { fg = "#16161D", bg = "#89b4fa" }, -- sumiInk0 on crystalBlue
	-- }

	vim.api.nvim_set_hl(0, "TablineActive", colors.active)
	vim.api.nvim_set_hl(0, "TablineInactive", colors.inactive)
	vim.api.nvim_set_hl(0, "TablineSepActiveLeft", { bg = colors.active.bg, fg = colors.bg })
	vim.api.nvim_set_hl(0, "TablineSepInactiveLeft", { bg = colors.inactive.bg, fg = colors.bg })
	vim.api.nvim_set_hl(0, "TablineSepActiveRight", { fg = colors.active.bg, bg = colors.bg })
	vim.api.nvim_set_hl(0, "TablineSepInactiveRight", { fg = colors.inactive.bg, bg = colors.bg })
end

local function add_buffer(bufnr)
	if find_buffer(bufnr) or not is_relevant_buffer(bufnr) then
		return
	end
	local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
	table.insert(state.buffers, {
		bufnr = bufnr,
		name = filename,
		jump_label = acquire_jump_label(),
	})
end

local function sync_buffers()
	-- drop buffers that are gone or got unlisted
	for i = #state.buffers, 1, -1 do
		local b = state.buffers[i]
		if not vim.api.nvim_buf_is_valid(b.bufnr) or not vim.bo[b.bufnr].buflisted then
			release_jump_label(b.jump_label)
			table.remove(state.buffers, i)
		end
	end
	-- pick up newly listed ones (keeps existing order, appends new)
	for _, bufnr in ipairs(get_buffers()) do
		add_buffer(bufnr)
	end
	create_tab_line()
end

local function setup_auto_commands()
	vim.api.nvim_create_autocmd("BufEnter", {
		group = state.autogroup,
		callback = function(args)
			local bufnr = args.buf
			local existing, _ = find_buffer(bufnr)

			if not existing and is_relevant_buffer(bufnr) then
				add_buffer(bufnr)
			end
			create_tab_line()
		end,
	})

	vim.api.nvim_create_autocmd("BufDelete", {
		group = state.autogroup,
		callback = function(args)
			local bufnr = args.buf
			local deleted = delete_buffer(bufnr)
			if deleted then
				release_jump_label(deleted.jump_label)
			end
			create_tab_line()
		end,
	})

	vim.api.nvim_create_autocmd("BufModifiedSet", {
		group = state.autogroup,
		callback = function()
			create_tab_line()
		end,
	})

	vim.api.nvim_create_autocmd("OptionSet", {
		group = state.autogroup,
		pattern = "buflisted",
		callback = function()
			vim.schedule(sync_buffers)
		end,
	})
end

local function init()
	state.buffers = {}

	local buffers = get_buffers()
	for _, bufnr in ipairs(buffers) do
		add_buffer(bufnr)
	end
end

function M.setup()
	setup_highlight_groups()
	setup_auto_commands()
	init()
	create_tab_line()
	vim.o.tabline = "%!v:lua.get_cached_tabline()"
end

function M.open_next_buffer()
	local curr_bufnr = vim.api.nvim_get_current_buf()
	local _, idx = find_buffer(curr_bufnr)
	if idx then
		local next_idx = idx + 1
		if next_idx > #state.buffers then
			next_idx = 1
		end
		local next_buf = state.buffers[next_idx]
		vim.api.nvim_set_current_buf(next_buf.bufnr)
	end
end

function M.open_prev_buffer()
	local curr_bufnr = vim.api.nvim_get_current_buf()
	local _, idx = find_buffer(curr_bufnr)
	if idx then
		local prev_idx = (idx - 1)
		if prev_idx < 1 then
			prev_idx = #state.buffers
		end
		local prev_buf = state.buffers[prev_idx]
		vim.api.nvim_set_current_buf(prev_buf.bufnr)
	end
end

function M.jump_mode()
	state.jump_mode = not state.jump_mode
	create_tab_line()
end

return M
