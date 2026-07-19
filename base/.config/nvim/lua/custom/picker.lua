local M = {} -- Main module which gets exported
local I = {} -- Table for internal (private) functions which

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

---@alias Picker.InputPosition "none" | "top" | "bottom"
---@alias Picker.PreviewPosition "none" | "top"| "bottom"| "left"| "right"

---@class Picker.Highlight highlight for text (e.g. for item labels)
---@field start_col integer
---@field end_col integer
---@field hl_group string highlight group to use when rendering the label

---@class Picker.Item
---@field id integer index number of the original items passed in, or auto generated
---@field label string label to be show in the results window
---@field label_highligts Picker.Highlight[]
---@field preview_highlights Picker.Highlight[]
---@field original_item any original item object as passed to the picker
---@field bufnr integer? buffer number is the item is inside a buffer
---@field filename string?   filenmae is the item is inside a file
---@field row integer? row/line number if the item is inside a file/buffer and it has a location
---@field col integer? row/line number if the item is inside a file/buffer and it has a location

-- Plugin internal state
---@class Picker.State
---@field is_open boolean
---@field items Picker.Item[]?
---@field results Picker.Item[]?
---
---@field find_items fun (query:string, callback: fun (items: Picker.Item[]))
---@field filter_items fun (items: Picker.Item[], query: string, callback: fun (items: Picker.Item[], done: boolean))
---@field format_item fun (item: Picker.Item): (string, Picker.Highlight[])
---@field format_opts table<string, boolean>
---
--@field on_action (fun (items: any[]?, action: string?): boolean)?
---@field on_action table<string, (fun (items: any[]?): boolean)>?
---@field on_choice (fun(item: any, index: integer?))?
---
---@field original_buf integer | nil
---@field original_win integer | nil
---@field input_buf integer | nil
---@field input_win integer | nil
---@field results_buf integer | nil
---@field results_win integer | nil
---@field review_buf integer | nil
---@field review_win integer | nil
local state = {
	run_count = 0,

	labels_ns = vim.api.nvim_create_namespace("picker_labels"),
	selection_ns = vim.api.nvim_create_namespace("picker_selection"),
	ac_group = vim.api.nvim_create_augroup("PickerInternal", { clear = true }),

	is_open = false,

	items = nil, -- All available items
	results = nil, -- Filtered items to be shown in the results window

	selected_idx = nil, -- Index inside results (1 - based)
	selected_hl_mark = nil,

	-- Specific implementation per picker
	find_items = function() end,
	filter_items = function() end,
	format_item = tostring,
	format_opts = {},

	-- Seletion callbacks (only one is used depending on the config)
	on_action = nil, -- function(items, action) - Allows multiple items and custom actions
	on_choice = nil, -- function(item, index) - vim.ui.select "contract"

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
	shell_cmd_job = nil,
}

function I.setup_windows(opts)
	local width_offset, heigth_offset = 0, 1
	local ui = vim.api.nvim_list_uis()[1]
	local width = math.floor((ui.width - width_offset) * opts.width)
	local height = math.floor((ui.height - heigth_offset) * opts.height)
	local row = math.floor((ui.height - height) / 2)
	local col = math.floor((ui.width - width) / 2)

	state.input_buf = vim.api.nvim_create_buf(false, true)
	state.results_buf = vim.api.nvim_create_buf(false, true)
	state.preview_buf = vim.api.nvim_create_buf(false, true)

	-- Automatically delete these buffers when they are hidden
	vim.bo[state.input_buf].bufhidden = "wipe"
	vim.bo[state.results_buf].bufhidden = "wipe"
	vim.bo[state.preview_buf].bufhidden = "wipe"

	-- Disable any completion plugins on the input window
	vim.b[state.input_buf].completion = false

	local border_width = 1

	local results_row, results_col = row, col
	local results_width, results_height = width, height

	local input_row, input_col = nil, nil
	local input_width, input_height = nil, 1 + (2 * border_width)

	local preview_row, preview_col = nil, nil
	local preview_width, preview_height = nil, nil

	if opts.input_position == "bottom" then
		results_row = row
		results_height = height - input_height
		input_row = row + results_height
		input_width = results_width
		input_col = results_col
		input_width = results_width
	elseif opts.input_position == "top" then
		results_row = row + input_height
		results_height = height - input_height
		input_row = row
		input_col = results_col
		input_width = results_width
	else
		results_row = row
		results_height = height
	end

	if opts.preview_position == "bottom" then
		preview_height = math.floor(results_height / 2)
		results_height = results_height - preview_height
		preview_row = results_row + results_height
		preview_col = results_col
		preview_width = results_width
	elseif opts.preview_position == "top" then
		preview_height = math.floor(results_height / 2)
		results_height = results_height - preview_height
		preview_row = results_row
		results_row = results_row + preview_height
		preview_col = results_col
		preview_width = results_width
	elseif opts.preview_position == "left" then
		preview_width = math.floor(results_width / 2)
		results_width = results_width - preview_width
		preview_col = results_col
		results_col = results_col + results_width
		preview_row = results_row
		preview_height = results_height
	elseif opts.preview_position == "right" then
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

