local M = {}

-- 1. Get initial items/results (if any)
-- 2. Accept input
-- 3. On Input filter results
-- 4. Update preview

local state = {
	-- Original buffer from which the plugin was launched
	original_buf = nil,
	original_win = nil,

	-- Needed windows for the UI
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

	-- Source data and filtered results
	source_items = nil,
	options = nil,
}

local function del_first_option_highlight()
	if state.first_option_ext_mark then
		vim.api.nvim_buf_del_extmark(state.results_buf, state.namespace, state.first_option_ext_mark)
		state.first_option_ext_mark = nil
	end
end

local function add_first_option_highlight()
	local first_line = vim.api.nvim_buf_get_lines(state.results_buf, 0, 1, false)[1]

	if first_line and first_line ~= "" then
		del_first_option_highlight()
		state.first_option_ext_mark = vim.api.nvim_buf_set_extmark(state.results_buf, state.namespace, 0, 0, {
			hl_eol = true,
			hl_group = "CursorLine",
			end_row = 1,
		})
	end
end

local function add_fuzzymatch_letter_highlights(lines, query)
	if not state.results_buf or not vim.api.nvim_buf_is_valid(state.results_buf) or query == "" then
		return
	end

	local result = vim.fn.matchfuzzypos(lines, query)
	local pos_list = result[2]

	if not pos_list then
		return
	end

	for line_idx, char_positions in ipairs(pos_list) do
		local line = lines[line_idx]
		if line then
			for _, char_pos in ipairs(char_positions) do
				pcall(vim.api.nvim_buf_set_extmark, state.results_buf, state.namespace, line_idx - 1, char_pos, {
					end_col = char_pos + 1,
					hl_group = "WarningMsg",
					priority = 100,
				})
			end
		end
	end
end

local function close_picker()
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

local function update_preview()
	if not state.results_win or not vim.api.nvim_win_is_valid(state.results_win) then
		return
	end
	if not state.preview_buf or not vim.api.nvim_buf_is_valid(state.preview_buf) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(state.results_win)
	local idx = cursor[1]
	local selection = state.options[idx]

	if selection.type == "buffer" then
		local bufnr = selection.key;
		
	local filename = vim.api.nvim_buf_get_lines(state.results_buf, idx - 1, idx, false)[1]
	else
		vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, { "Not a buffer" })
		return
	end

	local filename = vim.api.nvim_buf_get_lines(state.results_buf, idx - 1, idx, false)[1]

	if not filename or filename == "" then
		vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, { "No file selected" })
		return
	end

	-- 1. Open the file asynchronously
	vim.uv.fs_open(filename, "r", 438, function(open_err, fd)
		if open_err or not fd then
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(state.preview_buf) then
					vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, { "Error opening file" })
				end
			end)
			return
		end

		-- 2. Read a 8KB chunk (usually plenty to get the first 100 lines)
		vim.uv.fs_read(fd, 8192, 0, function(read_err, data)
			-- Always close the file descriptor when done reading
			vim.uv.fs_close(fd)

			if read_err or not data then
				return
			end

			-- 3. Process the raw data chunk into clean lines
			local lines = {}
			for line in string.gmatch(data, "[^\r\n]+") do
				if #lines >= 100 then
					break
				end
				table.insert(lines, line)
			end

			-- 4. Jump back to Neovim's main thread to modify the buffer safely
			vim.schedule(function()
				if not state.preview_buf or not vim.api.nvim_buf_is_valid(state.preview_buf) then
					return
				end

				vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, lines)

				-- Apply syntax highlighting
				local ft = vim.filetype.match({ filename = filename })
				if ft then
					vim.bo[state.preview_buf].syntax = ft
				else
					vim.bo[state.preview_buf].syntax = "off"
				end
			end)
		end)
	end)
end

local function render_results(options, query)
	vim.schedule(function()
		state.options = options

		if vim.api.nvim_buf_is_valid(state.results_buf) then
			local lines = {}
			for _, result in ipairs(options) do
				table.insert(lines, result.label)
			end
			vim.api.nvim_buf_set_lines(state.results_buf, 0, -1, false, lines)
			add_first_option_highlight()
			add_fuzzymatch_letter_highlights(lines, query)
			-- update_preview()
		end
	end)
