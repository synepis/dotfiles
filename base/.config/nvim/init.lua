vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.g.have_nerd_font = true

-- [[ Basic options ]] --
vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.expandtab = true
vim.o.smartindent = true
vim.o.wrap = false
vim.o.breakindent = true
vim.o.number = true
vim.o.mouse = "a"
vim.o.showmode = false
vim.o.undofile = true
vim.o.signcolumn = "yes"
vim.o.winborder = "rounded"

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.o.ignorecase = true
vim.o.smartcase = true

vim.o.updatetime = 250
vim.o.timeoutlen = 300
vim.o.splitright = true
vim.o.splitbelow = true

vim.o.inccommand = "nosplit"

vim.o.cursorline = true
vim.o.scrolloff = 10

vim.o.confirm = true

vim.opt.termguicolors = true

-- Quick replace
vim.keymap.set("n", "R", [[:%s/\<<C-r><C-w>\>/]], { desc = "Search and replace word under cursor" })

-- Enable code folding
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldlevel = 99

-- Sync clipboard between OS and Neovim.
vim.schedule(function()
	vim.o.clipboard = "unnamedplus"
end)

-- Clear highlights on search when pressing <Esc> in normal mode
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Easier escape
vim.keymap.set("i", "jk", "<Esc>", { noremap = true, silent = true })

