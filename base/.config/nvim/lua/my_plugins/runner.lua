local M = {}

---@class Task Represent a "template" of how to run a command
---@field type string Type of task, e.g. build, test_all, test_one...
---@field cmd string Command to execute with variables not yet interpolated

---@class Execution Represent an "instance" of Task which can be executed
---@field type string Same as Task.type
---@field cmd string Command to execute but with all variables interpolated (ready to run)

---@class PluginState
---@field project_type string|nil The type of project, (e.g. 'lua', 'golang', 'zig')
---@field vars table<string, string> key-value pairs of static variables (defined in .tasks.json)
---@field execFn function|nil The callback to run a selected task/execution
---@field tasks Task[] Tasks loaded from .tasks.json
---@field executions Execution[] Executions ("intances" of tasks)
local state = {
	project_type = nil,
	vars = {},
	execFn = nil,
	tasks = {},
	executions = {},
}

local function interpolate_cmd_vars(cmd, vars)
	for var_name, var_value in pairs(vars) do
		cmd = string.gsub(cmd, "{{" .. var_name .. "}}", var_value)
	end
	return cmd
end

local function build_executions(tasks, vars)
	local executions = {}
	for _, task in ipairs(tasks) do
		-- Only tasks without context_vars can be directly invoked from the run menu,
		-- tasks with context_vars need context when invoked, e.g. invoked from a specific test file
		if task.context_vars == nil or #task.context_vars == 0 then
			table.insert(executions, {
				type = task.type,
				cmd = interpolate_cmd_vars(task.cmd, vars),
			})
		end
	end
	return executions
end

local function load_config_file()
	local tasks_file = vim.fn.getcwd() .. "/.tasks.json"
	if vim.fn.filereadable(tasks_file) == 1 then
		local data = vim.fn.readfile(tasks_file)
		local tasks_config = vim.fn.json_decode(data)

		state.tasks = tasks_config.tasks
		state.vars = tasks_config.vars
		state.project_type = tasks_config.project_type
		state.executions = build_executions(state.tasks, state.vars)

		return true
	end
	return false
end

local function get_nearest_test_node(test_node_types)
	-- 1. Get the node at the cursor
	local node = vim.treesitter.get_node()
	if not node then
		return nil
	end

	-- 2. Climb the tree until we find a matching node type
	while node do
		if vim.tbl_contains(test_node_types, node:type()) then
			return node
		end
		node = node:parent()
	end
	return nil
end

local function get_test_context()
	local ft = vim.bo.filetype
	local node = nil
	local test_name = nil

	if ft == "go" then
		node = get_nearest_test_node({ "function_declaration" })
		if node then
			-- In Go: (function_declaration name: (identifier) @name)
			local child = node:child(1) -- Simplification; better to use TS Query
			test_name = vim.treesitter.get_node_text(child, 0)
			if not test_name:match("^Test") then
				return nil
			end
		end
	end

	return test_name
end

local function is_cursor_in_node(node)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_row = cursor[1] - 1 -- TS uses 0-indexed rows
	local cursor_col = cursor[2]

	local start_row, start_col, end_row, end_col = node:range()

	print("Cursor: " .. cursor_row .. ", " .. cursor_col)
	print("Node: [" .. start_row .. "-" .. end_row .. "], [" .. start_col .. "-" .. end_col .. "]")

	-- Check if cursor is within the vertical and horizontal bounds
	local in_row = cursor_row >= start_row and cursor_row <= end_row
	if not in_row then
		return false
	end

	-- Extra precision: if on the boundary rows, check columns
	if cursor_row == start_row and cursor_col < start_col then
		return false
	end
	if cursor_row == end_row and cursor_col > end_col then
		return false
	end

	return true
end

local function find_under_cursor_query(query_str)
	local bufnr = vim.api.nvim_get_current_buf()
	local lang = vim.bo[bufnr].filetype
	local query = vim.treesitter.query.parse(lang, query_str)

	local curr = vim.treesitter.get_node()
	local s_row, s_col, e_row, e_col = curr:range()

	while curr do
		print(vim.inspect(curr))
		for pattern, match, metadata in query:iter_matches(curr, bufnr, s_row, s_row + 1) do
			print("Match" .. vim.inspect(pattern))
			for id, nodes in pairs(match) do
				local capture_name = query.captures[id]
				print(id .. "Capture name: " .. vim.inspect(capture_name))
				for _, node in ipairs(nodes) do
					local capture_text = vim.treesitter.get_node_text(node, bufnr)
					print("Capture value: " .. capture_text)
					-- return
				end
			end
		end
		curr = curr:parent()
	end

	print("Couldn't find nothing under cursor")
	return nil, nil
