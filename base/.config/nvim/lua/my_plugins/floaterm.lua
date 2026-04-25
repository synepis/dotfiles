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