function I.close_picker()
	state.run_count = 0
	state.selected_idx = nil

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

	state.input_buf, state.preview_buf, state.results_buf = nil, nil, nil
	state.input_win, state.preview_win, state.results_win = nil, nil, nil

	-- Wipe global bindinding
	pcall(vim.keymap.del, "n", "<C-i>")
	pcall(vim.keymap.del, "n", "<C-r>")
	pcall(vim.keymap.del, "n", "<C-p>")

	-- Clean up original window and set back focus to it
	if vim.api.nvim_win_is_valid(state.original_win) then
		vim.api.nvim_set_current_win(state.original_win)
	end
	state.original_buf = nil
	state.original_win = nil
end

function I.focus_input_line()
	if vim.api.nvim_win_is_valid(state.input_win) then
		vim.api.nvim_set_current_win(state.input_win)
		vim.cmd("startinsert!")
	end
end

function I.focus_second_result_line()
	-- We focus on the second line since the first one is always preselected
	if vim.api.nvim_win_is_valid(state.results_win) then
		vim.api.nvim_set_current_win(state.results_win)
		local jump_line = math.min(2, vim.api.nvim_buf_line_count(state.results_buf))
		vim.api.nvim_win_set_cursor(state.results_win, { jump_line, 0 })
		vim.cmd("stopinsert")
	end
end

function I.focus_last_result_line()
	if vim.api.nvim_win_is_valid(state.results_win) then
		vim.api.nvim_set_current_win(state.results_win)
		local last_line = vim.api.nvim_buf_line_count(state.results_buf)
		vim.api.nvim_win_set_cursor(state.results_win, { last_line, 0 })
		vim.cmd("stopinsert")
	end
end

function I.get_visual_line_range(winnr)
	local v_pos = vim.fn.getpos("v")
	local visual_row = v_pos[2]

	local cursor = vim.api.nvim_win_get_cursor(winnr)
	local cursor_row = cursor[1]

	local start_row = math.min(visual_row, cursor_row)
	local end_row = math.max(visual_row, cursor_row)

	return start_row, end_row
end

function I.accept_selection(action)
	local mode = vim.api.nvim_get_mode().mode

	local visual_mode = mode == "v" or mode == "V" or mode == "\22" -- \22 is visual block mode
	local inside_results_win = state.results_win == vim.api.nvim_get_current_win()

	local should_close, should_refresh = false, false

	if visual_mode and inside_results_win then
		local start_row, end_row = I.get_visual_line_range(state.results_win)

		local items, idxs = {}, {}
		for row = start_row, end_row do
			table.insert(items, state.results[row])
			table.insert(idxs, state.results[row].id)
		end

		local action_handler = state.on_action[action]

		if action_handler and #items > 0 then
			should_close = action_handler(items)
		end
	else
		local selected = state.results[state.selected_idx]
		local action_handler = state.on_action and state.on_action[action]

		debug_log(state.selected_idx)

		if selected and action_handler then
			local item = selected
			should_refresh = true
			should_close = action_handler({ item })
		elseif selected and state.on_choice then
			local item = selected.original_item
			local idx = selected.id
			state.on_choice(item, idx)
		end
	end

	if should_close then
		vim.cmd("stopinsert")
		I.close_picker()
	elseif should_refresh then
		I.run_search() -- We refresh if any action was made
	end
end

function I.reject_selection()
	if state.on_choice then
		state.on_choice(nil, nil)
		-- elseif state.on_action then
		-- 	state.on_action(nil)
	end
	vim.cmd("stopinsert")
	I.close_picker()
end

function I.focus_result_window()
	vim.api.nvim_set_current_win(state.results_win)
end

function I.focus_preview_window()
	vim.api.nvim_set_current_win(state.preview_win)
end