end

function M.setup(opts)
	state.execFn = opts.execFn

	load_config_file()

	vim.api.nvim_create_user_command("RunnerSelectTask", function()
		M.run_select_task()
	end, {})

	vim.api.nvim_create_user_command("RunnerRunUnderCursor", function()
		M.run_nearest_test()
	end, {})

	vim.api.nvim_create_user_command("RunnerRunUnderCursorDryRun", function()
		-- M.run_under_cursor_dry_run()
		local query = [[
			((function_declaration 
		        name: (identifier) @test_name) 
		        (#match? @test_name "^Test")) 
		    ((function_declaration 
		        name: (identifier) @main_name) 
		        (#eq? @main_name "main")) 
		]]
		find_under_cursor_query(query)
	end, {})

	vim.api.nvim_create_user_command("RunnerReloadConfig", function()
		M.reload_config_file()
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
		state.execFn(task.cmd)
	end
end

function M.reload_config_file()
	if load_config_file() == false then
		vim.notify("Error loading .tasks.json", vim.log.levels.ERROR)
		return
	end
	vim.notify("Runner loaded .tasks.json", vim.log.levels.INFO)
end

function M.run_select_task()
	if state.executions == nil or #state.executions == 0 then
		vim.notify("Runner: No available tasks/executions", vim.log.levels.WARN)
		return
	end

	-- 4. Create a list of display names
	local options = {}
	for _, task in ipairs(state.executions) do
		table.insert(options, task.type)
	end

	-- 5. Show the picker
	vim.ui.select(options, {
		prompt = "Select Task to Run:",
	}, function(choice)
		if not choice then
			return
		end

		-- Find the command corresponding to the choice
		for _, task in ipairs(state.executions) do
			if task.type == choice then
				run_task(task)
				return
			end
		end
	end)
end

local function find_task_by_type(tasks, type)
	for _, task in ipairs(tasks) do
		if task.type == type then
			return task
		end
	end
	return nil
end

local function find_execution_by_cmd(executions, cmd)
	for _, execution in ipairs(executions) do
		print(execution.cmd, cmd)
		if execution.cmd == cmd then
			return execution
		end
	end
	return nil
end

local function buffer_name_matches(pattern)
	local filename = vim.api.nvim_buf_get_name(0)
	return filename:match(pattern) ~= nil
end

local function is_go_test_file()
	return buffer_name_matches("_test%.go$") ~= nil
end

local function find_under_cursor(node_eval_func)
	local node = vim.treesitter.get_node()
	if not node then
		return nil
	end

	while node do
		local type = node:type()
		local name_node = node:child(1)
		local name_text = vim.treesitter.get_node_text(name_node, 0)
		print(type .. "|" .. name_text)
		node = node:parent()
	end
	return nil
end

local function recurse_syntax_tree()
	local node = vim.treesitter.get_node()
	if not node then
		return nil
	end

	while node do
		local type = node:type()
		local name_node = node:child(1)
		local name_text = vim.treesitter.get_node_text(name_node, 0)
		print(type .. "|" .. name_text)

		if is_go_test_function(node) then
		elseif is_go_main_function(node) then
		end

		node = node:parent()
	end
	return nil
end
-- Run under cursor logic:
-- Detect file type (pythong, golang, zig...)
-- Detect if inside test method
-- Detect if inside test file
-- Detect if inside main function
function M.run_under_cursor_dry_run()
	local ft = vim.bo.filetype
	local filename = vim.fn.expand("%:t")

	recurse_syntax_tree()
end

function M.run_nearest_test()
	local test_name = get_test_context()
	if not test_name then
		vim.notify("No test found at cursor", vim.log.levels.WARN)
		return
	end

	local cmd = ""
	local ft = vim.bo.filetype

	if ft == "go" then
		cmd = string.format("go test -v -run ^%s$", test_name)
	elseif ft == "python" then
		cmd = string.format("pytest %s::%s", vim.fn.expand("%"), test_name)
	elseif ft == "zig" then
		cmd = string.format("zig test --filter '%s' %s", test_name, vim.fn.expand("%"))
	end

	local vars = vim.tbl_extend("force", state.vars, { TEST_NAME = test_name })
	local test_one_task = find_task_by_type(state.tasks, "test_one")
	local test_one_execution = {
		type = test_one_task.type .. " " .. test_name,
		cmd = interpolate_cmd_vars(test_one_task.cmd, vars),
	}

	if find_execution_by_cmd(state.executions, test_one_execution.cmd) == nile then
		table.insert(state.executions, test_one_execution)
	end

	run_task(test_one_execution)
end

return M
