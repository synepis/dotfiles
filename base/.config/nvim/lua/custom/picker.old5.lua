local M = {}

-- DEBUG --
-- To see logs `:vsplit | terminal tail -f debug.log`
local function debug_log(msg)
	-- Appends a line to a 'debug.log' file in your current working directory
	local file = io.open("debug.log", "a")
	if file then
		file:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
		file:close()
	end
end

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

---@enum PickerMode
local PickerMode = {
	BUFFER = "buffer",
	FILE = "file",
	SYMBOL = "symbol",
}

---@enum InputPosition
local InputPosition = {
	NONE = nil,
	TOP = "TOP",
	BOTTOM = "BOTTOM",
}

---@enum PreviewPosition
local PreviewPosition = {
	NONE = nil,
	TOP = "TOP",
	BOTTOM = "BOTTOM",
	LEFT = "LEFT",
	RIGHT = "RIGHT",
}

---@class PickerConfig Main picker configuration table
---@field input_position? InputPosition Default position of the input bar
---@field preview_position? PreviewPosition Default position of the preview
---@field width? number Width as a percentage of the window height in [0..1] range
---@field height? number Height as a percentage of the window height in [0..1] range

---@class Highlight
---@field start_col integer
---@field end_col integer

---@class PickerLabel
---@field text string Label text to show
---@field highlights Highlight[] List of label highlights

---@class PickerOption
---@field key string Unique value which gets returned if the selection is accpted
---@field label PickerLabel Value to be shown in the options pane
---@field filename? string Present if this option is a file
---@field bufnr? integer Present if this option is a buffer
---@field row? integer Row or line number, present if this option is a buffer or a file
---@field col? integer Present if this option is a buffer or a file

local state = {
	namespace = vim.api.nvim_create_namespace("picker"),
	ac_group = vim.api.nvim_create_augroup("PickerInternal", { clear = true }),

	is_open = false,
	mode = nil,
	options = nil, -- All available options
	results = nil, -- Filtered options

	selected_idx = nil, -- Index inside results (1 - based)
	selected_hl_mark = nil,

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

	-- config
	config = nil,

	-- ui_select "contract"
	format_item = nil, --  external function for formatting
	on_choice = nil, -- Callback: function(item, index)
}

-- Utilities
local function read_file(filename, callback)
	vim.uv.fs_stat(filename, function(stat_err, stat)
		if stat_err or not stat then
			vim.schedule(function()
				vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, { "Error stating file" })
			end)
			return
		end

		vim.uv.fs_open(filename, "r", 438, function(open_err, fd)
			if open_err or not fd then
				vim.schedule(function()
					vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, { "Error opening file" })
				end)
				return
			end

			vim.uv.fs_read(fd, stat.size, 0, function(read_err, data)
				vim.uv.fs_close(fd)

				if read_err or not data then
					return
				end

				local clean_data = string.gsub(data, "\r\n", "\n")
				local lines = vim.split(clean_data, "\n", { trimempty = false })
				callback(lines)
			end)
		end)
	end)
end

local function run_shell_cmd(cmd, callback)
	if state.search_job then
		pcall(state.uv.kill, state.search_job, 15)
		state.search_job = nil
	end

	local stdout = state.uv.new_pipe(false)
	local output_chunks = {}

	-- Spawn the shell task on a background worker thread via libuv
	state.search_job, _ = state.uv.spawn("sh", {
		args = { "-c", cmd },
		stdio = { nil, stdout, nil },
	}, function()
		-- debug_log("Starting cmd: " .. cmd)
		-- Process termination callback
		if stdout then
			stdout:read_stop()
			stdout:close()
		end
		state.search_job = nil

		local output = table.concat(output_chunks) -- Concat all results into a single string
		local lines = {}
		for line in string.gmatch(output, "[^\r\n]+") do
			table.insert(lines, line)
		end

		if callback then
			callback(lines)
		end
	end)

	state.uv.read_start(stdout, function(_, data)
		if data then
			table.insert(output_chunks, data)
		end
	end)
end

local function close_picker()
	vim.api.nvim_clear_autocmds({ group = state.ac_group })

	state.is_open = false
	state.mode = nil
	state.options = nil
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