-- Easier escape from terminal mode
vim.keymap.set("t", "<Space><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

-- Navigation.
vim.keymap.set({ "n", "v", "o" }, "H", "0", { noremap = true, silent = true })
vim.keymap.set({ "n", "v", "o" }, "L", "$", { noremap = true, silent = true })
vim.keymap.set({ "n", "v", "o" }, "J", "<C-d>", { noremap = true, silent = true })
vim.keymap.set({ "n", "v", "o" }, "K", "<C-u>", { noremap = true, silent = true })

-- Remap joining lines (due to navigation using J)
vim.keymap.set({ "n", "v", "o" }, "M", "J", { noremap = true, silent = true })

-- Mouse horizontal scroll
vim.keymap.set("n", "<S-ScrollWheelDown>", "3zl", { noremap = true, silent = true })
vim.keymap.set("n", "<S-ScrollWheelUp>", "3zh", { noremap = true, silent = true })

-- Mouse horizontal scroll
vim.keymap.set("n", "<S-ScrollWheelDown>", "3zl", { noremap = true, silent = true })
vim.keymap.set("n", "<S-ScrollWheelUp>", "3zh", { noremap = true, silent = true })

-- Window movements --
vim.keymap.set({ "n", "v" }, "<leader>wh", "<C-w>h", { noremap = true, silent = true })
vim.keymap.set({ "n", "v" }, "<leader>wj", "<C-w>j", { noremap = true, silent = true })
vim.keymap.set({ "n", "v" }, "<leader>wk", "<C-w>k", { noremap = true, silent = true })
vim.keymap.set({ "n", "v" }, "<leader>wl", "<C-w>l", { noremap = true, silent = true })

-- Nicer indenting
vim.keymap.set("v", ">", ">gv")
vim.keymap.set("v", "<", "<gv")

-- Easier save and quit
vim.keymap.set({ "n", "v" }, "<leader>q", ":q<CR>")
vim.keymap.set({ "n", "v" }, "<leader>Q", ":q!<CR>")
vim.keymap.set({ "n", "v" }, "<leader>ww", ":w<CR>")
vim.keymap.set({ "n", "v" }, "<leader>wa", ":wa<CR>")
vim.keymap.set({ "n", "v" }, "<leader>wq", ":wq<CR>")

-- Switch between alternate buffers (two most recent)
vim.keymap.set({ "n", "v" }, "<leader>a", "<C-^>")

-- Ensure pasting doesn't replace the clipboard
vim.keymap.set("x", "p", [["_dP]])

-- More natual re-do
vim.keymap.set("n", "U", "<C-r>")

-- Windows exchange/swap
vim.keymap.set({ "n", "v" }, "<leader>wx", "<C-w>x")

-- Enable the new VIM UI and hide the command line when not in use
-- require("vim._core.ui2").enable()
-- vim.opt.cmdheight = 0

-- Custom winbar
function _G.custom_winbar()
	local filename = vim.fn.expand("%:t")
	local modified = vim.bo.modified and "[+]" or ""

	local hl = ""
	if vim.api.nvim_get_current_win() == tonumber(vim.g.actual_curwin) then
		hl = "%#StatulLine#"
	else
		hl = "%#StatusLineNC#"
	end

	return hl .. " %f" .. modified .. "%*" -- %t is filename, %* resets the highlight
end

vim.opt.winbar = "%{%v:lua.custom_winbar()%}"

-- Window resizing
local function resize_mode()
	local winnr = vim.fn.winnr()
	local windows = vim.api.nvim_list_wins()
	local is_last_col = vim.fn.winnr("l") == winnr and #windows > 1
	local is_last_row = vim.fn.winnr("j") == winnr and #windows > 1

	-- highligh the resizing window
	vim.api.nvim_set_hl(0, "ResizeModeActive", { bg = "#395075" })

	local current_win = vim.api.nvim_get_current_win()
	local original_winhl = vim.wo[current_win].winhighlight

	local new_winhl = "Normal:ResizeModeActive"
	if original_winhl ~= "" then
		new_winhl = original_winhl .. "," .. new_winhl
	end
	vim.wo[current_win].winhighlight = new_winhl
	vim.cmd("redraw")

    print(original_winhl)

	-- Keybindings for resising
	while true do
		local char = vim.fn.getchar()
		local key = type(char) == "number" and vim.fn.nr2char(char) or char
		local low_key = string.lower(key)

		local inc = key == low_key and "2" or "20"

		if low_key == "h" then
			if is_last_col then
				vim.cmd("vertical resize +" .. inc)
			else
				vim.cmd("vertical resize -" .. inc)
			end
		elseif low_key == "l" then
			if is_last_col then
				vim.cmd("vertical resize -" .. inc)
			else
				vim.cmd("vertical resize +" .. inc)
			end
		elseif low_key == "j" then
			if is_last_row then
				vim.cmd("resize -" .. inc)
			else
				vim.cmd("resize +" .. inc)
			end
		elseif low_key == "k" then
			if is_last_row then
				vim.cmd("resize +" .. inc)
			else
				vim.cmd("resize -" .. inc)
			end
		else
			vim.wo[current_win].winhighlight = original_winhl
			break
		end
		vim.cmd("redraw")
	end
end

vim.keymap.set("n", "<leader>wr", resize_mode, { desc = "Enter window resizing mode" })

-- [[ Basic Autocommands ]]

-- Highlight when yanking (copying) text
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking (copying) text",
	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
	callback = function()
		vim.hl.on_yank()
	end,
})

-- Automatic split resize on OS window resize
vim.api.nvim_create_autocmd("VimResized", {
	command = "wincmd =",
})

-- Show cursor line only in active window [enable]
vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
	group = vim.api.nvim_create_augroup("active_cursorline", { clear = true }),
	callback = function()
		vim.opt_local.cursorline = true
	end,
})

-- Show cursor line only in active window [disable]
vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
	group = "active_cursorline",
	callback = function()
		vim.opt_local.cursorline = false
	end,
})

-- Force a blinking bar cursor in terminal insert mode
vim.api.nvim_create_autocmd("TermEnter", {
	pattern = "term://*",
	callback = function()
		vim.opt_local.guicursor =
			"n-v-c-sm:block,i-ci-ve:ver25-blinkwait300-blinkoff200-blinkon250-Cursor/lCursor,r-cr-o:hor20"
	end,
})