function I.setup_keybindings()
	local common_opts = { silent = true }

	vim.keymap.set("n", "j", I.focus_second_result_line, { buffer = state.input_buf })
	vim.keymap.set("n", "k", I.focus_last_result_line, { buffer = state.input_buf })

	vim.keymap.set("i", "<C-j>", I.focus_second_result_line, { buffer = state.input_buf })
	vim.keymap.set("i", "<C-k>", I.focus_last_result_line, { buffer = state.input_buf })

	vim.keymap.set("n", "i", I.focus_input_line, { buffer = state.results_buf })
	vim.keymap.set("n", "a", I.focus_input_line, { buffer = state.results_buf })

	vim.keymap.set("n", "<C-j>", "j", { buffer = state.results_buf })
	vim.keymap.set("n", "<C-k>", "k", { buffer = state.results_buf })

	vim.keymap.set("n", "<C-i>", I.focus_input_line)
	vim.keymap.set("n", "<C-r>", I.focus_result_window)
	vim.keymap.set("n", "<C-p>", I.focus_preview_window)

	-- Selection acceptance
	local function bind_accept_selection(modes, key, bufnr)
		vim.keymap.set(modes, key, function()
			I.accept_selection(key)
		end, { buffer = bufnr, unpack(common_opts) })
	end
	bind_accept_selection({ "n", "i" }, "<CR>", state.input_buf)
	bind_accept_selection({ "n", "v" }, "<CR>", state.results_buf)
	bind_accept_selection({ "n", "v" }, "d", state.results_buf)

	-- Selection rejection
	vim.keymap.set("n", "<Esc>", I.reject_selection, { buffer = state.input_buf })
	vim.keymap.set("n", "<Esc>", I.reject_selection, { buffer = state.results_buf })
	vim.keymap.set("n", "<Esc>", I.reject_selection, { buffer = state.preview_buf })
	vim.keymap.set("n", "q", I.reject_selection, { buffer = state.results_buf })
	vim.keymap.set("n", "q", I.reject_selection, { buffer = state.preview_buf })

	-- Limit input buffer to single line input
	vim.keymap.set("n", "o", "<NOP>", { buffer = state.input_buf })
	vim.keymap.set("n", "O", "<NOP>", { buffer = state.input_buf })
end

function I.update_selection(selected_idx)
	if not state.results or selected_idx > #state.results then
		selected_idx = nil
		vim.api.nvim_buf_clear_namespace(state.results_buf, state.selection_ns, 0, -1)
	end

	state.selected_idx = selected_idx

	-- Always clear out previous ext_mark
	if state.selected_hl_mark ~= nil then
		vim.api.nvim_buf_del_extmark(state.results_buf, state.selection_ns, state.selected_hl_mark)
		state.selected_hl_mark = nil
	end

	if selected_idx then
		if state.results[selected_idx] then
			state.selected_hl_mark =
				vim.api.nvim_buf_set_extmark(state.results_buf, state.selection_ns, selected_idx - 1, 0, {
					hl_eol = true,
					hl_group = "CursorLine",
					end_row = selected_idx,
				})
		end
	end
end

function I.render_preview()
	if not state.selected_idx or not state.results[state.selected_idx] then
		return
	end

	local selection = state.results[state.selected_idx]

	if not selection then
		return
	end

	local new_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[new_buf].bufhidden = "wipe"
	vim.keymap.set("n", "<Esc>", I.reject_selection, { buffer = new_buf })
	vim.keymap.set("n", "q", I.reject_selection, { buffer = new_buf })

	if selection.filename then
		I.read_file(selection.filename, function(lines)
			vim.schedule(function()
				vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, lines)

				local ft = vim.filetype.match({ filename = selection.filename })
				if ft then
					vim.bo[new_buf].filetype = ft
					vim.bo[new_buf].syntax = "off"
				else
					vim.bo[new_buf].filetype = ""
					vim.bo[new_buf].syntax = "off"
				end
				vim.bo[new_buf].modifiable = false

				state.preview_buf = new_buf

				vim.api.nvim_win_set_buf(state.preview_win, new_buf)
				vim.api.nvim_win_set_cursor(state.preview_win, { selection.row or 1, selection.col or 0 })
				vim.wo[state.preview_win].number = true
			end)
		end)
	elseif selection.bufnr then
		local lines = vim.api.nvim_buf_get_lines(selection.bufnr, 0, -1, false)

		vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, lines)

		vim.bo[new_buf].filetype = vim.bo[selection.bufnr].filetype
		vim.bo[new_buf].syntax = vim.bo[selection.bufnr].syntax
		vim.bo[new_buf].modifiable = false

		state.preview_buf = new_buf

		vim.api.nvim_win_set_buf(state.preview_win, new_buf)
		vim.api.nvim_win_set_cursor(state.preview_win, { selection.row or 1, selection.col or 0 })
		vim.wo[state.preview_win].number = true
	end
end

local has_devicons, devicons = pcall(require, "nvim-web-devicons")

function I.get_buf_icon(bufnr)
	local ft = vim.bo[bufnr].filetype
	if ft == "" then
		return "📄", "Default"
	end

	if has_devicons then
		local icon, hl_group = devicons.get_icon_by_filetype(ft, { default = "true" })
		return icon, hl_group
	end

	return "📄", "Default"
end