---@param mode PickerMode
---@param input_position InputPosition
---@param preview_position PreviewPosition
local function init_windows(mode, input_position, preview_position)
	local width_offset, heigth_offset = 0, 1
	local ui = vim.api.nvim_list_uis()[1]
	local width = math.floor((ui.width - width_offset) * state.config.width)
	local height = math.floor((ui.height - heigth_offset) * state.config.height)
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

	if input_position == InputPosition.BOTTOM then
		results_row = row
		results_height = height - input_height
		input_row = row + results_height
		input_width = results_width
		input_col = results_col
		input_width = results_width
	elseif input_position == InputPosition.TOP then
		results_row = row + input_height
		results_height = height - input_height
		input_row = row
		input_col = results_col
		input_width = results_width
	else
		results_row = row
		results_height = height
	end

	if preview_position == PreviewPosition.BOTTOM then
		preview_height = math.floor(results_height / 2)
		results_height = results_height - preview_height
		preview_row = results_row + results_height
		preview_col = results_col
		preview_width = results_width
	elseif preview_position == PreviewPosition.TOP then
		preview_height = math.floor(results_height / 2)
		results_height = results_height - preview_height
		preview_row = results_row
		results_row = results_row + preview_height
		preview_col = results_col
		preview_width = results_width
	elseif preview_position == PreviewPosition.LEFT then
		preview_width = math.floor(results_width / 2)
		results_width = results_width - preview_width
		preview_col = results_col
		results_col = results_col + results_width
		preview_row = results_row
		preview_height = results_height
	elseif preview_position == PreviewPosition.RIGHT then
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
		title = "Results",
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
			title = "Find " .. mode,
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

local function get_buf_icon(bufnr)
	local ft = vim.bo[bufnr].filetype
	if ft == "" then
		return "📄", "Default"
	end

	local has_devicons, devicons = pcall(require, "nvim-web-devicons")
	if has_devicons then
		local icon, hl_group = devicons.get_icon_by_filetype(ft, { default = "true" })
		return icon, hl_group
	end

	return "📄", "Default"
end

local function get_file_icon(filepath)
	local has_devicons, devicons = pcall(require, "nvim-web-devicons")
	if not has_devicons then
		return "📄", "Default"
	end

	local filename = vim.fn.fnamemodify(filepath, ":t")
	local extension = vim.fn.fnamemodify(filepath, ":e")
	local icon, hl_group = devicons.get_icon(filename, extension, { default = true })
	return icon, hl_group
end

