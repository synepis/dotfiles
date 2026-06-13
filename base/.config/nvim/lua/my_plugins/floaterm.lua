local M = {}

local state = {
	buf = nil,
	win = nil,
	chan_id = nil,
}

function M.setup()
	vim.api.nvim_create_user_command("FloaTermToggle", function()
		M.toggle_terminal()
	end, {})

	vim.api.nvim_create_user_command("FloaTermSendCmd", function(cmd)
		M.toggle_terminal(cmd)
	end, {})

	vim.api.nvim_create_user_command("FloaTermQuickfix", function()
		M.yank_to_quickfix()
	end, {})
end

function M.yank_to_quickfix()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		vim.notify("No active terminal buffer found", vim.log.levels.WARN)
		return
	end

	-- 1. Grab raw lines from the terminal buffer
	local raw_lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
	local clean_lines = {}

	for _, line in ipairs(raw_lines) do
		-- 2. STRIP ANSI ESCAPE CODES (Crucial for terminal buffers)
		-- This deletes all the hidden color/style data so it's pure text
		local clean = line:gsub("\27%[[0-9;]*[mK]", "")

		-- Remove carriage returns that terminals love to inject (\r)
		clean = clean:gsub("\r", "")

		-- Only keep lines that aren't empty shell prompts
		if clean:match("%S") then
			table.insert(clean_lines, clean)
		end
	end

	-- 3. Temporarily set the quickfix list with the cleaned text.
	-- This forces Neovim to parse the pure text using the current 'errorformat'
	vim.fn.setqflist({}, "r", {
		title = "Parsed Terminal Errors",
		lines = clean_lines,
	})

	-- 4. Filter out the "noise" entries that didn't match a real file.
	-- When setqflist parses text, valid errors get a 'valid = 1' flag.
	-- Junk lines (like compiler warnings or notes) get 'valid = 0'.
	local qf_items = vim.fn.getqflist()
	local only_errors = {}

	for _, item in ipairs(qf_items) do
		if item.valid == 1 then
			table.insert(only_errors, item)
		end
	end

	-- 5. Overwrite the quickfix list one last time with ONLY the valid matches
	vim.fn.setqflist({}, "r", {
		title = "Compiler Errors",
		items = only_errors,
	})

	-- 6. Hand off to Telescope
	local has_telescope, telescope = pcall(require, "telescope.builtin")
	if has_telescope then
		-- If the list is empty, don't open an empty picker
		if #only_errors == 0 then
			vim.notify("No compiler errors parsed from terminal output.", vim.log.levels.INFO)
			return
		end

		telescope.quickfix({
			show_line = true,
			trim_text = true,
		})
	else
		vim.cmd("copen")
	end
end

function M.toggle_terminal()
	-- 1. Check if the window is already open and valid; if so, close it
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
		state.win = nil
		return
	end

	-- 2. Ensure we have a valid buffer, or create one if it doesn't exist
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, true)
	end

	-- 3. Calculate dimensions (80% of screen)
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	-- 4. Open the window
	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = "Terminal",
	})

	-- 5. Only start the terminal process if the buffer is empty/new
	-- We check the 'buftype' to see if it's already a terminal
	if vim.bo[state.buf].buftype ~= "terminal" then
		state.chan_id = vim.fn.termopen(os.getenv("SHELL") or "bash")
	end

	-- Always enter insert mode when opening
	vim.cmd("startinsert")
end

function M.send_cmd_to_terminal(command)
	-- 1. If terminal doesn't exist or was deleted, create it
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		-- Reuse your existing toggle/open function logic here to spawn it
		M.toggle_terminal()
	end

	-- 2. Send the command + Carriage Return (\n)
	-- \21 is Ctrl-U (Line Kill)
	-- \12 is Ctrl-L (Clear Screen)
	if state.chan_id then
		vim.api.nvim_chan_send(state.chan_id, "\27Sclear\n")
		vim.api.nvim_chan_send(state.chan_id, command .. "\n")
	end

	-- 3. Ensure the window is open so we can see the result
	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		M.toggle_terminal()
	end
end

return M
