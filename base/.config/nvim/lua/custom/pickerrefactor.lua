local M = {}

-- DEBUG --
-- To see logs `:vsplit | terminal tail -f debug.log`
local function debug_log(msg)
	-- Appends a line to a 'debug.log' file in your current working directory
	local file = io.open("debug.log", "a")
	if file then
		local msg_str = type(msg) == "string" and msg or vim.inspect(msg)
		file:write(os.date("[%H:%M:%S] ") .. msg_str .. "\n")
		file:close()
	end
end

-- Utilities
local function read_file(filename, callback)
	vim.uv.fs_stat(filename, function(stat_err, stat)
		if stat_err or not stat then
			return callback(nil, "Error stating file: " .. tostring(filename))
		end

		vim.uv.fs_open(filename, "r", 438, function(open_err, fd)
			if open_err or not fd then
				return callback(nil, "Error opening file: " .. tostring(filename))
			end

			vim.uv.fs_read(fd, stat.size, 0, function(read_err, data)
				vim.uv.fs_close(fd)
				if read_err or not data then
					return callback(nil, "Error reading file: " .. tostring(filename))
				end

				local clean_data = string.gsub(data, "\r\n", "\n")
				local lines = vim.split(clean_data, "\n", { trimempty = false })

				callback(lines, nil)
			end)
		end)
	end)
end

---@enum InputPosition
M.InputPosition = {
	NONE = "NONE",
	TOP = "TOP",
	BOTTOM = "BOTTOM",
}

---@enum PreviewPosition
M.PreviewPosition = {
	NONE = "NONE",
	TOP = "TOP",
	BOTTOM = "BOTTOM",
	LEFT = "LEFT",
	RIGHT = "RIGHT",
}

-- Main plugin internal state
local state = {
	namespace = vim.api.nvim_create_namespace("picker"),
	ac_group = vim.api.nvim_create_augroup("PickerInternal", { clear = true }),

	is_open = false,
	pipelines = {}, -- map of piplines
	pipeline = nil, -- currently active pipeline

	items = nil, -- All available items
	results = nil, -- Filtered items to be shown in the results window

	selected_idx = nil, -- Index inside results (1 - based)
	selected_hl_mark = nil,

	-- Seletion callbacks (only one is used depending on the config)
	on_action = nil, -- function(items, indicies, action) - Allows multiple items and custom actions
	on_choice = nil, -- function(item, index) - vim.ui.select "contract"

	format_item = nil, -- function(item): string

	-- Original buffer from which the plugin was launched
	original_buf = nil,
	original_win = nil,

	-- Needed for the UI windows
	input_buf = nil,
	input_win = nil,
	results_buf = nil,
	results_win = nil,
	preview_buf = nil,
	preview_win = nil,

	-- Async support for external tools (e.g. `fzf`)
	uv = vim.uv,
	debounce_timer = vim.uv.new_timer(),
	search_job = nil,
}