---Formats a single PickerOption into a string and returns highlight coordinates
---@param option PickerOption
---@return string formatted_line The text to insert into the buffer
---@return table highlights A list of highlight definitions
local function format_option(option, opts)
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

	if option.filename then
		local icon, icon_hl = get_file_icon(option.filename)
		append_chunk(icon .. " ", icon_hl)
	elseif option.bufnr then
		local icon, icon_hl = get_buf_icon(option.bufnr)
		append_chunk(icon .. " ", icon_hl)
	end

	local has_chunks = false

	if opts.show_file and option.filename then
		append_chunk(option.filename, "PickerFilename")
		has_chunks = true
	elseif opts.show_file and option.bufnr then
		local full_path = vim.api.nvim_buf_get_name(option.bufnr)
		local filename = vim.fn.fnamemodify(full_path, ":.")
		if filename == "" then
			filename = "[No name]"
		end
		append_chunk(filename, "PickerFilename")
		has_chunks = true
	end

	if opts.show_row and option.row then
		append_chunk(":", "PickerDelimiter")
		append_chunk(tostring(option.row), "Number")
		has_chunks = true
	end

	if opts.show_col and option.col then
		append_chunk(":", "PickerDelimiter")
		append_chunk(tostring(option.col), "PickerNumber")
		has_chunks = true
	end

	if has_chunks then
		append_chunk("| ", "PickerDelimiter")
	end

	append_chunk(option.label.text, "PickerLabel")

	if option.label.highlights then
		local label_start = current_len - #option.label.text
		for _, hl in ipairs(option.label.highlights) do
			table.insert(highlights, {
				hl_group = "PickerRegex",
				start_col = label_start + hl.start_col,
				end_col = label_start + hl.end_col,
			})
		end
	end

	return table.concat(chunks, ""), highlights
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
		vim.api.nvim_buf_set_lines(state.preview_scratch_buf, 0, -1, false, {})
		return
	end

	if selection.filename then
		read_file(selection.filename, function(lines)
			vim.schedule(function()
				vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, lines)
				vim.api.nvim_win_set_cursor(state.preview_win, { selection.row or 1, selection.col or 0 })

				-- Apply syntax highlighting
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

local function render_results(results, opts)
	vim.schedule(function()
		if state.results_buf and vim.api.nvim_buf_is_valid(state.results_buf) then
			local lines = {}
			local highlights = {}
			for _, result in ipairs(results) do
				local line_text, line_hls = format_option(result, opts)
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

local function filter_options(query)
	local filtered = {}

	if query ~= "" then
		local targets = {}
		for i, opt in ipairs(state.options) do
			table.insert(targets, {
				text = opt.label.text,
				idx = i,
			})
		end

		local matches = vim.fn.matchfuzzypos(targets, query, { key = "text" })
		local matched_targets = matches[1]
		local matched_positions = matches[2]

		for idx, target in ipairs(matched_targets) do
			local original_opt = state.options[target.idx]
			local char_positions = matched_positions[idx]

			local opt = vim.tbl_extend("force", {}, original_opt)
			opt.label = vim.tbl_extend("force", {}, original_opt.label)
			opt.label.highlights = {}

			for _, pos in ipairs(char_positions) do
				local byte_start = vim.str_byteindex(opt.label.text, "utf-32", pos)
				local byte_end = vim.str_byteindex(opt.label.text, "utf-32", pos + 1)

				table.insert(opt.label.highlights, {
					start_col = byte_start,
					end_col = byte_end,
				})
			end
			table.insert(filtered, opt)
		end
	else
		filtered = state.options
	end

	return filtered
end

local function fuzzy_highlight_options(query)
	local highlighted = { unpack(state.options) } -- Shallow copy

	if query ~= "" then
		local targets = {}
		for i, opt in ipairs(state.options) do
			table.insert(targets, {
				text = opt.label.text,
				idx = i,
			})
		end

		local matches = vim.fn.matchfuzzypos(targets, query, { key = "text" })
		local matched_targets = matches[1]
		local matched_positions = matches[2]

		for idx, target in ipairs(matched_targets) do
			local original_opt = state.options[target.idx]
			local char_positions = matched_positions[idx]

			local opt = vim.tbl_extend("force", {}, original_opt)
			opt.label = vim.tbl_extend("force", {}, original_opt.label)
			opt.label.highlights = {}

			for _, pos in ipairs(char_positions) do
				local byte_start = vim.str_byteindex(opt.label.text, "utf-32", pos)
				local byte_end = vim.str_byteindex(opt.label.text, "utf-32", pos + 1)

				table.insert(opt.label.highlights, {
					start_col = byte_start,
					end_col = byte_end,
				})
			end
			highlighted[target.idx] = opt
		end
	else
		highlighted = state.options
	end

	return highlighted
end

---@class PickerPipeline
---@field find function  -- Finds the potential options
---@field filter function  -- Filter the found options
---@field render function  -- Render the resutls (filtered options)

---@type table<string, PickerPipeline>
local pipelines = {
	ui_select = {
		find = function() end,
		filter = function() end,
		render = function() end,
	},
	buffers = {
		find = function(_, callback)
			local listed_bufs = vim.api.nvim_list_bufs() -- Listed (user) buffers avoids including other non-file buffers
			local options = {}
			for _, bufnr in ipairs(listed_bufs) do
				if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted then
					local full_filename = vim.api.nvim_buf_get_name(bufnr)
					local filename = vim.fn.fnamemodify(full_filename, ":.")
					if filename == "" then
						filename = "[No name]"
					end
					local label = string.format("%s [%d]", filename, bufnr)
					table.insert(options, {
						key = bufnr,
						label = { text = label },
						bufnr = bufnr,
						row = 1,
						col = 0,
					})
				end
			end
			callback(options)
		end,
		filter = function(_, query, callback)
			callback(filter_options(query))
		end,
		render = function(filtered, query)
			local results_opts = {
				show_file = false,
				show_col = false,
				show_row = false,
			}
			render_results(filtered, results_opts)
		end,
	},
	diagnostics = {
		find = function(_, callback)
			local diagnostics = vim.diagnostic.get(nil)
			local options = {}

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

				table.insert(options, {
					key = #options,
					label = { text = label },
					bufnr = bufnr,
					filename = filename,
					row = lnum,
					col = 0,
				})
			end
			callback(options)
		end,
		filter = function(_, query, callback)
			callback(filter_options(query))
		end,
		render = function(filtered, query)
			local results_opts = {
				show_file = true,
				show_col = true,
				show_row = true,
			}
			render_results(filtered, results_opts)
		end,
	},
	symbols = {
		find = function(_query, callback)
			-- Use cached options (once per picker launch)
			if state.options ~= nil then
				callback(state.options)
				return
			end

			local bufnr = state.original_buf
			local method = "textDocument/documentSymbol"

			-- Prepare the parameters using the target buffer's URI
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

				local options = {}
				local symbol_kind_map = vim.lsp.protocol.SymbolKind

				-- Recursive helper to flatten the AST tree and filter functions
				local function process_symbols(symbols, depth)
					for _, symbol in ipairs(symbols) do
						local kind_name = symbol_kind_map[symbol.kind] or "Unknown"
						local icon = lsp_kind_icons[symbol.kind] or "󰓎"
						local indent = string.rep("  ", depth)
						local display_name = string.format("%s [%s %s] %s ", indent, icon, kind_name, symbol.name)

						table.insert(options, {
							key = #options,
							label = { text = display_name },
							bufnr = bufnr,
							row = symbol.range.start.line + 1,
							col = symbol.range.start.character + 1,
						})

						-- Language servers often nest local functions or methods inside
						-- parent symbols, so we always check children recursively
						if symbol.children and not vim.tbl_isempty(symbol.children) then
							process_symbols(symbol.children, depth + 1)
						end
					end
				end

				-- Run the processor on the root results
				process_symbols(result, 0)

				callback(options)
			end)
		end,
		filter = function(_, query, callback)
			local filtered = filter_options(query)
			callback(filtered)
		end,
		render = function(filtered)
			local results_opts = {
				show_file = true,
				show_col = true,
				show_row = true,
			}
			render_results(filtered, results_opts)
		end,
	},
	references = {
		find = function(_, callback)
			-- Use cached options (once per picker launch)
			if state.options ~= nil then
				callback(state.options)
				return
			end

			local bufnr = state.original_buf
			local win = state.original_win or 0
			local method = "textDocument/references"
			local cursor = vim.api.nvim_win_get_cursor(win)

			local params = {
				textDocument = {
					uri = vim.uri_from_bufnr(bufnr),
				},
				position = {
					line = cursor[1] - 1,
					character = cursor[2],
				},
				context = {
					includeDeclaration = true, -- Set to false if you only want usages
				},
			}
			vim.lsp.buf_request(bufnr, method, params, function(err, result, _, _)
				if err or not result or vim.tbl_isempty(result) then
					print("No references found or LSP error occurred.")
					return
				end

				local options = {}

				for _, ref in ipairs(result) do
					local ref_bufnr = vim.uri_to_bufnr(ref.uri)
					local start_line = ref.range.start.line + 1

					if not vim.api.nvim_buf_is_loaded(ref_bufnr) then
						vim.fn.bufload(ref_bufnr)
					end
					local line_text = vim.api.nvim_buf_get_lines(
						ref_bufnr,
						ref.range.start.line,
						ref.range.start.line + 1,
						false
					)[1] or ""

					line_text = vim.trim(line_text)

					local display_name = string.format("%s", line_text)

					table.insert(options, {
						key = #options,
						label = { text = display_name },
						bufnr = ref_bufnr,
						row = start_line,
						col = ref.range.start.character + 1,
						-- Passing along extra metadata allows custom formatting later!
						filename = vim.uri_to_fname(ref.uri),
						match_start = ref.range.start.character + 1,
						match_end = ref.range["end"].character + 1,
					})
				end

				state.options = options
				callback(options)
			end)
		end,
		filter = function(_, query, callback)
			local filtered = filter_options(query)
			callback(filtered)
		end,
		render = function(filtered)
			local results_opts = {
				show_file = true,
				show_col = true,
				show_row = true,
			}
			render_results(filtered, results_opts)
		end,
	},
	files = {
		find = function(query, callback)
			local shell_cmd = "fd --type f --hidden --no-ignore --max-results 1000 --exclude .git"
			if query ~= "" then
				shell_cmd = string.format("%s | fzf -f %s", shell_cmd, vim.fn.shellescape(query))
			end

			run_shell_cmd(shell_cmd, function(output)
				local options = {}
				for _, line in ipairs(output) do
					table.insert(options, {
						key = #options,
						label = { text = line },
						filename = line,
					})
				end
				callback(options)
			end)
		end,
		filter = function(_, query, callback)
			-- We still filter these using nvim fuzzy match to get the higlights,
			-- also `fuzzy_highlight_options` must be on the main thread
			vim.schedule(function()
				callback(fuzzy_highlight_options(query))
			end)
		end,
		render = function(filtered)
			local ui_opts = { show_file = false, show_row = false, show_col = false }
			render_results(filtered, ui_opts)
		end,
	},
	live_grep = {
		find = function(query, callback)
			if query == "" then
				render_results({}, {})
				return
			end

			local shell_cmd =
				string.format("rg --json --hidden --smart-case %s | head -n 100", vim.fn.shellescape(query))

			run_shell_cmd(shell_cmd, function(output)
				local options = {}
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
							local label = {
								text = text:gsub("[\r\n]", " "), -- Strip any new lines
								highlights = {
									{ start_col = start_pos, end_col = start_pos + match_length },
								},
							}
							table.insert(options, {
								key = #options,
								label = label,
								filename = filename,
								row = lnum,
								col = start_pos,
								match_length = match_length, -- Store it for your highlighter!
							})
						end
					end
				end
				callback(options)
			end)
		end,
		filter = function(options, _, callback)
			callback(options) -- Passthrough
		end,
		render = function(filtered)
			local ui_opts = { show_file = true, show_row = true, show_col = true }
			render_results(filtered, ui_opts)
		end,
	},
}

local function run_search()
	local query = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)[1] or ""
	local pipeline = pipelines[state.mode or "buffers"]

	if not pipeline then
		error("Unkown pipeline mode: " .. state.mode)
	end

	pipeline.find(query, function(options)
		state.options = options
		pipeline.filter(options, query, function(filtered)
			state.results = filtered
			pipeline.render(filtered, query)
		end)
	end)