-- [[ Plugins ]]
vim.pack.add({
	{ src = "https://github.com/rebelot/kanagawa.nvim" },
	{ src = "https://github.com/mason-org/mason.nvim" },
	{ src = "https://github.com/stevearc/conform.nvim" },
	{ src = "https://github.com/ibhagwan/fzf-lua" },
	{ src = "https://github.com/nvim-tree/nvim-tree.lua" },
	{ src = "https://github.com/nvim-tree/nvim-web-devicons" },
	{ src = "https://github.com/smoka7/hop.nvim" },
	{ src = "https://github.com/saghen/blink.lib" },
	{ src = "https://github.com/saghen/blink.cmp" },
	{ src = "https://github.com/nvim-mini/mini.pairs" },
	{ src = "https://github.com/nvim-mini/mini.surround" },
	{ src = "https://github.com/nvim-mini/mini.ai" },
	{ src = "https://github.com/lewis6991/gitsigns.nvim" },
	{ src = "https://github.com/mfussenegger/nvim-dap" },
	{ src = "https://github.com/igorlfs/nvim-dap-view", version = vim.version.range("1.*") },
	{ src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
})

-- Treesitter
-- Ensure basic parsers are installed
local parsers = {
	"bash",
	"c",
	"cpp",
	"diff",
	"html",
	"lua",
	"luadoc",
	"markdown",
	"markdown_inline",
	"query",
	"vim",
	"vimdoc",
	"python",
	"jinja",
	"jinja_inline",
}
require("nvim-treesitter").install(parsers)

---@param buf integer
---@param language string
local function treesitter_try_attach(buf, language)
	-- Check if a parser exists and load it
	if not vim.treesitter.language.add(language) then
		return
	end
	-- Enable syntax highlighting and other treesitter features
	local ok, _ = pcall(vim.treesitter.start, buf, language)
	if not ok then
		return
	end

	-- Enable treesitter based folds
	-- For more info on folds see `:help folds`
	-- vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
	-- vim.wo.foldmethod = 'expr'

	-- Check if treesitter indentation is available for this language, and if so enable it
	-- in case there is no indent query, the indentexpr will fallback to the vim's built in one
	local has_indent_query = vim.treesitter.query.get(language, "indents") ~= nil

	-- Enable treesitter based indentation
	if has_indent_query then
		vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end
end

local available_parsers = require("nvim-treesitter").get_available()
vim.api.nvim_create_autocmd("FileType", {
	callback = function(args)
		local buf, filetype = args.buf, args.match

		local language = vim.treesitter.language.get_lang(filetype)
		if not language then
			return
		end

		local installed_parsers = require("nvim-treesitter").get_installed("parsers")

		if vim.tbl_contains(installed_parsers, language) then
			-- Enable the parser if it is already installed
			treesitter_try_attach(buf, language)
		elseif vim.tbl_contains(available_parsers, language) then
			-- If a parser is available in `nvim-treesitter`, auto-install it and enable it after the installation is done
			require("nvim-treesitter").install(language):await(function()
				treesitter_try_attach(buf, language)
			end)
		else
			-- Try to enable treesitter features in case the parser exists but is not available from `nvim-treesitter`
			treesitter_try_attach(buf, language)
		end
	end,
})

-- Mini
require("mini.pairs").setup() -- Auto bracket pairing
require("mini.surround").setup() -- Bracket surrounding
local spec_treesitter = require("mini.ai").gen_spec.treesitter
require("mini.ai").setup({
	custom_textobjects = {
		f = spec_treesitter({ a = "@function.outer", i = "@function.inner" }),
		o = spec_treesitter({
			a = { "@conditional.outer", "@loop.outer" },
			i = { "@conditional.inner", "@loop.inner" },
		}),
	},
})

-- Autocomplete: Blink (you need rust & cargo for this)
local has_blink, blink = pcall(require, "blink.cmp")
if has_blink then
	blink.build():pwait()
	blink.setup({
		keymap = {
			preset = "super-tab",
			["<CR>"] = { "accept", "fallback" },
			["<Tab>"] = { "accept", "fallback" },
			["<Up>"] = { "select_prev", "fallback" },
			["<Down>"] = { "select_next", "fallback" },
			["<C-k>"] = { "select_prev", "fallback" },
			["<C-j>"] = { "select_next", "fallback" },
		},
		sources = {
			default = { "lsp", "path", "snippets", "buffer" },
		},
		completion = {
			documentation = { auto_show = true, auto_show_delay_ms = 200 },
			menu = {
				draw = {
					columns = { { "kind_icon" }, { "label", "label_description", gap = 1 } },
				},
			},
		},
	})
else
	print("Blink not found")
end

-- IMPORTANT: Because Mason installs binaries into a hidden directory,
-- we tell Neovim exactly where to find the execution command.
local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/"

-- LSP: Keymaps (Runs automatically whenever an LSP connects)
vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local opts = { buffer = args.buf }

		-- local picker = require("custom.picker")
		--
		-- vim.keymap.set("n", "gd", picker.find_definitions, opts)
		-- vim.keymap.set("n", "gi", picker.find_implementations, opts)
		-- The most robust way to register it in your LspAttach:
		--
		-- vim.keymap.set("n", "gD", function()
		--  print("Do nothing")
		-- end, opts)
		-- vim.keymap.set("n", "gD", "<cmd>lua require('custom.picker').find_declarations()<CR>", {
		--  buffer = args.buf,
		--  silent = true,
		--  noremap = true,
		-- })
		-- local has_fzf, fzf = pcall(require, "fzf-lua")
		-- if has_fzf then
		--  vim.keymap.set("n", "gd", function()
		--      fzf.lsp_definitions()
		--  end, opts)
		--  vim.keymap.set("n", "gi", function()
		--      fzf.lsp_implementations()
		--  end, opts)
		--  vim.keymap.set("n", "gD", function()
		--      fzf.lsp_declarations()
		--  end, opts)
		--  vim.keymap.set("n", "gt", function()
		--      fzf.lsp_typedefs()
		--  end, opts)
		--
		--  -- vim.keymap.set("n", "<leader>ca", function()
		--  --  fzf.lsp_code_actions()
		--  -- end, opts)
		-- end

		-- Standard way to map code actions in Neovim 0.7+
		vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, {
			buffer = true, -- Set it for the current buffer only (ideally inside an LSP attach event)
			desc = "LSP Code Actions (via custom picker)",
		})
		vim.keymap.set("n", "gh", vim.lsp.buf.hover, opts)
		vim.keymap.set("n", "ge", vim.diagnostic.open_float, { desc = "[G]oto [E]errors" })
		vim.keymap.set("n", "gh", vim.lsp.buf.signature_help, { desc = "[G]oto signature [H]elp" })
		vim.keymap.set("i", "<C-k>", vim.lsp.buf.signature_help, { desc = "[G]oto signature [H]elp" })
		vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
	end,
})

