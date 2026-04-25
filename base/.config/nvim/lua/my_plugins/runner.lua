local M = {}

local defaults = {
	execFn = nil,
}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", defaults, opts or {})

	vim.api.nvim_create_user_command("RunnerSelectTask", function()
		M.run_select_task()
	end, {})
end

local function run_task(task)
	if task.debug then
		require("dap").run({
			type = "go",
			name = task.name,
			request = "launch",
			program = task.cmd,
			args = {},
		})
	else
		M.options.execFn(task.cmd)
	end
end

function M.run_select_task()
	-- 1. Define the path to your tasks file
	local tasks_file = vim.fn.getcwd() .. "/.tasks.json"

	-- 2. Check if the file exists
	if vim.fn.filereadable(tasks_file) == 0 then
		vim.notify("No .tasks.json found in project root", vim.log.levels.WARN)
		return
	end

	-- 3. Read and decode the JSON
	local data = vim.fn.readfile(tasks_file)
	local tasks = vim.fn.json_decode(data)

	-- 4. Create a list of display names
	local options = {}
	for _, task in ipairs(tasks) do
		table.insert(options, task.name)
	end

	-- 5. Show the picker
	vim.ui.select(options, {
		prompt = "Select Task to Run:",
	}, function(choice)
		if not choice then
			return
		end

		-- Find the command corresponding to the choice
		for _, task in ipairs(tasks) do
			if task.name == choice then
				run_task(task)
				return
			end
		end
	end)
end

return M