end

local function make_buffer_option(bufnr, label, row, col)
	return {
		type = "buffer",
		key = bufnr,
		label = label,
		row = row,
		col = col,
	}
end

local function make_file_option(filename, row, col)
	return {
		type = "file",
		key = filename,
		label = filename,
		row = row,
		col = col,
	}
end

local function get_buffer_options()
	local listed_bufs = vim.api.nvim_list_bufs() -- Listed (user) buffers avoids including other non-file buffers
	local options = {}
	for _, buf in ipairs(listed_bufs) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
			-- table.insert(options, { key = buf, label = vim.api.nvim_buf_get_name(buf) })
			table.insert(options, make_buffer_option(buf, vim.api.nvim_buf_get_name(buf), nil, nil))
		end
	end
	return options
end

local function get_diagnostic_options()
	local diagnostics = vim.diagnostic.get(nil)
	local options = {}

	local severity_labels = {
		[vim.diagnostic.severity.ERROR] = "󰅚 ERROR",
		[vim.diagnostic.severity.WARN] = "󰀪 WARN",
		[vim.diagnostic.severity.INFO] = "󰋽 INFO",
		[vim.diagnostic.severity.HINT] = "󰌶 HINT",
	}

	for _, diag in ipairs(diagnostics) do
		local filename = vim.api.nvim_buf_get_name(diag.bufnr)
		local relative_file = vim.fn.fnamemodify(filename, ":.")
		local lnum = diag.lnum + 1
		local severity = severity_labels[diag.severity] or "DIAG"
		local label = string.format("%s:%d [%s] %s", relative_file, lnum, severity, diag.message:gsub("\n", " "))
		-- table.insert(options, { key = diag, label = label })
		table.insert(options, make_buffer_option(diag.bufnr, label, lnum, nil))
	end
	return options
end

-- local function flatten_and_filter_symbols(symbols, allowed_kinds, container_name)
-- 	local flat = {}
-- 	local symbol_kind_map = vim.lsp.protocol.SymbolKind
--
-- 	for _, symbol in ipairs(symbols) do
-- 		-- 1. Convert integer kind to string name (e.g., 12 -> "Function")
-- 		local kind_name = symbol_kind_map[symbol.kind] or "Unknown"
--
-- 		-- 2. Construct a clean display path (e.g., "setup_windows > state.original_buf")
-- 		local display_name = container_name and (container_name .. " > " .. symbol.name) or symbol.name
--
-- 		-- 3. Check if we should include this symbol based on our filter list
-- 		-- If allowed_kinds is nil or empty, we include everything
-- 		local is_allowed = not allowed_kinds or vim.tbl_contains(allowed_kinds, kind_name)
--
-- 		if is_allowed then
-- 			table.insert(flat, {
-- 				name = display_name, -- For the picker display text
-- 				raw_name = symbol.name, -- The base name
-- 				kind = kind_name, -- String type ("Function", "Variable")
-- 				lnum = symbol.range.start.line + 1, -- 1-indexed for Neovim jumping
-- 				col = symbol.range.start.character + 1,
-- 			})
-- 		end
--
-- 		local x = {
-- 			name = display_name, -- For the picker display text
-- 			raw_name = symbol.name, -- The base name
-- 			kind = kind_name, -- String type ("Function", "Variable")
-- 			lnum = symbol.range.start.line + 1, -- 1-indexed for Neovim jumping
-- 			col = symbol.range.start.character + 1,
-- 		}
--
-- 		-- 4. Recursively process children (even if the parent itself was filtered out)
-- 		if symbol.children and not vim.tbl_isempty(symbol.children) then
-- 			local children_flat = flatten_and_filter_symbols(symbol.children, allowed_kinds, symbol.name)
-- 			for _, child in ipairs(children_flat) do
-- 				table.insert(flat, child)
-- 			end
-- 		end
-- 	end
--
-- 	return flat
-- end