function I.get_file_icon(filepath)
	local has_devicons, devicons = pcall(require, "nvim-web-devicons")
	if not has_devicons then
		return "📄", "Default"
	end

	local filename = vim.fn.fnamemodify(filepath, ":t")
	local extension = vim.fn.fnamemodify(filepath, ":e")
	local icon, hl_group = devicons.get_icon(filename, extension, { default = true })
	return icon, hl_group
end

function I.format_item(item, opts)
	local chunks = {}
	local highlights = {}
	local current_len = 0

	local function append_chunk(text, hl_group)
		table.insert(chunks, text)
		table.insert(highlights, {
			hl_group = hl_group,
			start_col = current_len,
			end_col = current_len + #text,
		})
		current_len = current_len + #text
	end

	if item.filename then
		local icon, icon_hl = I.get_file_icon(item.filename)
		append_chunk(icon .. " ", icon_hl)
	elseif item.bufnr then
		local icon, icon_hl = I.get_buf_icon(item.bufnr)
		append_chunk(icon .. " ", icon_hl)
	end

	local has_chunks = false

	if opts.show_file and item.filename then
		append_chunk(item.filename, "PickerFilename")
		has_chunks = true
	elseif opts.show_file and item.bufnr then
		local full_path = vim.api.nvim_buf_get_name(item.bufnr)
		local filename = vim.fn.fnamemodify(full_path, ":.")
		if filename == "" then
			filename = "[No name]"
		end
		append_chunk(filename, "PickerFilename")
		has_chunks = true
	end

	if opts.show_row and item.row then
		append_chunk(":", "PickerDelimiter")
		append_chunk(tostring(item.row), "Number")
		has_chunks = true
	end

	if opts.show_col and item.col then
		append_chunk(":", "PickerDelimiter")
		append_chunk(tostring(item.col), "PickerNumber")
		has_chunks = true
	end

	if has_chunks then
		append_chunk("| ", "PickerDelimiter")
	end

	append_chunk(item.label, "PickerLabel")

	if item.label_highlights then
		local label_start = current_len - #item.label
		for _, hl in ipairs(item.label_highlights) do
			table.insert(highlights, {
				hl_group = "PickerRegex",
				start_col = label_start + hl.start_col,
				end_col = label_start + hl.end_col,
			})
		end
	end

	return table.concat(chunks, ""), highlights
end

function I.render_results(results)
	vim.schedule(function()
		if state.results_buf and vim.api.nvim_buf_is_valid(state.results_buf) then
			local lines = {}
			local highlights = {}
			for _, result in ipairs(results) do
				local line_text, line_hls = I.format_item(result, state.format_opts or {})
				table.insert(lines, line_text)
				table.insert(highlights, line_hls)
			end

			vim.api.nvim_buf_set_lines(state.results_buf, 0, -1, false, lines)
			vim.api.nvim_win_set_cursor(state.results_win, { 1, 0 })
			vim.api.nvim_buf_clear_namespace(state.results_buf, state.labels_ns, 0, -1)
			--
			-- Apply the highlights line by line
			for line_idx, line_hls in ipairs(highlights) do
				for _, hl in ipairs(line_hls) do
					vim.api.nvim_buf_set_extmark(state.results_buf, state.labels_ns, line_idx - 1, hl.start_col, {
						end_col = hl.end_col,
						hl_group = hl.hl_group,
						hl_mode = "combine",
					})
				end
			end

			vim.api.nvim_win_set_config(state.results_win, {
				title = string.format("Results [%d]", state.results and #state.results or 0),
			})

			I.update_selection(1) -- Set the first result as selected
			I.render_preview()
		end
	end)
end

function I.run_search_query(query, callback)
	state.find_items(query, function(items)
		state.items = items
		state.filter_items(items, query, function(filtered)
			state.results = filtered
			callback()
		end)
	end)
end

function I.run_search()
	state.run_count = state.run_count + 1

	local query = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)[1] or ""

	state.find_items(query, function(items)
		state.items = items
		state.filter_items(items, query, function(filtered)
			state.results = filtered
			I.render_results(filtered)
		end)
	end)
end

function I.setup_event_listeners()
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = state.input_buf,
		group = state.ac_group,
		callback = function()
			state.debounce_timer:stop()
			state.debounce_timer:start(20, 0, vim.schedule_wrap(I.run_search))
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
					I.update_selection(row)
					I.render_preview()
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
				-- vim.bo[state.results_buf].modifiable = false
			elseif current_win == state.preview_win then
				-- vim.bo[state.preview_buf].modifiable = false
			elseif current_win == state.input_win then
				-- Do nothing
			else
				I.close_picker() -- We are outside all 3 plugin windows, close the picker
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
		callback = function(args)
			-- This is mostly to handle edge cases where the user closes one of the windows by accident
			-- local current_win = vim.api.nvim_get_current_win()
			local closed_win = tonumber(args.match)

			local is_plugin_win = closed_win == state.input_win
				or closed_win == state.results_win
				or closed_win == state.preview_win

			if is_plugin_win and state.is_open then
				I.reject_selection()
			end
		end,
	})
