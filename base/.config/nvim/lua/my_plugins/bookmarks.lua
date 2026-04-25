local M = {}

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local ns_id = vim.api.nvim_create_namespace("bookmarks")

local defaults = {
	sign_text = " ",
	sign_hl = "ErrorMsg",
}

local function log(msg)
	local log_file = io.open("/tmp/bookmarks.nvim.log", "a")
	if log_file then
		log_file:write(os.date("%H:%M:%S") .. " : " .. vim.inspect(msg) .. "\n")
		log_file:close()
	end
end

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", defaults, opts or {})
	M.bookmarks = {}

	vim.api.nvim_create_user_command("BookmarksShow", function()
		M.show_bookmarks()
	end, {})

	vim.api.nvim_create_user_command("BookmarksToggle", function()
		M.toggle_bookmark()
	end, {})
end

local function remove_bookmark_by_id(marks, id)
	for i, m in ipairs(marks) do
		if m.id == id then
			table.remove(marks, i)
			vim.api.nvim_buf_del_extmark(m.bufnr, ns_id, id)
			break
		end
	end
end

function M.toggle_bookmark()
	local bufnr = vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1
	local col = cursor[2]

	local existing = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { row, 0 }, { row, -1 }, {})

	if #existing > 0 then
		local id = existing[1][1]
		remove_bookmark_by_id(M.bookmarks, id)
	else
		local id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, col, {
			sign_text = M.options.sign_text,
			sign_hl_group = M.options.sign_hl,
		})
		local extmark = {
			id = id,
			bufnr = bufnr,
			row = row,
			col = col,
			text = vim.api.nvim_get_current_line(),
			filename = filename,
		}
		table.insert(M.bookmarks, extmark)
	end
end

local function make_picker_entries()
	return finders.new_table({
		results = M.bookmarks,
		entry_maker = function(entry)
			return {
				value = entry.id,
				display = string.format("[%d] %s", entry.id, entry.text),
				ordinal = entry.text,
				filename = entry.filename,
				lnum = entry.row + 1,
				col = entry.col,
			}
		end,
	})
end

function M.show_bookmarks()
	local opts = opts or {}
	pickers
		.new(opts, {
			prompt_title = "Bookmarks",
			finder = make_picker_entries(),
			sorter = conf.generic_sorter(opts),
			previewer = conf.grep_previewer({}),
			attach_mappings = function(prompt_bufnr, map)
				local delete_bookmark = function()
					local selection = action_state.get_selected_entry()
					remove_bookmark_by_id(M.bookmarks, selection.value)
					print("Removing: " .. vim.inspect(selection.value))

					local current_picker = action_state.get_current_picker(prompt_bufnr)
					current_picker:refresh(make_picker_entries(), { reset_prompt = true })
				end

				map("i", "<C-d>", delete_bookmark)
				map("n", "d", delete_bookmark)

				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					vim.cmd("edit " .. selection.filename)
					vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col })
				end)
				return true
			end,
		})
		:find()
end

return M
