local M = {}

local state = {
	bookmarks = {}, -- array with all the marks' (bufnr, id)
	is_sorted = false, -- flag indicating whether the `bookmarks` array is sorted
	idx = 0, -- the current position in the `bookmarks` array
}

local default_config = {
	signs = {
		priority = 10,
		sign_text = "",
		sign_hl_group = "DiagnosticHint",
		number_hl_group = nil,
		line_hl_group = nil,
		cursorline_hl_group = nil,
	},
	keymaps = {
		normal = {
			toggle = "<leader>mm",
			next = "<leader>nn",
			prev = "<leader><S-n><S-n>",
			show = "<leader>fm",
			remove_in_buffer = "<leader>rm",
			remove_all = "<leader><S-r>m",
		},
		insert = {},
		visual = {
			next = "<leader>nn",
			prev = "<leader><S-n><S-n>",
		},
	},
	picker = {
		prompt_title = "Bookmarks",
		initial_mode = "normal",
		normal_prompt_delete = "<C-r>",
		insert_prompt_delete = "<C-r>",
	},
}

M.config = nil

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", {}, default_config, opts or {})

	local modes = {
		normal = "n",
		insert = "i",
		visual = "v",
	}

	local actions = {
		toggle = M.toggle,
		next = M.next,
		prev = M.prev,
		show = M.show,
		remove_in_buffer = M.remove_in_buffer,
		remove_all = M.remove_all,
	}

	for mode, mappings in pairs(M.config.keymaps) do
		if modes[mode] then
			for action, mapping in pairs(mappings) do
				if actions[action] and mapping then
					vim.keymap.set(modes[mode], mapping, actions[action])
				end
			end
		end
	end
end

local ns_id = vim.api.nvim_create_namespace("bookmarks")

local function remove_by_id(bufnr, id)
	for i, mark in ipairs(state.bookmarks) do
		if (mark.bufnr == bufnr) and (mark.id == id) then
			vim.api.nvim_buf_del_extmark(mark.bufnr, ns_id, mark.id)
			table.remove(state.bookmarks, i)
			return
		end
	end
end

local function remove_by_buffer(bufnr)
	-- iterate backwards because of lua indexing-while-mutating problem
	for i = #state.bookmarks, 1, -1 do
		local mark = state.bookmarks[i]
		if mark.bufnr == bufnr then
			vim.api.nvim_buf_del_extmark(mark.bufnr, ns_id, mark.id)
			table.remove(state.bookmarks, i)
		end
	end
end

function M.remove_in_buffer()
	return remove_by_buffer(vim.api.nvim_get_current_buf())
end

function M.remove_all()
	for i, mark in ipairs(state.bookmarks) do
		vim.api.nvim_buf_del_extmark(mark.bufnr, ns_id, mark.id)
	end
	state.bookmarks = {}
end

function M.toggle()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] - 1
	local col = cursor[2]

	local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { row, 0 }, { row, -1 }, {})
	if #marks > 0 then
		local id = marks[1][1]
		remove_by_id(bufnr, id)
		return
	end

	local id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, col, {
		priority = M.config.signs.priority,
		sign_text = M.config.signs.sign_text,
		sign_hl_group = M.config.signs.sign_hl_group,
		number_hl_group = M.config.signs.number_hl_group,
		line_hl_group = M.config.signs.line_hl_group,
		cursorline_hl_group = M.config.signs.cursorline_hl_group,
		invalidate = true,
	})

	local mark = {
		bufnr = bufnr,
		id = id,
	}
	table.insert(state.bookmarks, mark)

	state.is_sorted = false
end

local function advance(offset)
	if #state.bookmarks == 0 then
		return
	end

	if not state.is_sorted then
		table.sort(state.bookmarks, function(a, b)
			return (a.bufnr == b.bufnr and a.id < b.id) or a.bufnr < b.bufnr
		end)
		state.is_sorted = true
	end

	state.idx = ((state.idx + offset - 1) % #state.bookmarks) + 1
	local mark = state.bookmarks[state.idx]
	local pos = vim.api.nvim_buf_get_extmark_by_id(mark.bufnr, ns_id, mark.id, { details = true })

	if #pos == 0 or pos[3].invalid then
		vim.api.nvim_buf_del_extmark(mark.bufnr, ns_id, mark.id)
		table.remove(state.bookmarks, state.idx)
		state.idx = (state.idx > 0) and (state.idx - 1) or 0
		return M.move(offset)
	end

	vim.api.nvim_set_current_buf(mark.bufnr)
	vim.api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
end

function M.next()
	return advance(vim.v.count1)
end

function M.prev()
	return advance(-vim.v.count1)
end

local function make_entries()
	local finders = require("telescope.finders")

	-- remove invalid bookmarks
	local valid_bookmarks = {}
	for _, mark in ipairs(state.bookmarks) do
		local pos = vim.api.nvim_buf_get_extmark_by_id(mark.bufnr, ns_id, mark.id, { details = true })
		if (#pos > 0) and not pos[3].invalid then
			table.insert(valid_bookmarks, mark)
		end
	end
	state.bookmarks = valid_bookmarks

	return finders.new_table({
		results = state.bookmarks,
		entry_maker = function(mark)
			local pos = vim.api.nvim_buf_get_extmark_by_id(mark.bufnr, ns_id, mark.id, {})
			local file = vim.api.nvim_buf_get_name(mark.bufnr)
			local text = vim.trim(vim.api.nvim_buf_get_lines(mark.bufnr, pos[1], pos[1] + 1, false)[1])

			return {
				value = mark.id,
				ordinal = text,
				display = string.format("[%d,%d] %s", mark.bufnr, mark.id, text),
				filename = file,
				bufnr = mark.bufnr,
				lnum = pos[1] + 1,
				col = pos[2],
			}
		end,
	})
end

function M.show()
	local pickers = require("telescope.pickers")
	local config_values = require("telescope.config").values
	local actions = require("telescope.actions")
	local actions_state = require("telescope.actions.state")

	local actions_utils = require("telescope.actions.utils")

	pickers
		.new({}, {
			prompt_title = M.config.picker.prompt_title,
			initial_mode = M.config.picker.initial_mode,
			finder = make_entries(),
			previewer = config_values.grep_previewer({}),
			sorter = config_values.generic_sorter({}),
			attach_mappings = function(picker_bufnr, map)
				-- delete entries under multi-select or, if none, the entry under the cursor
				local delete_entries = function()
					-- use `no_multi_select` flag since there is apparently no way to check if multi-select is on
					no_multi_select = true

					-- delete entries under multi-select if any
					actions_utils.map_selections(picker_bufnr, function(entry, _)
						no_multi_select = false
						remove_by_id(entry.bufnr, entry.value)
					end)

					-- delete the entry under the cursor if none were under multi-select
					if no_multi_select then
						local entry = actions_state.get_selected_entry()
						remove_by_id(entry.bufnr, entry.value)
					end

					local current_picker = actions_state.get_current_picker(picker_bufnr)
					current_picker:refresh(make_entries(), { reset_prompt = true })
				end

				if M.config.picker.normal_prompt_delete then
					map("n", M.config.picker.normal_prompt_delete, delete_entries)
				end
				if M.config.picker.insert_prompt_delete then
					map("i", M.config.picker.insert_prompt_delete, delete_entries)
				end

				return true
			end,
		})
		:find()
end

return M