end

---@param items Picker.Item[]
---@param query string
function I.filter_fuzzy_match(items, query)
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

	local matches = vim.fn.matchfuzzypos(targets, query, { key = "text" })
	local matched_targets = matches[1]
	local matched_positions = matches[2]

	for idx, target in ipairs(matched_targets) do
		local old_item = items[target.idx]
		local char_positions = matched_positions[idx]

		-- Do a shallow copy of the item so we can modify the label_highlights
		local new_item = vim.tbl_extend("force", {}, old_item)
		new_item.label_highlights = {}

		for _, pos in ipairs(char_positions) do
			local byte_start = vim.str_byteindex(new_item.label, "utf-32", pos)
			local byte_end = vim.str_byteindex(new_item.label, "utf-32", pos + 1)

			table.insert(new_item.label_highlights, {
				start_col = byte_start,
				end_col = byte_end,
			})
		end
		table.insert(filtered, new_item)
	end

	return filtered
end

function I.start_picker(opts)
	if state.is_open then
		return -- Can only have a single instance of picker open
	end

	state.is_open = true
	state.prompt = opts.prompt or "Select options"

	state.find_items = opts.find_items
	state.filter_items = opts.filter_items
	state.format_opts = opts.format_opts

	state.on_choice = opts.on_choice
	state.on_action = opts.on_action

	state.original_buf = vim.api.nvim_get_current_buf()
	state.original_win = vim.api.nvim_get_current_win()

	I.setup_windows({
		width = opts.width or 0.8,
		height = opts.width or 0.8,
		input_position = opts.input_position or "top",
		preview_position = opts.preview_position or "bottom",
	})
	I.setup_keybindings()
	I.setup_event_listeners()
	I.run_search()
end

function M.generic_select(items, opts)
	local format_label = opts.format_label or tostring

	local internal_items = {}
	for idx, item in ipairs(items) do
		table.insert(internal_items, {
			id = idx,
			label = format_label(item),
			original_item = item,
		})
	end

	I.start_picker({
		prompt = opts.prompt or "Choose an option",
		input_position = "top",
		preview_position = "none",
		find_items = function(_, callback)
			callback(internal_items)
		end,
		filter_items = function(filtered, query, callback)
			callback(I.filter_fuzzy_match(filtered, query))
		end,
		on_choice = opts.on_choice,
		on_action = opts.on_action,
	})
end

function M.ui_select(items, opts, on_choice)
	local format_label = opts.format_label or tostring

	local internal_items = {}
	for idx, item in ipairs(items) do
		table.insert(internal_items, {
			id = idx,
			label = format_label(item),
			original_item = item,
		})
	end

	I.start_picker({
		prompt = "Choose an option",
		input_position = "top",
		preview_position = "none",
		find_items = function(_, callback)
			callback(internal_items)
		end,
		filter_items = function(filtered, query, callback)
			callback(I.filter_fuzzy_match(filtered, query))
		end,
		on_choice = on_choice,
	})
end

function I.open_first_item(items)
	if not items or #items == 0 then
		return
	end
	local item = items[1]
	local win = state.original_win or 0

	if item.bufnr then
		vim.api.nvim_win_set_buf(win, item.bufnr)
		vim.api.nvim_win_set_cursor(win, { item.row, item.col })
	elseif item.filename then
		vim.api.nvim_win_call(win, function()
			vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
			vim.api.nvim_win_set_cursor(win, { item.row or 1, item.col or 0 })
		end)
	end
end