-- LSP: Lua
vim.lsp.config("lua_ls", {
	cmd = { mason_bin .. "lua-language-server" },
	filetypes = { "lua" },
	root_markers = { ".git", "init.lua" },
	settings = {
		Lua = {
			diagnostics = { globals = { "vim" } },
			workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } },
			runtime = { version = "LuaJIT" },
		},
		telemetry = { enable = false },
	},
	capabilities = blink.get_lsp_capabilities(),
})
vim.lsp.enable("lua_ls")

-- LSP: C/C++ (clangd)
vim.lsp.config("clangd", {
	cmd = {
		mason_bin .. "clangd",
		"--background-index", -- Force background indexing
		-- "--clang-tidy", -- Enable linting
		"--header-insertion=iwyu", -- Include What You Use suggestions
		"--completion-style=detailed",
		-- "--fallback-style=llvm",
	},
	filetypes = { "c", "cpp", "objc", "objcpp" },
	root_markers = { ".git", "compile_commands.json", "Makefile" },
	capabilities = blink.get_lsp_capabilities(),
})
vim.lsp.enable("clangd")

-- LSP: Python (pyright)
vim.lsp.config("pyright", {
	cmd = { mason_bin .. "pyright-langserver", "--stdio" },
	filetypes = { "python" },
	root_markers = { ".git", "pyproject.toml", "setup.py", "requirements.txt" },
	capabilities = blink.get_lsp_capabilities(),
	settings = {
		python = {
			analysis = {
				autoSearchPaths = true,
				useLibraryCodeForTypes = true,
				diagnosticMode = "openFilesOnly", -- or "workspace"
				typeCheckingMode = "standard", -- "off" by default, set to "standard" or "strict" for error highlights!
			},
		},
	},
	handlers = {
		-- Override the default rename handler to remove the `annotationId` from edits.
		--
		-- Pyright is being non-compliant here by returning `annotationId` in the edits, but not
		-- populating the `changeAnnotations` field in the `WorkspaceEdit`. This causes Neovim to
		-- throw an error when applying the workspace edit.
		--
		-- See:
		-- - https://github.com/neovim/neovim/issues/34731
		-- - https://github.com/microsoft/pyright/issues/10671
		[vim.lsp.protocol.Methods.textDocument_rename] = function(err, result, ctx)
			if err then
				vim.notify("Pyright rename failed: " .. err.message, vim.log.levels.ERROR)
				return
			end

			---@cast result lsp.WorkspaceEdit
			for _, change in ipairs(result.documentChanges or {}) do
				for _, edit in ipairs(change.edits or {}) do
					if edit.annotationId then
						edit.annotationId = nil
					end
				end
			end

			local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
			vim.lsp.util.apply_workspace_edit(result, client.offset_encoding)
		end,
	},
})
vim.lsp.enable("pyright")