---@param input_position InputPosition
---@param preview_position PreviewPosition
local function setup_windows(opts)
	local width_offset, heigth_offset = 0, 1
	local ui = vim.api.nvim_list_uis()[1]
	local width = math.floor((ui.width - width_offset) * opts.width)
	local height = math.floor((ui.height - heigth_offset) * opts.height)
	local row = math.floor((ui.height - height) / 2)
	local col = math.floor((ui.width - width) / 2)

	state.input_buf = vim.api.nvim_create_buf(false, true)
	state.results_buf = vim.api.nvim_create_buf(false, true)
	state.preview_buf = vim.api.nvim_create_buf(false, true)

	-- Disable any completion plugins on the input window
	vim.b[state.input_buf].completion = false

	local border_width = 1

	local results_row, results_col = row, col
	local results_width, results_height = width, height

	local input_row, input_col = nil, nil
	local input_width, input_height = nil, 1 + (2 * border_width)

	local preview_row, preview_col = nil, nil
	local preview_width, preview_height = nil, nil

	if opts.input_position == M.InputPosition.BOTTOM then
		results_row = row
		results_height = height - input_height
		input_row = row + results_height
		input_width = results_width
		input_col = results_col
		input_width = results_width
	elseif opts.input_position == M.InputPosition.TOP then
		results_row = row + input_height
		results_height = height - input_height
		input_row = row
		input_col = results_col
		input_width = results_width
	else
		results_row = row
		results_height = height
	end

	if opts.preview_position == M.PreviewPosition.BOTTOM then
		preview_height = math.floor(results_height / 2)
		results_height = results_height - preview_height
		preview_row = results_row + results_height
		preview_col = results_col
		preview_width = results_width
	elseif opts.preview_position == M.PreviewPosition.TOP then
		preview_height = math.floor(results_height / 2)
		results_height = results_height - preview_height
		preview_row = results_row
		results_row = results_row + preview_height
		preview_col = results_col
		preview_width = results_width
	elseif opts.preview_position == M.PreviewPosition.LEFT then
		preview_width = math.floor(results_width / 2)
		results_width = results_width - preview_width
		preview_col = results_col
		results_col = results_col + results_width
		preview_row = results_row
		preview_height = results_height
	elseif opts.preview_position == M.PreviewPosition.RIGHT then
		preview_width = math.floor(results_width / 2)
		results_width = results_width - preview_width
		preview_col = results_col + results_width
		preview_row = results_row
		preview_height = results_height
	end

	state.results_win = vim.api.nvim_open_win(state.results_buf, false, {
		row = results_row,
		col = results_col,
		width = results_width - (2 * border_width),
		height = results_height - (2 * border_width),
		title = input_row ~= nil and "Results" or state.prompt,
		title_pos = "center",
		relative = "editor",
		style = "minimal",
		border = "rounded",
	})

	if input_row ~= nil then
		state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
			row = input_row,
			col = input_col,
			width = input_width - (2 * border_width),
			height = input_height - (2 * border_width),
			relative = "editor",
			title = state.prompt or "Input",
			title_pos = "center",
			style = "minimal",
			border = "rounded",
		})
		vim.cmd("startinsert")
	end

	if preview_row ~= nil then
		state.preview_win = vim.api.nvim_open_win(state.preview_buf, false, {
			row = preview_row,
			col = preview_col,
			width = preview_width - (2 * border_width),
			height = preview_height - (2 * border_width),
			relative = "editor",
			title = "Preview",
			title_pos = "center",
			style = "minimal",
			border = "rounded",
		})
		vim.wo[state.preview_win].number = true
		vim.wo[state.preview_win].cursorline = true
	end
end

local function close_picker()
	vim.api.nvim_clear_autocmds({ group = state.ac_group })

	state.is_open = false
	state.items = nil
	state.results = nil

	if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
		vim.api.nvim_win_close(state.input_win, true)
	end
	if state.results_win and vim.api.nvim_win_is_valid(state.results_win) then
		vim.api.nvim_win_close(state.results_win, true)
	end

	if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
		vim.api.nvim_win_close(state.preview_win, true)
	end

	state.input_buf = nil
	state.input_win = nil

	state.preview_win = nil
	state.preview_buf = nil

	state.results_buf = nil
	state.results_win = nil

	-- Wipe global bindinding
	vim.keymap.del("n", "<C-i>")
	vim.keymap.del("n", "<C-r>")
	vim.keymap.del("n", "<C-p>")

	-- Clean up original window and set back focus to it
	vim.api.nvim_set_current_win(state.original_win)
	state.original_buf = nil
	state.original_win = nil
end

local function focus_input_line()
	if vim.api.nvim_win_is_valid(state.input_win) then
		vim.api.nvim_set_current_win(state.input_win)
		vim.cmd("startinsert!")
	end
end

local function focus_second_result_line()
	-- We focus on the second line since the first one is always preselected
	if vim.api.nvim_win_is_valid(state.results_win) then
		vim.api.nvim_set_current_win(state.results_win)
		local jump_line = math.min(2, vim.api.nvim_buf_line_count(state.results_buf))
		vim.api.nvim_win_set_cursor(state.results_win, { jump_line, 0 })
		vim.cmd("stopinsert")
	end
end

