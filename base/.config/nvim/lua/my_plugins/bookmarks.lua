local M = {}

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

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
			invalidate = true,
		})
		local extmark = {
			id = id,
			bufnr = bufnr,
			row = row,
			col = col,
			text = vim.trim(vim.api.nvim_get_current_line()),
			filename = filename,
		}
		table.insert(M.bookmarks, extmark)
	end
end

local function make_picker_entries()
	local valid_bookmarks = {}
	for _, mark in ipairs(M.bookmarks) do
		local ok, details = pcall(vim.api.nvim_buf_get_extmark_by_id, mark.bufnr, ns_id, mark.id, { details = true })
		if ok and details and #details > 0 and not details[3].invalid then
			mark.row = details[1]
			mark.col = details[2]
			if vim.api.nvim_buf_is_loaded(mark.bufnr) then
				local text = vim.api.nvim_buf_get_lines(mark.bufnr, mark.row, mark.row + 1, false)[1] or mark.text
				mark.text = vim.trim(text)
			end
			table.insert(valid_bookmarks, mark)
		end
	end
	M.bookmarks = valid_bookmarks

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
				bufnr = entry.bufnr,
			}
		end,
	})
end

function M.show_bookmarks()
	pickers
		.new({}, {
			prompt_title = "Bookmarks",
			finder = make_picker_entries(),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				title = "Bookmark Preview",
				define_preview = function(self, entry, status)
					-- 1. Get the actual current position of the extmark
					print(vim.inspect(entry))
					local details =
						vim.api.nvim_buf_get_extmark_by_id(entry.bufnr, ns_id, entry.value, { details = true })

					if details and #details > 0 then
						local live_row = details[1] + 1

						-- 2. Put the file in the preview buffer
						conf.buffer_previewer_maker(entry.filename, self.state.bufnr, {
							bufnr = self.state.bufnr,
							winid = self.state.winid,
						})

						-- 3. Scroll the preview window to the LIVE position
						-- vim.schedule(function()
						-- 	if vim.api.nvim_win_is_valid(self.state.winid) then
						-- 		vim.api.nvim_win_set_cursor(self.state.winid, { live_row, 0 })
						-- 		-- Center the line in the preview
						-- 		vim.api.nvim_buf_call(self.state.bufnr, function()
						-- 			vim.cmd("normal! zz")
						-- 		end)
						-- 	end
						-- end)
					end
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				local delete_bookmark = function()
					local selection = action_state.get_selected_entry()
					remove_bookmark_by_id(M.bookmarks, selection.value)

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