local function get_document_symbols(callback)
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

		local items_for_picker = {}
		local symbol_kind_map = vim.lsp.protocol.SymbolKind

		-- Recursive helper to flatten the AST tree and filter functions
		local function process_symbols(symbols, container_name)
			for _, symbol in ipairs(symbols) do
				local kind_name = symbol_kind_map[symbol.kind] or "Unknown"

				-- Only care about Functions and Methods (functions inside classes/tables)
				if kind_name == "Function" or kind_name == "Method" then
					local display_name = container_name and (container_name .. " > " .. symbol.name) or symbol.name

					-- table.insert(items_for_picker, {
					-- 	label = display_name, -- The string your fuzzy filter looks at!
					-- 	lnum = symbol.range.start.line + 1,
					-- 	col = symbol.range.start.character + 1,
					-- 	kind = kind_name,
					-- })

					table.insert(
						items_for_picker,
						make_buffer_option(
							bufnr,
							display_name,
							symbol.range.start.line + 1,
							symbol.range.start.character + 1
						)
					)
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

		-- print(vim.inspect(items_for_picker))

		-- Pass the flat array of function definitions to your picker
		if callback then
			callback(items_for_picker)
		end
	end)
end
local function filter_options_fuzzy(options, query)
	local options_lookup = {}
	local option_labels = {}

	for i, opt in ipairs(options) do
		table.insert(option_labels, opt.label)
		options_lookup[opt.label] = i
	end

	local results = options
	local matches = vim.fn.matchfuzzypos(option_labels, query)

	if query ~= "" then
		for _, label in ipairs(matches[1]) do
			local item = options[options_lookup[label]]
			table.insert(results, item)
		end
	end

	render_results(results, query)
end

local function filter_items(source)
	local query = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)[1] or ""

	if source == "files" then
		return
	elseif source == "buffers" then
		filter_options_fuzzy(get_buffer_options(), query)
	elseif source == "diagnostics" then
		filter_options_fuzzy(get_diagnostic_options(), query)
	elseif source == "symbols" then
		get_document_symbols(function(options)
			filter_options_fuzzy(options, query)
		end)
	end
end

local function run_search()
	if state.search_job then
		pcall(state.uv.kill, state.search_job, 15)
		state.search_job = nil
	end

	local query = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)[1] or ""

	local shell_cmd = "fd --type f --hidden --no-ignore --max-results 1000 --exclude .git"
	if query ~= "" then
		shell_cmd = string.format("%s | fzf -f %s", shell_cmd, vim.fn.shellescape(query))
	end

	local stdout = state.uv.new_pipe(false)
	local output_chunks = {}

	-- Spawn the shell task on a background worker thread via libuv
	state.search_job, _ = state.uv.spawn("sh", {
		args = { "-c", shell_cmd },
		stdio = { nil, stdout, nil },
	}, function()
		-- Process termination callback
		if stdout then
			stdout:read_stop()
			stdout:close()
		end
		state.search_job = nil

		-- Compile string array data once fully buffered
		local raw_output = table.concat(output_chunks)
		local lines = {}
		for line in string.gmatch(raw_output, "[^\r\n]+") do
			table.insert(lines, line)
		end

		-- Schedule buffer rendering updates back onto Neovim's main UI thread safely
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(state.results_buf) then
				vim.api.nvim_buf_set_lines(state.results_buf, 0, -1, false, lines)
				add_first_option_highlight()
				update_preview()
				add_fuzzymatch_letter_highlights(lines, query)
			end
		end)
	end)

	state.uv.read_start(stdout, function(_, data)
		if data then
			table.insert(output_chunks, data)
		end
	end)
end