local function focus_last_result_line()
	if vim.api.nvim_win_is_valid(state.results_win) then
		vim.api.nvim_set_current_win(state.results_win)
		local last_line = vim.api.nvim_buf_line_count(state.results_buf)
		vim.api.nvim_win_set_cursor(state.results_win, { last_line, 0 })
		vim.cmd("stopinsert")
	end
end

local function get_visual_line_range(winnr)
	local v_pos = vim.fn.getpos("v")
	local visual_row = v_pos[2]

	local cursor = vim.api.nvim_win_get_cursor(winnr)
	local cursor_row = cursor[1]

	local start_row = math.min(visual_row, cursor_row)
	local end_row = math.max(visual_row, cursor_row)

	return start_row, end_row
end

local function accept_selection()
	local mode = vim.api.nvim_get_mode().mode
	local visual_mode = mode == "v" or mode == "V" or mode == "\22" -- \22 is visual block mode
	local inside_results_win = state.results_win == vim.api.nvim_get_current_win()

	if visual_mode and inside_results_win then
		local start_row, end_row = get_visual_line_range(state.results_win)
		debug_log(string.format("multi accept_selection: %d - %d", start_row, end_row))

		local items, idxs = {}, {}
		for row = start_row, end_row do
			table.insert(items, state.results[row].original_item or state.results[row])
			table.insert(idxs, state.results[row].key)
		end
		debug_log(vim.inspect(items))
		debug_log(vim.inspect(idxs))
		-- debug_log(vim.inspect({items, idxs}))
	else
		debug_log("single accept_selection")
		local selected = state.results[state.selected_idx]

		if selected and state.on_choice then
			local item = selected.original_item or selected
			local idx = selected.key or state.selected_idx

			debug_log("Chosen: " .. vim.inspect(item) .. ", idx: " .. idx)
			state.on_choice(item, idx)
		end

		vim.cmd("stopinsert")
		close_picker()
	end
end

local function reject_selection()
	if state.on_choice then
		state.on_choice(nil, nil)
	end
	vim.cmd("stopinsert")
	close_picker()
end

local function focus_result_window()
	vim.api.nvim_set_current_win(state.results_win)
end

local function focus_preview_window()
	vim.api.nvim_set_current_win(state.preview_win)
end

local function setup_keybindings()
	local common_opts = { silent = true }

	-- Switching between windows
	vim.keymap.set("n", "j", focus_second_result_line, { buffer = state.input_buf })
	vim.keymap.set("n", "k", focus_last_result_line, { buffer = state.input_buf })

	vim.keymap.set("i", "<C-j>", focus_second_result_line, { buffer = state.input_buf })
	vim.keymap.set("i", "<C-k>", focus_last_result_line, { buffer = state.input_buf })

	vim.keymap.set("n", "i", focus_input_line, { buffer = state.results_buf })
	vim.keymap.set("n", "a", focus_input_line, { buffer = state.results_buf })

	vim.keymap.set("n", "<C-j>", "j", { buffer = state.results_buf })
	vim.keymap.set("n", "<C-k>", "k", { buffer = state.results_buf })

	vim.keymap.set("n", "<C-i>", focus_input_line)
	vim.keymap.set("n", "<C-r>", focus_result_window)
	vim.keymap.set("n", "<C-p>", focus_preview_window)

	-- Selection acceptance
	vim.keymap.set({ "n", "i" }, "<CR>", accept_selection, { buffer = state.input_buf, unpack(common_opts) })
	vim.keymap.set({ "n", "v" }, "<CR>", accept_selection, { buffer = state.results_buf, unpack(common_opts) })

	-- Selection rejection
	vim.keymap.set("n", "<Esc>", reject_selection, { buffer = state.input_buf })
	vim.keymap.set("n", "<Esc>", reject_selection, { buffer = state.results_buf })
	vim.keymap.set("n", "<Esc>", reject_selection, { buffer = state.preview_buf })
	vim.keymap.set("n", "q", reject_selection, { buffer = state.results_buf })
	vim.keymap.set("n", "q", reject_selection, { buffer = state.preview_buf })

	-- Limit input buffer to single line input
	vim.keymap.set("n", "o", "<NOP>", { buffer = state.input_buf })
	vim.keymap.set("n", "O", "<NOP>", { buffer = state.input_buf })