function M.find_buffers()
	I.start_picker({
		prompt = "Find Buffers",
		input_position = "top",
		preview_position = "bottom",
		find_items = function(_, callback)
			local listed_bufs = vim.api.nvim_list_bufs() -- Listed (user) buffers avoids including other non-file buffers
			local items = {}
			for _, bufnr in ipairs(listed_bufs) do
				if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted then
					local full_filename = vim.api.nvim_buf_get_name(bufnr)
					local filename = vim.fn.fnamemodify(full_filename, ":.")
					if filename == "" then
						filename = "[No name]"
					end
					local label = string.format("%s [%d]", filename, bufnr)
					table.insert(items, {
						id = bufnr,
						label = label,
						bufnr = bufnr,
						row = 1,
						col = 0,
					})
				end
			end
			callback(items)
		end,
		filter_items = function(filtered, query, callback)
			callback(I.filter_fuzzy_match(filtered, query))
		end,
		on_action = {
			["<CR>"] = function(items)
				I.open_first_item(items)
				return true
			end,
			["d"] = function(items)
				for _, item in ipairs(items) do
					-- We have to create a replacement scratch buffer if we are deleting the last buffer
					local valid_buffers = vim.fn.getbufinfo({ buflisted = 1 })

					if #valid_buffers <= 1 then
						local scratch_buf = vim.api.nvim_create_buf(true, true)

						vim.bo[scratch_buf].bufhidden = "wipe"

						for _, win in ipairs(vim.api.nvim_list_wins()) do
							if vim.api.nvim_win_get_buf(win) == item.bufnr then
								vim.api.nvim_win_set_buf(win, scratch_buf)
							end
						end
					end
					vim.api.nvim_buf_delete(item.bufnr, {})
				end
				return false -- Don't close the picker on deletion of a buffer
			end,
		},
	})
end

function M.find_files()
	I.start_picker({
		prompt = "Find Files",
		input_position = "top",
		preview_position = "bottom",
		find_items = function(query, callback)
			local shell_cmd = "fd --type f --hidden --no-ignore --max-results 1000 --exclude .git"
			if query ~= "" then
				shell_cmd = string.format("%s | fzf -f %s", shell_cmd, vim.fn.shellescape(query))
			end

			I.run_shell_cmd(shell_cmd, function(output)
				local items = {}
				for _, line in ipairs(output) do
					table.insert(items, {
						id = #items,
						label = line,
						filename = line,
						original_item = line,
					})
				end
				callback(items)
			end)
		end,
		filter_items = function(filtered, query, callback)
			-- We still filter these using nvim fuzzy match to get the higlights,
			-- also `fuzzy_highlight_items` must be on the main thread
			vim.schedule(function()
				callback(I.filter_fuzzy_match(filtered, query))
			end)
		end,
		on_action = {
			["<CR>"] = function(items)
				I.open_first_item(items)
				return true
			end,
		},
	})
end

function M.live_grep()
	I.start_picker({
		prompt = "Live Grep",
		input_position = "top",
		preview_position = "bottom",
		find_items = function(query, callback)
			if query == "" then
				I.render_results({})
				return
			end

			local shell_cmd =
				string.format("rg --json --hidden --smart-case %s | head -n 100", vim.fn.shellescape(query))

			I.run_shell_cmd(shell_cmd, function(output)
				local items = {}
				for _, line in ipairs(output) do
					local ok, parsed = pcall(vim.json.decode, line)
					if ok and parsed and parsed.type == "match" then
						local data = parsed.data
						local filename = data.path.text
						local lnum = data.line_number
						local submatch = data.submatches[1]

						if submatch then
							local start_pos = submatch.start
							local match_length = submatch["end"] - submatch.start
							local text = data.lines.text
							if text then
								local label = text:gsub("[\r\n]", " ") -- Strip any new lines
								local highlights = {
									{ start_col = start_pos, end_col = start_pos + match_length },
								}
								table.insert(items, {
									id = #items,
									label = label,
									-- label_highlights = highlights,
									filename = filename,
									row = lnum,
									col = start_pos,
									match_length = match_length,
								})
							end
						end
					end
				end
				callback(items)
			end)
		end,
		filter_items = function(items, _, callback)
			callback(items) -- Passthrough
		end,
		format_opts = { show_file = true, show_row = true, show_col = true },
		on_action = {
			["<CR>"] = function(items)
				I.open_first_item(items)
				return true
			end,
		},
	})
end

