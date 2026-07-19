local M = {}

local treesitter_textobj_config = {
	lua = {
		function_call = {
			query = [[
                (function_call) @function_call
            ]],
		},
		function_outer = {
			query = [[
                [(function_declaration)
                 (function_definition)] @function_outer
            ]],
		},
		function_inner = {
			query = [[
                (function_declaration
                  body: (_) @function_inner)

                (function_definition
                  body: (_) @function_inner)
            ]],
		},
		parameter_inner = {
			capture_name = "parameter",
			query = [[
                (arguments (_) @parameter)
                (parameters (_) @parameter)
            ]],
		},
		parameter_outer = {
			capture_name = "parameter",
			query = [[
                (arguments (_) @parameter)
                (parameters (_) @parameter)
            ]],
			list_delimiter = ",",
		},
	},
}

local function get_treesitter_node_range(node, list_delimiter)
	if not list_delimiter then
		return node:range()
	else
		-- For nodes which are parts of list (.e.g parameters, arguments) and
		-- we want to extract the outer rather than inner variant we need to
		-- also include any delimiters with it (e.g. commas)
		local prev = node:prev_sibling()
		local next = node:next_sibling()

		local s_row, s_col, e_row, e_col = node:range()

		if next and next:type() == list_delimiter then
			_, _, e_row, e_col = next:range()
		elseif prev and prev:type() == list_delimiter then
			s_row, s_col, _, _ = prev:range()
		end

		return s_row, s_col, e_row, e_col
	end
end

local function cursor_in_node_range(c_row, c_col, node)
	local s_row, s_col, e_row, e_col = node:range()
	local in_row_range = s_row <= c_row and e_row >= c_row

	if not in_row_range then
		return false
	end

	if s_row == e_row then
		return s_col <= c_col and c_col <= e_col
	elseif s_row == c_row then
		return s_col <= c_col
	elseif e_row == c_row then
		return c_col <= e_col
	else
		return true
	end
end

function M.select_text_object(text_obj_name)
	local bufnr = 0
	local language = vim.bo[bufnr].filetype

	local parser = vim.treesitter.get_parser(bufnr, language, { error = false })
	if not parser then
		return
	end

	local tree = parser:parse()[1]
	local root = tree:root()

	local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
	cursor_row = cursor_row - 1

	local lang_config = treesitter_textobj_config[language]
	if not lang_config then
		print("No function pattern configured for language: " .. language)
		return
	end

	local text_obj_config = lang_config[text_obj_name]
	if not text_obj_config then
		print("No language config for text_obj_name: " .. text_obj_name)
		return
	end

	local query_string = text_obj_config.query

	local ok, query = pcall(vim.treesitter.query.parse, language, query_string)
	if not ok or not query then
		print("Failed to parse Tree-sitter query for " .. language .. " " .. query)
		return
	end

	local capture_name = text_obj_config.capture_name or text_obj_name

	local target_node = nil
	for id, node, _ in query:iter_captures(root, bufnr, cursor_row, cursor_row + 1) do
		if query.captures[id] == capture_name then
			if cursor_in_node_range(cursor_row, cursor_col, node) then
				target_node = node
				-- We do not break here to allow finding the most deeply nested node,
				-- e.g. the most deeply nested function definition
			end
		end
	end

	if target_node then
		local start_row, start_col, end_row, end_col =
			get_treesitter_node_range(target_node, text_obj_config.list_delimiter)

		vim.cmd("normal! \x1b")
		vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
		vim.cmd("normal! v")
		vim.api.nvim_win_set_cursor(0, { end_row + 1, end_col - 1 })
	else
		print("Cursor is not inside a " .. text_obj_name)
	end
end

return M