end

local function update_selection(selected_idx)
	if not state.results or selected_idx > #state.results then
		selected_idx = nil
	end

	state.selected_idx = selected_idx

	-- Always clear out previous ext_mark
	if state.selected_hl_mark ~= nil then
		vim.api.nvim_buf_del_extmark(state.results_buf, state.namespace, state.selected_hl_mark)
		state.selected_hl_mark = nil
	end

	if selected_idx then
		if state.results[selected_idx] then
			-- debug_log("setting selected " .. selected_idx)
			state.selected_hl_mark =
				vim.api.nvim_buf_set_extmark(state.results_buf, state.namespace, selected_idx - 1, 0, {
					hl_eol = true,
					hl_group = "CursorLine",
					end_row = selected_idx,
				})
		end
	end
end

local function render_preview()
	if not state.selected_idx then
		return
	end

	local selection = state.results[state.selected_idx]

	if not selection then
		return
	end

	if selection.filename then
		read_file(selection.filename, function(lines)
			vim.schedule(function()
				vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, lines)
				vim.api.nvim_win_set_cursor(state.preview_win, { selection.row or 1, selection.col or 0 })

				local ft = vim.filetype.match({ filename = selection.filename })
				if ft then
					vim.bo[state.preview_buf].filetype = ft
				else
					vim.bo[state.preview_buf].syntax = "off"
				end
			end)
		end)
	elseif selection.bufnr then
		local lines = vim.api.nvim_buf_get_lines(selection.bufnr, 0, -1, false)

		vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, lines)
		vim.api.nvim_win_set_cursor(state.preview_win, { selection.row or 1, selection.col or 0 })

		vim.bo[state.preview_buf].filetype = vim.bo[selection.bufnr].filetype
		vim.bo[state.preview_buf].syntax = vim.bo[selection.bufnr].syntax
	end
end

local function render_results(results)
	vim.schedule(function()
		if state.results_buf and vim.api.nvim_buf_is_valid(state.results_buf) then
			local lines = {}
			local highlights = {}
			for _, result in ipairs(results) do
				local line_text, line_hls = state.format_item(result.original_item)
				table.insert(lines, line_text)
				table.insert(highlights, line_hls)
			end

			vim.api.nvim_buf_set_lines(state.results_buf, 0, -1, false, lines)
			vim.api.nvim_win_set_cursor(state.results_win, { 1, 0 })
			vim.api.nvim_buf_clear_namespace(state.results_buf, state.namespace, 0, -1)

			-- Apply the highlights line by line
			for line_idx, line_hls in ipairs(highlights) do
				for _, hl in ipairs(line_hls) do
					vim.api.nvim_buf_set_extmark(state.results_buf, state.namespace, line_idx - 1, hl.start_col, {
						end_col = hl.end_col,
						hl_group = hl.hl_group,
						hl_mode = "combine",
					})
				end
			end
			update_selection(1) -- Set the first result as selected
			render_preview()
		end
	end)
end

local function run_pipeline()
	local query = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)[1] or ""

	state.pipeline.find(query, function(items)
		state.items = items
		state.pipeline.filter(items, query, function(filtered)
			state.results = filtered
			render_results(filtered, {})
		end)
	end)
end

