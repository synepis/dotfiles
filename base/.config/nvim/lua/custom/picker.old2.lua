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

-- Async
local M = {}

-- 1. The Async Wrapper: Runs a function inside a coroutine
function M.async(fn)
	return function(...)
		local co = coroutine.create(fn)
		local function next_step(...)
			local success, result = coroutine.resume(co, ...)
			if not success then
				error(debug.traceback(co, result))
			end
		end
		next_step(...)
	end
end

-- 2. The Await Wrapper: Converts a callback-based function into a yielding one
function M.await(async_fn)
	return function(...)
		local co = coroutine.running()
		assert(co, "M.await must be called inside an M.async function")

		-- Inject our own callback into the arguments that resumes the coroutine
		local args = { ... }
		table.insert(args, function(...)
			coroutine.resume(co, ...)
		end)

		async_fn(unpack(args))
		return coroutine.yield()
	end
end

_G.AsyncUtil = M -- Make it global so we can test it easily

-- Wrap Neovim's callback-based timer
local sleep = AsyncUtil.await(function (ms, callback)
	vim.defer_fn(callback, ms)
end)

-- Define our async block
local run_test = AsyncUtil.async(function()
	debug_log("Step 1: Starting...")

	sleep(2000) -- Pauses execution for 2 seconds, but Neovim stays responsive!

	debug_log("Step 2: 2 seconds passed!")

	sleep(1000)

	debug_log("Step 3: Done!")
end)

-- Execute it
run_test()

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
-- local PickerLabel = {}
--
-- PickerLabel.__index = PickerLabel
--
-- function PickerLabel.new(text, highlights)
-- 	local self = setmetatable({}, PickerLabel)
-- 	self.text = text
-- 	self.highlights = highlights
-- 	return self
-- end

---@class PickerOption
---@field key string Unique value which gets returned if the selection is accpted
---@field label PickerLabel Value to be shown in the options pane
---@field filename? string Present if this option is a file
---@field bufnr? integer Present if this option is a buffer
---@field row? integer Row or line number, present if this option is a buffer or a file
---@field col? integer Present if this option is a buffer or a file

local state = {
	mode = nil,
	options = nil, -- All available options
	results = nil, -- Filtered options

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

	-- Namespace for highlights and extmarks
	namespace = vim.api.nvim_create_namespace("picker"),
	first_option_ext_mark = nil,

	-- Async support for external tools (e.g. `fzf`)
	uv = vim.uv,
	debounce_timer = vim.uv.new_timer(),
	search_job = nil,

	-- config
	config = nil,
}

local function close_picker()
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
	state.original_win, state.input_win, state.results_win, state.preview_win = nil, nil, nil, nil
	state.original_buf, state.input_buf, state.results_buf, state.preview_buf = nil, nil, nil, nil
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
	end

	-- Keybindings and events
	vim.keymap.set("n", "<Esc>", close_picker, { buffer = state.input_buf })
	vim.keymap.set("n", "<Esc>", close_picker, { buffer = state.results_buf })
	vim.keymap.set("n", "<Esc>", close_picker, { buffer = state.preview_buf })
	vim.keymap.set("n", "q", close_picker, { buffer = state.results_buf })
end

local function get_buffer_options(callback)
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
				row = 0,
				col = 0,
			})
		end
	end
	if callback then
		callback(options)
	end
end

local function get_diagnostic_options(callback)
	local diagnostics = vim.diagnostic.get(nil)
	local options = {}

	local severity_labels = {
		[vim.diagnostic.severity.ERROR] = "󰅚 ERROR",
		[vim.diagnostic.severity.WARN] = "󰀪 WARN",
		[vim.diagnostic.severity.INFO] = "󰋽 INFO",
		[vim.diagnostic.severity.HINT] = "󰌶 HINT",
	}

	for _, diag in ipairs(diagnostics) do
		-- local filename = vim.api.nvim_buf_get_name(diag.bufnr)
		-- local relative_file = vim.fn.fnamemodify(filename, ":.")
		local lnum = diag.lnum + 1
		local severity = severity_labels[diag.severity] or "DIAG"
		local label = string.format("[%s] %s", severity, diag.message:gsub("\n", " "))
		table.insert(options, {
			key = #options,
			label = { text = label },
			bufnr = diag.bufnr,
			row = lnum,
			col = 0,
		})
	end
	if callback then
		callback(options)
	end