function M.find_symbols()
	local lsp_kind_icons = {
		[1] = "󰈔", -- File
		[2] = "", -- Module
		[3] = "󰅪", -- Namespace
		[4] = "📦", -- Package
		[5] = "𝓒", -- Class
		[6] = "󰆧", -- Method
		[7] = "", -- Property
		[8] = "󰜢", -- Field
		[9] = "", -- Constructor
		[10] = "", -- Enum
		[11] = "𝓘", -- Interface
		[12] = "󰊕", -- Function
		[13] = "󰀫", -- Variable
		[14] = "󰏿", -- Constant
		[15] = "󱄽", -- String
		[16] = "󰎠", -- Number
		[17] = "◧", -- Boolean
		[18] = "󰅪", -- Array
		[19] = "󰅩", -- Object
		[20] = "󰌆", -- Key
		[21] = "󰟢", -- Null
		[22] = "", -- EnumMember
		[23] = "󰙅", -- Struct
		[24] = "🗲", -- Event
		[25] = "󰆕", -- Operator
		[26] = "󰅲", -- TypeParameter
	}

	I.start_picker({
		prompt = "Find Symbols",
		on_choice = nil, -- TODO: Fix this
		input_position = "top",
		preview_position = "bottom",
		find_items = function(_, callback)
			-- Use cached items (once per picker launch)
			if state.items ~= nil then
				callback(state.items)
				return
			end

			local bufnr = state.original_buf
			local method = "textDocument/documentSymbol"

			local params = {
				textDocument = {
					uri = vim.uri_from_bufnr(bufnr),
				},
			}

			vim.lsp.buf_request(bufnr, method, params, function(err, result, _, _)
				if err or not result or vim.tbl_isempty(result) then
					print("No symbols found or LSP error occurred.")
					return
				end

				local items = {}
				local symbol_kind_map = vim.lsp.protocol.SymbolKind

				-- Recursive helper to flatten the AST tree and filter functions
				local function process_symbols(symbols, depth)
					for _, symbol in ipairs(symbols) do
						local kind_name = symbol_kind_map[symbol.kind] or "Unknown"
						local icon = lsp_kind_icons[symbol.kind] or "󰓎"
						local indent = string.rep("  ", depth)
						local display_name = string.format("%s [%s %s] %s ", indent, icon, kind_name, symbol.name)

						table.insert(items, {
							id = #items,
							label = display_name,
							bufnr = bufnr,
							row = symbol.range.start.line + 1,
							col = symbol.range.start.character + 1,
						})

						if symbol.children and not vim.tbl_isempty(symbol.children) then
							process_symbols(symbol.children, depth + 1)
						end
					end
				end

				-- Run the processor on the root results
				process_symbols(result, 0)

				callback(items)
			end)
		end,
		filter_items = function(filtered, query, callback)
			callback(I.filter_fuzzy_match(filtered, query))
		end,
		format_opts = { show_file = true, show_row = true, show_col = true },
		on_action = {
			["<CR>"] = function(items)
				I.open_first_item(items)
				return true
			end,
		},
	})
end

function M.find_diagnostics()
	I.start_picker({
		prompt = "Find Diagnostics",
		input_position = "top",
		preview_position = "bottom",
		find_items = function(_, callback)
			local diagnostics = vim.diagnostic.get(nil)
			local items = {}

			local severity_labels = {
				[vim.diagnostic.severity.ERROR] = "󰅚 ERROR",
				[vim.diagnostic.severity.WARN] = "󰀪 WARN",
				[vim.diagnostic.severity.INFO] = "󰋽 INFO",
				[vim.diagnostic.severity.HINT] = "󰌶 HINT",
			}

			for _, diag in ipairs(diagnostics) do
				local lnum = diag.lnum + 1
				local severity = severity_labels[diag.severity] or "DIAG"

				local bufnr, filename = nil, nil
				if vim.api.nvim_buf_is_loaded(diag.bufnr) then
					bufnr = diag.bufnr
				else
					local raw_filename = vim.api.nvim_buf_get_name(diag.bufnr)
					filename = vim.fn.fnamemodify(raw_filename, ":.")
				end

				local label = string.format("[%s] %s", severity, diag.message:gsub("\n", " "))

				table.insert(items, {
					id = #items,
					label = label,
					bufnr = bufnr,
					filename = filename,
					row = lnum,
					col = 0,
				})
			end
			callback(items)
		end,
		filter_items = function(filtered, query, callback)
			callback(I.filter_fuzzy_match(filtered, query))
		end,
		format_opts = { show_file = true, show_row = true, show_col = true },
		on_action = {
			["<CR>"] = function(items)
				debug_log(items)
				I.open_first_item(items)
				return true
			end,
		},
	})
end

-- LSP request pickers
function I.make_lsp_request(method, bufnr, callback)
	local win = state.original_win or 0
	local cursor = vim.api.nvim_win_get_cursor(win)

	local params = {
		textDocument = { uri = vim.uri_from_bufnr(bufnr) },
		position = { line = cursor[1] - 1, character = cursor[2] },
		context = { includeDeclaration = false }, -- Set to false if you only want usages
	}

	vim.lsp.buf_request(bufnr, method, params, function(err, result, _, _)
		debug_log("Found: " .. vim.inspect(result))
		if err or not result or vim.tbl_isempty(result) then
			callback({})
			return
		end

		local raw_items = vim.islist(result) and result or { result }
		local items = {}

		for _, raw in ipairs(raw_items) do
			local target_uri = raw.targetUri or raw.uri
			local target_range = raw.targetSelectionRange or raw.targetRange or raw.range

			if target_uri and target_range then
				local ref_bufnr = vim.uri_to_bufnr(target_uri)
				local start_line = target_range.start.line + 1

				if not vim.api.nvim_buf_is_loaded(ref_bufnr) then
					vim.fn.bufload(ref_bufnr)
				end

				local line_text = vim.api.nvim_buf_get_lines(
					ref_bufnr,
					target_range.start.line,
					target_range.start.line + 1,
					false
				)[1] or ""

				table.insert(items, {
					key = #items,
					label = vim.trim(line_text),
					bufnr = ref_bufnr,
					row = start_line,
					col = target_range.start.character,
					filename = vim.uri_to_fname(target_uri),
					match_start = target_range.start.character + 1,
					match_end = target_range["end"].character + 1,
				})
			end
		end
		callback(items)
	end)