-- LSP: Go (gopls)
vim.lsp.config("gopls", {
	cmd = { mason_bin .. "gopls" },
	filetypes = { "go", "gomod", "gowork", "gotmpl" },
	root_markers = { ".git", "go.work", "go.mod" },
	capabilities = blink.get_lsp_capabilities(),
})
vim.lsp.enable("gopls")

-- LSP: typst (tinymist)
vim.lsp.config("tinymist", {
	cmd = { "tinymist" },
	filetypes = { "typst" },
	root_markers = { ".git" },
	capabilities = blink.get_lsp_capabilities(),
	settings = {
		exportPdf = "onSave",
		formatterMode = "typstyle",
	},
})
vim.lsp.enable("tinymist")

vim.lsp.config("html", {
	cmd = { mason_bin .. "vscode-html-language-server", "--stdio" },
	filetypes = { "html", "jinja" }, -- Add "jinja" here
	root_markers = { ".git" },
	init_options = {
		provideFormatter = true,
		embeddedLanguages = {
			css = true,
			javascript = true,
		},
		configurationSection = { "html", "css", "javascript" },
	},
	capabilities = blink.get_lsp_capabilities(),
})
vim.lsp.enable("html")

vim.lsp.config("ts_ls", {
	cmd = { mason_bin .. "typescript-language-server", "--stdio" },
	filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "jinja" },
	root_markers = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },
	capabilities = blink.get_lsp_capabilities(),
})
vim.lsp.enable("ts_ls")

--
-- Color Scheme
require("kanagawa").setup()
vim.cmd.colorscheme("kanagawa")
-- Light theme: vim.cmd.colorscheme("kanagawa-lotus")

-- Formatting
require("conform").setup({
	formatters_by_ft = {
		lua = { "stylua" },
		python = { "ruff_organize_imports", "ruff_format" },
		html = { "prettier" },
		css = { "prettier" },
		javascript = { "prettier" },
		markdown = { "prettier" },
		typescript = { "prettier" },
		jinja = { "djlint" },
		sql = { "sql_formatter" },
	},
	formatters = {
		prettier = {
			inherit = false,
			command = "prettier",
			args = function(_, _)
				return {
					"--stdin-filepath",
					"$FILENAME",
					"--print-width",
					"100",
					"--prose-wrap",
					"always",
				}
			end,
		},
		djlint = {
			prepend_args = {
				"--line-break-after-multiline-tag",
				"--max-attribute-length",
				"3",
			},
		},
	},
})

vim.keymap.set("n", "<leader>cf", function()
	require("conform").format({
		lsp_format = "fallback",
		async = true,
	})
end, { desc = "[C]ode [F]ormat" })