end

local function get_document_symbols(callback)
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

	vim.lsp.buf_request(bufnr, method, params, function(err, result, ctx, config)
		if err or not result or vim.tbl_isempty(result) then
			print("No symbols found or LSP error occurred.")
			return
		end

		local options = {}
		local symbol_kind_map = vim.lsp.protocol.SymbolKind

		-- Recursive helper to flatten the AST tree and filter functions
		local function process_symbols(symbols, container_name)
			for _, symbol in ipairs(symbols) do
				local kind_name = symbol_kind_map[symbol.kind] or "Unknown"

				-- Only care about Functions and Methods (functions inside classes/tables)
				if kind_name == "Function" or kind_name == "Method" then
					local display_name = container_name and (container_name .. " > " .. symbol.name) or symbol.name
					table.insert(options, {
						key = #options,
						label = { text = display_name },
						bufnr = bufnr,
						row = symbol.range.start.line + 1,
						col = symbol.range.start.character + 1,
					})
				end

				-- Language servers often nest local functions or methods inside
				-- parent symbols, so we always check children recursively
				if symbol.children and not vim.tbl_isempty(symbol.children) then
					process_symbols(symbol.children, symbol.name)
				end
			end
		end

		-- Run the processor on the root results
		process_symbols(result)

		if callback then
			callback(options)
		end
	end)
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

	if opts.show_file and option.filename then
		append_chunk(option.filename, "String")
	elseif opts.show_file and option.bufnr then
		local full_path = vim.api.nvim_buf_get_name(option.bufnr)
		local filename = vim.fn.fnamemodify(full_path, ":.")
		if filename == "" then
			filename = "[No name]"
		end
		append_chunk(filename, "String")
	end

	if opts.show_row and option.row then
		append_chunk(":", "Delimiter")
		append_chunk(tostring(option.row), "Number")
	end

	if opts.show_col and option.col then
		append_chunk(":", "Delimiter")
		append_chunk(tostring(option.col), "Number")
	end

	if #chunks > 0 then
		append_chunk(" | ", "Delimiter")
	end

	append_chunk(option.label.text, "Normal")

	if option.label.highlights then
		local label_start = current_len - #option.label.text
		for _, hl in ipairs(option.label.highlights) do
			table.insert(highlights, {
				hl_group = "WarningMsg",
				start_col = label_start + hl.start_col,
				end_col = label_start + hl.end_col,
			})
		end
	end

	return table.concat(chunks, ""), highlights
end

local function render_results(results, query, opts)
	vim.schedule(function()
		state.results = results
		if vim.api.nvim_buf_is_valid(state.results_buf) then
			vim.api.nvim_buf_clear_namespace(state.results_buf, state.namespace, 0, -1)

			local lines = {}
			local highlights = {}
			for _, result in ipairs(results) do
				local line_text, line_hls = format_option(result, opts)
				table.insert(lines, line_text)
				table.insert(highlights, line_hls)
			end

			vim.api.nvim_buf_set_lines(state.results_buf, 0, -1, false, lines)

			-- Apply the highlights line by line
			for line_idx, line_hls in ipairs(highlights) do
				for _, hl in ipairs(line_hls) do
					print(hl.start_col .. ":" .. hl.end_col)
					vim.api.nvim_buf_set_extmark(state.results_buf, state.namespace, line_idx - 1, hl.start_col, {
						end_col = hl.end_col,
						hl_group = hl.hl_group,
						hl_mode = "combine",
					})
				end
			end

			-- add_first_option_highlight()
			-- highlight_result_line_fuzzymatches(lines, query)
			-- update_preview()
		end
	end)