end

function I.start_lsp_picker(method, prompt_title)
	local bufnr = vim.api.nvim_get_current_buf()

	local has_support = false
	local clients = vim.lsp.get_clients({ bufnr = bufnr })

	local capability_map = {
		["textDocument/definition"] = "definitionProvider",
		["textDocument/implementation"] = "implementationProvider",
		["textDocument/declaration"] = "declarationProvider",
		["textDocument/typeDefinition"] = "typeDefinitionProvider",
		["textDocument/references"] = "referencesProvider",
	}
	local provider = capability_map[method]

	for _, client in ipairs(clients) do
		if provider and client.supports_method(method, bufnr) then
			has_support = true
			break
		end
	end

	if not has_support then
		vim.notify(
			string.format("LSP server does not support '%s'", prompt_title),
			vim.log.levels.WARN,
			{ title = "Picker Error" }
		)
		return
	end

	I.make_lsp_request(method, bufnr, function(lsp_items)
		if #lsp_items == 0 then
			vim.notify(string.format("No '%s' found.", method), vim.log.levels.INFO)
			return
		elseif #lsp_items == 1 then
			I.open_first_item(lsp_items)
			return
		end

		I.start_picker({
			prompt = prompt_title,
			input_position = "top",
			preview_position = "bottom",
			find_items = function(_, callback)
				callback(lsp_items)
			end,
			filter_items = function(filtered, query, callback)
				callback(I.filter_fuzzy_match(filtered, query))
			end,
			format_opts = { show_file = true, show_row = true, show_col = true },
			on_action = {
				["<CR>"] = function(items)
					-- Safeguard case: If user hits enter on an empty result set
					if not items or vim.tbl_isempty(items) then
						return true
					end

					I.open_first_item(items)
					return true
				end,
			},
		})
	end)
end

function I.build_lsp_picker(method, prompt_title)
	return function()
		I.start_lsp_picker(method, prompt_title)
	end
end

M.find_definitions = I.build_lsp_picker("textDocument/definition", "Find Definitions")
M.find_implementations = I.build_lsp_picker("textDocument/implementation", "Find Implementations")
M.find_declarations = I.build_lsp_picker("textDocument/declaration", "Find Declarations")
M.find_typedefs = I.build_lsp_picker("textDocument/typeDefinition", "Find Type Definitions")
M.find_references = I.build_lsp_picker("textDocument/references", "Find References")

function I.setup_highlight_groups()
	local higlight_groups = {
		{ name = "PickerFilename", fg = "#98bb6c" },
		{ name = "PickerDelimiter", fg = "#9cabca" },
		{ name = "PickerLabel", fg = "#dcd7ba" },
		{ name = "PickerNumber", fg = "#d27e99" },
		{ name = "PickerRegex", fg = "#ff9e3b" },
	}

	for _, hl in ipairs(higlight_groups) do
		vim.api.nvim_set_hl(0, hl.name, {
			fg = hl.fg,
			bg = "NONE",
			force = true,
		})
	end
end

function M.setup(config)
	I.setup_highlight_groups()
	print("loaded")
end

--- Reads a file asynchronously
---@param filename string
---@param callback fun(lines: string[]?, error: string?)
function I.read_file(filename, callback)
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

--- Runs a shell command asynchronously
---@param cmd string
---@param callback fun(lines: string[])
function I.run_shell_cmd(cmd, callback)
	if state.shell_cmd_job then
		pcall(state.uv.kill, state.shell_cmd_job, 15)
		state.shell_cmd_job = nil
	end

	local stdout = vim.uv.new_pipe(false)
	local output_chunks = {}

	state.shell_cmd_job, _ = vim.uv.spawn("sh", {
		args = { "-c", cmd },
		stdio = { nil, stdout, nil },
	}, function()
		if stdout then
			stdout:read_stop()
			stdout:close()
		end

		local output = table.concat(output_chunks) -- Concat all results into a single string
		local lines = {}
		for line in string.gmatch(output, "[^\r\n]+") do
			table.insert(lines, line)
		end

		if callback then
			callback(lines)
		end
	end)
	if stdout then
		vim.uv.read_start(stdout, function(_, data)
			if data then
				table.insert(output_chunks, data)
			end
		end)
	end
end

return M