-- Mason: External binary management
vim.api.nvim_create_autocmd("VimEnter", {
	desc = "Initialize external binary management",
	callback = function()
		local has_mason, mason = pcall(require, "mason")
		if has_mason then
			mason.setup()
		end
	end,
})

-- Picker: fzf
local has_fzf, fzf = pcall(require, "fzf-lua")
if has_fzf then
	fzf.setup({
		"fzf-native",
		fzf_opts = {
			-- 🔑 Added 'enter:accept' to the very end of your custom bind string!
			["--bind"] = "vi,ctrl-g:change-mode,j:down,k:up,G:last,g:first,enter:accept",
		},
		keymap = {
			["ctrl-g"] = "change-mode",
		},
		winopts = {
			preview = {
				layout = "vertical",
				vertical = "down:50%",
			},
		},
	})

	vim.keymap.set("n", "<leader>jf", function()
		fzf.files()
	end, { desc = "[F]ind [F]iles" })
	vim.keymap.set("n", "<leader>jg", function()
		fzf.live_grep()
	end, { desc = "[F]ind [G]rep" })
	vim.keymap.set("n", "<leader>jo", function()
		fzf.buffers()
	end, { desc = "[F]ind [O]pen Buffers" })
	vim.keymap.set("n", "<leader>jd", function()
		fzf.diagnostics_document()
	end, { desc = "[F]ind [D]iagnostics" })
	vim.keymap.set("n", "<leader>jr", function()
		fzf.lsp_references()
	end, { desc = "[F]ind [R]eferences" })
	vim.keymap.set("n", "<leader>js", function()
		fzf.lsp_document_symbols()
	end, { desc = "[F]ind [S]ymbols" })

	-- fzf.register_ui_select()
end

-- File Exploreer: nvim-tree
require("nvim-tree").setup({
	-- Disables netrw (built-in explorer) to avoid conflicts
	disable_netrw = true,
	hijack_netrw = true,

	-- Better visual experience
	view = {
		width = 35,
		relativenumber = false, -- Great for jumping around with 5j, 10k
	},
	renderer = {
		group_empty = true,
		highlight_opened_files = "all",
	},
	filters = {
		dotfiles = false, -- Set to true if you want to hide .gitignore, .ds_store, etc.
	},
	actions = {
		open_file = {
			resize_window = true,
		},
	},
	git = {
		ignore = false, -- Show .gitignore-d files
	},
})

-- Toggle the tree: <leader>e (e for Explorer)
vim.keymap.set("n", "<leader>we", ":NvimTreeToggle<CR>", { desc = "[W]indow [E]xplorer Toggle" })

-- Focus the tree: <leader>ef (e for explorer, f for focus)
-- Useful if you're in a file and want to jump back to the tree without toggling it
vim.keymap.set("n", "<leader>fe", ":NvimTreeFindFile<CR>", { desc = "[F]ind in [E]" })

-- DAP
local dap = require("dap")
-- Helper function to make defining keymaps cleaner
local function map(mode, lhs, rhs, desc)
	vim.keymap.set(mode, lhs, rhs, { silent = true, desc = "DAP: " .. desc })
end