local function setup_windows(mode)
	-- Remember the original buffer
	state.original_buf = vim.api.nvim_get_current_buf()
	state.original_win = vim.api.nvim_get_current_win()

	-- Layout the windows
	local ui = vim.api.nvim_list_uis()[1]
	local width = math.floor(ui.width * 0.8)
	local height = math.floor(ui.height * 0.8)
	local row = math.floor((ui.height - height) / 2)
	local col = math.floor((ui.width - width) / 2)

	state.input_buf = vim.api.nvim_create_buf(false, true)
	state.results_buf = vim.api.nvim_create_buf(false, true)
	state.preview_buf = vim.api.nvim_create_buf(false, true)

	-- Disable any completion plugins on the input window
	vim.b[state.input_buf].completion = false

	state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
		title = "Find " .. mode,
		title_pos = "center",
		relative = "editor",
		width = width,
		height = 1,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
	})
	state.results_win = vim.api.nvim_open_win(state.results_buf, false, {
		title = "Results",
		title_pos = "center",
		relative = "editor",
		width = width,
		height = math.floor((height - 2) / 2),
		row = row + 2 + 1,
		col = col,
		style = "minimal",
		border = "rounded",
	})
	state.preview_win = vim.api.nvim_open_win(state.preview_buf, false, {
		title = "Preview",
		title_pos = "center",
		relative = "editor",
		width = width,
		height = math.floor((height - 2) / 2),
		row = row + 2 + 1 + math.floor((height - 2) / 2) + 2,
		col = col,
		style = "minimal",
		border = "rounded",
	})

	-- Setup event listeners
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = state.input_buf,
		callback = function()
			state.debounce_timer:stop()
			-- state.debounce_timer:start(20, 0, vim.schedule_wrap(run_search))
			state.debounce_timer:start(
				20,
				0,
				vim.schedule_wrap(function()
					filter_items(mode)
				end)
			)
		end,
	})

	vim.api.nvim_create_autocmd({ "CursorMoved", "BufWinEnter" }, {
		buffer = state.results_buf,
		callback = function()
			state.debounce_timer:stop()
			state.debounce_timer:start(20, 0, vim.schedule_wrap(update_preview))
		end,
	})

	-- Setup keybindings
	local common_opts = { silent = true }

	vim.keymap.set("n", "<Esc>", close_picker, { buffer = state.input_buf, unpack(common_opts) })
	vim.keymap.set("n", "<Esc>", close_picker, { buffer = state.results_buf, unpack(common_opts) })
	vim.keymap.set("n", "q", close_picker, { buffer = state.results_buf, unpack(common_opts) })

	vim.keymap.set("n", "j", function()
		if vim.api.nvim_win_is_valid(state.results_win) then
			vim.api.nvim_set_current_win(state.results_win)
			vim.api.nvim_win_set_cursor(state.results_win, { 1, 0 })
			del_first_option_highlight()
		end
	end, { buffer = state.input_buf, unpack(common_opts) })

	vim.keymap.set("n", "k", function()
		if vim.api.nvim_win_is_valid(state.results_win) then
			vim.api.nvim_set_current_win(state.results_win)
			local last_line = vim.api.nvim_buf_line_count(state.results_buf)
			vim.api.nvim_win_set_cursor(state.results_win, { last_line, 0 })
			del_first_option_highlight()
		end
	end, { buffer = state.input_buf, unpack(common_opts) })

	local function return_to_input()
		if vim.api.nvim_win_is_valid(state.input_win) then
			vim.api.nvim_set_current_win(state.input_win)
			vim.cmd("startinsert!") -- '!' places cursor at the end of the line
		end
	end
	vim.keymap.set("n", "i", return_to_input, { buffer = state.results_buf, unpack(common_opts) })
	vim.keymap.set("n", "a", return_to_input, { buffer = state.results_buf, unpack(common_opts) })

	local function accept_selection()
		local focus_win = state.results_win
		if not vim.api.nvim_win_is_valid(focus_win) then
			return
		end

		local cursor = vim.api.nvim_win_get_cursor(focus_win)
		local idx = cursor[1]
		local selected = vim.api.nvim_buf_get_lines(state.results_buf, idx - 1, idx, false)[1]


		close_picker()

		if selected and selected ~= "" then
			vim.cmd("edit " .. vim.fn.fnameescape(selected))
		end
	end

	vim.keymap.set({ "n", "i" }, "<CR>", accept_selection, { buffer = state.input_buf, unpack(common_opts) })
	vim.keymap.set("n", "<CR>", accept_selection, { buffer = state.results_buf, unpack(common_opts) })
end

function M.show_select(opts)
	-- print("Opts: " .. vim.inspect(opts))
	setup_windows(opts.mode)

	-- Kick off the initial layout load
	-- run_search()
	filter_items(opts.mode)
	vim.cmd("startinsert")
end

function M.setup()
	print("Picker module loaded")
end

return M