end

local function focus_input_line()
	if vim.api.nvim_win_is_valid(state.input_win) then
		vim.api.nvim_set_current_win(state.input_win)
		vim.cmd("startinsert!") -- '!' places cursor at the end of the line
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

local function accept_selection()
	debug_log("accept_selection")
	local selected = state.results[state.selected_idx]

	if selected and selected.filename then
		vim.cmd("stopinsert")
		vim.api.nvim_win_call(state.original_win, function()
			vim.cmd("edit " .. vim.fn.fnameescape(selected.filename))
			vim.api.nvim_win_set_cursor(state.original_win, { selected.row or 1, selected.col or 0 })
		end)
	elseif selected and selected.bufnr then
		vim.cmd("stopinsert")
		vim.api.nvim_win_set_buf(state.original_win, selected.bufnr)
		vim.api.nvim_win_set_cursor(state.original_win, { selected.row, selected.col })
	end

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

	-- Exiting the picker
	vim.keymap.set("n", "<Esc>", close_picker, { buffer = state.input_buf })
	vim.keymap.set("n", "<Esc>", close_picker, { buffer = state.results_buf })
	vim.keymap.set("n", "<Esc>", close_picker, { buffer = state.preview_buf })
	vim.keymap.set("n", "q", close_picker, { buffer = state.results_buf })
	vim.keymap.set("n", "q", close_picker, { buffer = state.preview_buf })

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
	vim.keymap.set("n", "<CR>", accept_selection, { buffer = state.results_buf, unpack(common_opts) })

	-- Limit input buffer to single line input
	vim.keymap.set("n", "o", "<NOP>", { buffer = state.input_buf })
	vim.keymap.set("n", "O", "<NOP>", { buffer = state.input_buf })