-- ==========================================
-- 1. Execution & Flow Control
-- ==========================================
-- Start debugging or jump to the next breakpoint
map("n", "<F5>", dap.continue, "Start / Continue Debugging")
-- Step OVER a line of code (execute it, but don't drop inside its function)
map("n", "<F10>", dap.step_over, "Step Over")
-- Step INTO a function call to debug what's inside it
map("n", "<F11>", dap.step_into, "Step Into")
-- Step OUT of the current function back to where it was called
map("n", "<F12>", dap.step_out, "Step Out")

-- ==========================================
-- 2. Breakpoint Management
-- ==========================================
-- Toggle a red-dot breakpoint on the current line
map("n", "<leader>db", dap.toggle_breakpoint, "Toggle Breakpoint")
-- Clear all active breakpoints in the current workspace
map("n", "<leader>dc", dap.clear_breakpoints, "Clear All Breakpoints")

-- ==========================================
-- 3. Inspection & State (Great for Math!)
-- ==========================================
-- Hover over a variable (like a Vector3 or Matrix) to see its current value instantly
map("n", "<leader>dh", function()
	require("dap.ui.widgets").hover()
end, "Hover Variable Value")

-- local dapui = require("dapui")
-- map("n", "<leader>du", dapui.toggle, "[D]ebug [U]I Toggle")

dap.adapters.python = function(callback, config)
	if config.request == "launch" then
		callback({
			type = "executable",
			command = os.getenv("VIRTUAL_ENV") and (os.getenv("VIRTUAL_ENV") .. "/bin/python") or "python3",
			args = { "-m", "debugpy.adapter" },
		})
	end
end

dap.configurations.python = {
	{
		type = "python",
		request = "launch",
		name = "Launch Current File (Active Venv)",
		program = "${file}",
		pythonPath = function()
			local cwd = vim.fn.getcwd()
			if vim.fn.executable(cwd .. "/.venv/bin/python") == 1 then
				return cwd .. "/.venv/bin/python"
			else
				return "/usr/bin/python3"
			end
		end,
		console = "externalTerminal",
	},
}

-- Jumper: hop.nivm
local hop = require("hop")
local hop_treesitter = require("hop-treesitter")
hop.setup({
	-- keys = "etovxqpdygfblzhckisuran", -- Customize your hinting keys here
	keys = "wertyuiopasdfghjklcvnmx", -- Customize your hinting keys here
	multi_windows = true,
})

-- Test Cases: camelCase test_PascalCase snake_case 0.12 -0.23 A AA       b  b 1 123
vim.keymap.set({ "n", "v", "o" }, ";", function()
	hop.hint_patterns({
		callback = function(target)
			print("blah")
			if target == " " then
				hop.hint_lines()
			end
		end,
	}, "\\v[a-z]+|[A-Z]+|[A-Z][A-Z]+|[A-Z][a-z]+|[0-9][0-9\\.]+")
end, { desc = "Hop Word" })
vim.keymap.set({ "n", "v", "o" }, "<leader>;l", hop.hint_lines, { desc = "Hop Word" })
vim.keymap.set({ "n", "v", "o" }, "<leader>;n", hop_treesitter.hint_nodes, { desc = "Hop Node" })

-- Floating terminal (custom)
require("custom.floaterm").setup()

vim.keymap.set({ "n", "t" }, "<leader>wt", "<cmd>FloaTermToggle<CR>", { desc = "Toggle [W]indow [T]erminal" })
vim.keymap.set({ "n", "t" }, "<C-Space>", "<cmd>FloaTermToggle<CR>", { desc = "Toggle [W]indow [T]erminal" })
vim.keymap.set({ "t" }, "<leader>q", "<cmd>close<CR>", { desc = "Quit window in terminal mode" })
vim.keymap.set({ "n" }, "<leader>fq", "<cmd>FloaTermQuickfix<CR>", { desc = "[F]ind [Q]uickfix" })

-- Text Objects
-- local text_objects = require("custom.text_objects")
--
-- vim.keymap.set({ "x", "o" }, "ic", function()
--  text_objects.select_text_object("function_call")
-- end, { desc = "Select function call" })
--
-- vim.keymap.set({ "x", "o" }, "ac", function()
--  text_objects.select_text_object("function_call")
-- end, { desc = "Select function call" })
--
-- vim.keymap.set({ "x", "o" }, "if", function()
--  text_objects.select_text_object("function_inner")
-- end, { desc = "Select inner arguments" })
--
-- vim.keymap.set({ "x", "o" }, "af", function()
--  text_objects.select_text_object("function_outer")
-- end, { desc = "Select outer arguments" })
--
-- vim.keymap.set({ "x", "o" }, "ia", function()
--  text_objects.select_text_object("parameter_inner")
-- end, { desc = "Select inner arguments" })
--
-- vim.keymap.set({ "x", "o" }, "aa", function()
--  text_objects.select_text_object("parameter_outer")
-- end, { desc = "Select outer arguments" })
--
vim.keymap.set("n", "<leader>rs", ":source %<CR>", { desc = "Source this file" })

---
local function load_picker_plugin()
	-- 1. Clear the cached module so Neovim looks at the file on disk again
	package.loaded["custom.picker"] = nil

	-- 2. Re-require and setup
	local status, picker = pcall(require, "custom.picker")
	if status then
		picker.setup()
		vim.keymap.set("n", "<leader>ft", function()
			require("custom.picker").ui_select({
				"Apples",
				"Apples 2",
				"Apples 3",
				"Blah Apples",
				"Blah Apples 2",
				"Blah Apples 3",
				"Cherries",
				"Bananas",
			}, {}, function(item, idx)
				print("Selected: " .. vim.inspect(item) .. ", " .. vim.inspect(idx))
			end)
		end, { desc = "Custom picker" })

		vim.keymap.set("n", "<leader>kt", function()
			local items = {
				"Apples",
				"Apples 2",
				"Apples 3",
				"Blah Apples",
				"Blah Apples 2",
				"Blah Apples 3",
				"Cherries",
				"Bananas",
			}
			require("custom.picker").generic_select(items, {
				prompt = "Choose something",
				on_action = {
					["<CR>"] = function(items)
						print("selected: " .. vim.inspect(items))
					end,
				},
			})
		end, { desc = "Custom picker" })

		vim.keymap.set("n", "<leader>fs", function()
			require("custom.picker").find_symbols()
		end, { desc = "[F]ind [S]ymbols" })

		vim.keymap.set("n", "<leader>fd", function()
			require("custom.picker").find_diagnostics()
		end, { desc = "[F]ind [D]iagnostics" })

		vim.keymap.set("n", "<leader>ff", function()
			require("custom.picker").find_files()
		end, { desc = "[F]ind [F]iles" })

		vim.keymap.set("n", "<leader>fg", function()
			require("custom.picker").live_grep()
		end, { desc = "[F]ind Live [G]rep" })

		vim.keymap.set("n", "<leader>fo", function()
			require("custom.picker").find_buffers()
		end, { desc = "[F]ind [O]pen Buffers" })

		vim.keymap.set("n", "<leader>fu", function()
			require("custom.picker").find_references()
		end, { desc = "[F]ind [U]sages" })

		vim.keymap.set("n", "gd", picker.find_definitions, {})
		vim.keymap.set("n", "gi", picker.find_implementations, {})
		vim.keymap.set("n", "gD", picker.find_declarations, {})
		vim.keymap.set("n", "gt", picker.find_typedefs, {})
	else
		vim.notify("Failed to reload picker: " .. tostring(picker), vim.log.levels.ERROR)
	end
end
load_picker_plugin()

-- Custom Status Line
local function load_statustline_plugin()
	package.loaded["custom.statusline"] = nil

	local status, statusline = pcall(require, "custom.statusline")
	if status then
		statusline.setup()
	else
		vim.notify("Failed to reload picker: " .. tostring(statusline), vim.log.levels.ERROR)
	end
end
load_statustline_plugin()

vim.keymap.set("n", "<leader>rp", load_statustline_plugin, { desc = "reload plugin" })

-- Typst and Zathura utility
vim.keymap.set("n", "<leader>rt", function()
	local file = vim.api.nvim_buf_get_name(0)

	if not file:match("%.typ$") then
		vim.notify("Current buffer is not a .typ file", vim.log.levels.WARN)
		return
	end

	local pdf = file:gsub("%.typ$", ".pdf")

	local file_esc = vim.fn.shellescape(file)
	local pdf_esc = vim.fn.shellescape(pdf)

	-- Run typst watch to live-update the pdf
	-- Run zathura to render the pdf
	-- Make sure when zathura is closed the typst watch is also closed
	local cmd = string.format("typst watch %s & PID=$! ; zathura %s ; kill $PID", file_esc, pdf_esc)

	vim.fn.jobstart({ "sh", "-c", cmd }, { detach = true })

	vim.notify("Started Typst & Zathura", vim.log.levels.INFO)
end, { desc = "[R]un [T]ypst watch and Zathura" })