local function setup_event_listeners()
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = state.input_buf,
		group = state.ac_group,
		callback = function()
			state.debounce_timer:stop()
			state.debounce_timer:start(20, 0, vim.schedule_wrap(run_pipeline))
		end,
	})

	vim.api.nvim_create_autocmd({ "CursorMoved" }, {
		buffer = state.results_buf,
		group = state.ac_group,
		callback = function()
			state.debounce_timer:stop()
			state.debounce_timer:start(
				20,
				0,
				vim.schedule_wrap(function()
					if not vim.api.nvim_win_is_valid(state.results_win) then
						return
					end
					local row = vim.api.nvim_win_get_cursor(state.results_win)[1]
					update_selection(row)
					render_preview()
				end)
			)
		end,
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		group = state.ac_group,
		callback = function()
			if not state.is_open then
				return
			end

			local current_win = vim.api.nvim_get_current_win()

			if current_win == state.results_win then
				-- vim.schedule_wrap(render_preview)
				vim.bo[state.results_buf].modifiable = false
			elseif current_win == state.preview_win then
				vim.bo[state.preview_buf].modifiable = false
			elseif current_win == state.input_win then
				-- Do nothing
			else
				close_picker() -- We are outside all 3 plugin windows, close the picker
			end
		end,
	})

	vim.api.nvim_create_autocmd("WinLeave", {
		group = state.ac_group,
		callback = function()
			if not state.is_open then
				return
			end
			local current_win = vim.api.nvim_get_current_win()
			if current_win == state.results_win then
				vim.bo[state.results_buf].modifiable = true
			elseif current_win == state.preview_win then
				vim.bo[state.preview_buf].modifiable = true
			end
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = state.ac_group,
		callback = function()
			-- This is mostly to handle edge cases where the user closes one of the windows by accident
			local current_win = vim.api.nvim_get_current_win()

			local is_plugin_win = current_win == state.input_win
				or current_win == state.results_win
				or current_win == state.preview_win

			if is_plugin_win and state.is_open then
				reject_selection()
			end
		end,
	})
end

local function filter_fuzzy_match(items, query)
	if query == "" then
		return items
	end

	local filtered = {}

	local targets = {}
	for i, item in ipairs(items) do
		table.insert(targets, {
			text = item.label,
			idx = i,
		})
	end

	debug_log("targets")
	debug_log(targets)
	local matches = vim.fn.matchfuzzypos(targets, query, { key = "text" })
	local matched_targets = matches[1]
	local matched_positions = matches[2]

	for idx, target in ipairs(matched_targets) do
		local original_item = items[target.idx]
		local char_positions = matched_positions[idx]

		local item = vim.tbl_extend("force", {}, original_item)
		item.highlights = {}

		for _, pos in ipairs(char_positions) do
			local byte_start = vim.str_byteindex(item.label, "utf-32", pos)
			local byte_end = vim.str_byteindex(item.label, "utf-32", pos + 1)

			table.insert(item.highlights, {
				start_col = byte_start,
				end_col = byte_end,
			})
		end
		table.insert(filtered, item)
	end

	return filtered
end

local function setup_pipelines()
	state.pipelines = {
		ui_select = {
			prompt = "Choose an option", -- This will usually be overidden by the caller
			find = function(_, callback)
				-- Passthrough because all the items have been given when the select was invoked
				callback(state.items)
			end,
			filter = function(items, query, callback)
				callback(filter_fuzzy_match(items, query))
			end,
			format_item = tostring,
		},
	}
end

local function start_picker(opts)
	if state.is_open then
		return -- Can only have a single instance of picker open
	end

	local pipeline = state.pipelines[opts.mode or "ui_select"]

	if not pipeline then
		error("Unkown pipeline mode: " .. vim.inspect(opts.mode))
	end

	debug_log(vim.inspect(pipeline))

	state.is_open = true
	state.pipeline = pipeline
	state.prompt = opts.prompt or pipeline.prompt
	state.format_item = opts.format_item or pipeline.format_item
	state.on_choice = opts.on_choice or pipeline.on_choice
	state.on_action = opts.on_action or pipeline.on_action

	state.original_buf = vim.api.nvim_get_current_buf()
	state.original_win = vim.api.nvim_get_current_win()

	setup_windows({
		width = opts.width or 0.8,
		height = opts.width or 0.8,
		input_position = opts.input_position or M.InputPosition.TOP,
		preview_position = opts.preview_position or M.PreviewPosition.BOTTOM,
	})
	setup_keybindings()
	setup_event_listeners()
	run_pipeline()
end

function M.ui_select(items, opts, on_choice)
	local opt_format_item = opts.format_item or tostring

	state.items = {}
	for idx, item in ipairs(items) do
		table.insert(state.items, {
			key = idx,
			label = opt_format_item(item),
			original_item = item,
		})
	end

	start_picker({
		mode = "ui_select",
		prompt = "Choose an option",
		on_choice = on_choice,
	})
end

---@param config PickerConfig
function M.setup(config)
	setup_pipelines()
	print("loaded")
end

return M