end

local function filter_options(query, opts)
	local options_lookup = {}
	local option_labels = {}

	for i, opt in ipairs(state.options) do
		table.insert(option_labels, opt.label.text)
		options_lookup[opt.label.text] = i
	end

	local filtered = {}
	local matches = vim.fn.matchfuzzypos(option_labels, query)

	if query ~= "" then
		-- matches[1] is the matched labels
		-- matches[2] is the array of character position arrays
		local matched_labels = matches[1]
		local matched_positions = matches[2]

		for idx, label in ipairs(matched_labels) do
			local original_opt = state.options[options_lookup[label]]
			local positions = matched_positions[idx] -- Array of matched character indices

			-- Shallow copy the option so we don't mutate the original global state
			local opt = vim.tbl_extend("force", {}, original_opt)
			opt.label.highlights = {}

			-- Inject the matched positions into the object for rendering
			for _, pos in ipairs(positions) do
				local byte_start = vim.str_byteindex(opt.label.text, "utf-8", pos + 1) - 1
				local byte_end = vim.str_byteindex(opt.label.text, "utf-8", pos + 2) - 1
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

	render_results(filtered, query, opts)
end

local function run_shell_cmd(cmd, callback)
	print("Running cmd: " .. cmd)

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

local function filter_options_files(query)
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
		render_results(options, query, { show_file = false, show_row = false, show_col = false })
	end)
end

local function filter_options_live_grep(query)
	if query == "" then
		render_results({}, query, {})
		return
	end

	local shell_cmd = string.format("rg --json --hidden --smart-case %s | head -n 100", vim.fn.shellescape(query))

	run_shell_cmd(shell_cmd, function(output)
		-- print("Got: " .. vim.inspect(output))
		local options = {}
		for _, line in ipairs(output) do
			local ok, parsed = pcall(vim.json.decode, line)
			if ok and parsed and parsed.type == "match" then
				local data = parsed.data
				local filename = data.path.text
				local lnum = data.line_number
				local submatch = data.submatches[1] -- Grab the first match on this line

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
		render_results(options, query, { show_file = true, show_row = true, show_col = true })
	end)
end

local function run_search()
	local query = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)[1] or ""

	local get_options_func = nil
	local results_opts = {
		show_file = true,
		show_col = true,
		show_row = true,
	}

	if state.mode == "buffers" then
		get_options_func = get_buffer_options
	elseif state.mode == "diagnostics" then
		get_options_func = get_diagnostic_options
	elseif state.mode == "symbols" then
		get_options_func = get_document_symbols
	elseif state.mode == "files" then
		filter_options_files(query)
		return
	elseif state.mode == "live_grep" then
		filter_options_live_grep(query)
		return
	else
		vim.notify("Uknown mode: " .. state.mode, vim.log.levels.ERROR)
		return
	end

	get_options_func(function(options)
		state.options = options
		filter_options(query, results_opts)
	end)
end

function M.show_select(opts)
	debug_log("Running select: " .. opts.mode)

	state.mode = opts.mode
	state.original_buf = vim.api.nvim_get_current_buf()
	state.original_win = vim.api.nvim_get_current_win()

	init_windows(opts.mode, InputPosition.TOP, PreviewPosition.NONE)

	run_search()

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = state.input_buf,
		callback = function()
			state.debounce_timer:stop()
			state.debounce_timer:start(20, 0, vim.schedule_wrap(run_search))
		end,
	})
end

---@param config PickerConfig
function M.setup(config)
	-- print("Picker module loaded with config: " .. vim.inspect(config))
	state.config = {
		input_position = config.input_position or "TOP",
		preview_position = config.preview_position or "RIGHT",
		width = config.width or 0.8,
		height = config.height or 0.8,
	}
end

return M