end

local function setup_event_listeners()
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = state.input_buf,
		group = state.ac_group,
		callback = function()
			state.debounce_timer:stop()
			state.debounce_timer:start(20, 0, vim.schedule_wrap(run_search))
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
				vim.schedule_wrap(render_preview)
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
			-- If any window is closed by the user, close the entire picker
			local current_win = vim.api.nvim_get_current_win()

			local is_plugin_win = current_win == state.input_win
				or current_win == state.results_win
				or current_win == state.preview_win

			if is_plugin_win and state.is_open then
				close_picker()
			end
		end,
	})
end

local function setup_highlight_groups()
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

function M.ui_select(items, opts, on_choice)
	state.prompt = opts.prompt or "Choose one of the following:"
	state.options = items
	state.on_choice = on_choice

	state.mode = "ui_select"
	state.options = items
end

function M.show_select(opts)
	if state.is_open then
		return -- Can only have a single instance of picker open
	end

	state.is_open = true
	state.mode = opts.mode
	state.original_buf = vim.api.nvim_get_current_buf()
	state.original_win = vim.api.nvim_get_current_win()

	init_windows(opts.mode, InputPosition.TOP, PreviewPosition.BOTTOM)
	setup_keybindings()
	setup_event_listeners()
	run_search()
end

---@param config PickerConfig
function M.setup(config)
	setup_highlight_groups()
	state.config = {
		input_position = config.input_position or "TOP",
		preview_position = config.preview_position or "RIGHT",
		width = config.width or 0.8,
		height = config.height or 0.8,
	}
end

return M
