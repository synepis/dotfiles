vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.g.have_nerd_font = true

-- [[ Basic options ]] --
vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.expandtab = false
vim.o.smartindent = true
vim.o.wrap = false
vim.o.breakindent = true
vim.o.number = true
vim.o.mouse = "a"
vim.o.showmode = false
vim.o.undofile = true
vim.o.signcolumn = "yes"
vim.o.winborder = "rounded"

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

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.o.ignorecase = true
vim.o.smartcase = true

vim.o.updatetime = 250
vim.o.timeoutlen = 300
vim.o.splitright = true
vim.o.splitbelow = true

vim.o.inccommand = "split"

vim.o.cursorline = true
vim.o.scrolloff = 10

vim.o.confirm = true

-- Sync clipboard between OS and Neovim.
vim.schedule(function()
	vim.o.clipboard = "unnamedplus"
end)

-- [[ Basic Keymaps ]]

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

-- Nicer indendting
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

-- -- Special quit (by default close buffers, if last buffer then quit)
-- vim.keymap.set({ "n", "v" }, "<leader>q", function()
-- 	-- Count how many windows are open in the current tab
-- 	local tab_wins = vim.api.nvim_tabpage_list_wins(0)
--
-- 	if #tab_wins > 1 then
-- 		local win = vim.api.nvim_get_current_win()
-- 		print("Branch1")
-- 		vim.api.nvim_win_close(win, false)
-- 	else
-- 		print("Branch2")
-- 		local listed_buffers = vim.fn.getbufinfo({ buflisted = 1 })
-- 		print(vim.inspect(listed_buffers))
-- 		if #listed_buffers > 1 then
-- 			vim.cmd("bdelete")
-- 		else
-- 			vim.cmd("quit")
-- 		end
-- 	end
-- end, { desc = "Close buffer" })

-- Ensure pasting doesn't replace the clipboard
vim.keymap.set("x", "p", [["_dP]])

-- More natual re-do
vim.keymap.set("n", "U", "<C-r>")

-- Windows exchange/swap
vim.keymap.set({ "n", "v" }, "<leader>wx", "<C-w>x")

-- Window resizing
local function resize_mode()
	print("-- Window Resize Active -- ")

	local winnr = vim.fn.winnr()
	local windows = vim.api.nvim_list_wins()
	local is_last_col = vim.fn.winnr("l") == winnr and #windows > 1
	local is_last_row = vim.fn.winnr("j") == winnr and #windows > 1

	while true do
		local char = vim.fn.getchar()
		local key = vim.fn.nr2char(char)

		if key == "h" then
			if is_last_col then
				vim.cmd("vertical resize +2")
			else
				vim.cmd("vertical resize -2")
			end
		elseif key == "l" then
			if is_last_col then
				vim.cmd("vertical resize -2")
			else
				vim.cmd("vertical resize +2")
			end
		elseif key == "j" then
			if is_last_row then
				vim.cmd("resize -2")
			else
				vim.cmd("resize +2")
			end
		elseif key == "k" then
			if is_last_row then
				vim.cmd("resize +2")
			else
				vim.cmd("resize -2")
			end
		else
			print("-- Widow Resize Stopped --")
			break
		end
		vim.cmd("redraw")
	end
end

vim.keymap.set("n", "<leader>wr", resize_mode, { desc = "Enter window resizing mode" })

-- Project Build Release
vim.keymap.set(
	"n",
	"<leader>pB",
	":!cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build\n",
	{ desc = "[P]project [B]uild Release" }
)

-- Project Build Debug
vim.keymap.set(
	"n",
	"<leader>pb",
	":!cmake -B build -DCMAKE_BUILD_TYPE=Debug && cmake --build build\n",
	{ desc = "[P]project [B]uild Debug" }
)

-- File Explorer
vim.g.loaded_netrw = 1 -- disble netrw since we use nvim-tree below
vim.g.loaded_netrwPlugin = 1

-- vim.keymap.set("n", "<leader>we", vim.cmd.Lexplore, { desc = "Open [W]indow [E]xplorer", silent = true })
-- vim.keymap.set("n", "<leader>fe", function()
-- 	local current_file = vim.fn.expand("%:t")
-- 	local current_dir = vim.fn.expand("%:p:h")
-- 	vim.cmd("Lexplore " .. current_dir)
-- 	pcall(function()
-- 		vim.fn.search("\\<" .. current_file)
-- 	end)
-- end, { desc = "[F]ind in [E]xplorer" })

-- Diagnostics
vim.keymap.set("n", "<leader>wd", vim.diagnostic.setqflist, { desc = "Open [W]indow [D]iagnostics" })

-- [[ Basic Autocommands ]]

-- Highlight when yanking (copying) text
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking (copying) text",
	group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
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

-- Automatically set the root dir when starting vim.
-- Try to find any "root" type directory,
-- otherwise  set it to the opened buffer directory
-- vim.api.nvim_create_autocmd("VimEnter", {
-- 	callback = function()
-- 		local bufname = vim.api.nvim_buf_get_name(0)
-- 		local bufdir = ""
-- 		print(bufname)
-- 		print(vim.inspect(vim.uv.fs_stat(bufname)))
-- 		if vim.uv.fs_stat(bufname).type == "directory" then
-- 			bufdir = bufname
-- 		else
-- 			bufdir = vim.fs.dirname(bufname)
-- 		end
--
-- 		local rootdirs = vim.fs.find({ ".git", ".nvim" }, { path = bufdir, type = "directory", upward = true })
-- 		local rootdir = vim.fs.dirname(rootdirs[1]) or bufdir
--
-- 		vim.fn.chdir(rootdir)
-- 	end,
-- })

-- [[ lazy.nvim ]] --
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		error("Error cloning lazy.nvim:\n" .. out)
	end
end

---@type vim.Option
local rtp = vim.opt.rtp
rtp:prepend(lazypath)

-- [[ Plugins ]]

require("lazy").setup({
	"NMAC427/guess-indent.nvim",
	{
		"lewis6991/gitsigns.nvim",
		opts = {
			signs = {
				add = { text = "+" },
				change = { text = "~" },
				delete = { text = "_" },
				topdelete = { text = "‾" },
				changedelete = { text = "~" },
			},
		},
	},
	{
		"folke/which-key.nvim",
		event = "VimEnter", -- Sets the loading event to 'VimEnter'
		opts = {
			-- delay between pressing a key and opening which-key (milliseconds)
			-- this setting is independent of vim.o.timeoutlen
			delay = 500,
			icons = {
				-- set icon mappings to true if you have a Nerd Font
				mappings = vim.g.have_nerd_font,
				keys = vim.g.have_nerd_font and {} or {
					Up = "<Up> ",
					Down = "<Down> ",
					Left = "<Left> ",
					Right = "<Right> ",
					C = "<C-…> ",
					M = "<M-…> ",
					D = "<D-…> ",
					S = "<S-…> ",
					CR = "<CR> ",
					Esc = "<Esc> ",
					ScrollWheelDown = "<ScrollWheelDown> ",
					ScrollWheelUp = "<ScrollWheelUp> ",
					NL = "<NL> ",
					BS = "<BS> ",
					Space = "<Space> ",
					Tab = "<Tab> ",
					F1 = "<F1>",
					F2 = "<F2>",
					F3 = "<F3>",
					F4 = "<F4>",
					F5 = "<F5>",
					F6 = "<F6>",
					F7 = "<F7>",
					F8 = "<F8>",
					F9 = "<F9>",
					F10 = "<F10>",
					F11 = "<F11>",
					F12 = "<F12>",
				},
			},

			-- Document existing key chains
			spec = {
				{ "<leader>s", group = "[S]earch" },
				{ "<leader>f", group = "[F]ind" },
				{ "<leader>t", group = "[T]oggle" },
				{ "<leader>h", group = "Git [H]unk", mode = { "n", "v" } },
			},
		},
	},
	{
		"nvim-telescope/telescope.nvim",
		event = "VimEnter",
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = "make",
				cond = function()
					return vim.fn.executable("make") == 1
				end,
			},
			{ "nvim-telescope/telescope-ui-select.nvim" },
			{ "nvim-tree/nvim-web-devicons", enabled = vim.g.have_nerd_font },
		},
		config = function()
			-- [[ Configure Telescope ]]
			local actions = require("telescope.actions")
			require("telescope").setup({
				-- You can put your default mappings / updates / etc. in here
				--  All the info you're looking for is in `:help telescope.setup()`
				--
				-- defaults = {
				--   mappings = {
				--     i = { ['<c-enter>'] = 'to_fuzzy_refine' },
				--   },
				-- },
				-- pickers = {}
				defaults = {
					layout_strategy = "vertical",
					mappings = {
						i = { ["<S-CR>"] = actions.select_vertical },
						n = { ["<S-CR>"] = actions.select_vertical },
					},
					layout_config = {
						vertical = {
							mirror = true,
							prompt_position = "top",
						},
						width = 0.8,
						height = 0.9,
						preview_cutoff = 1,
					},
					sorting_strategy = "ascending",
					file_ignore_patterns = {
						"%.git/",
						"node_modules/",
						"zig%-cache/",
						"zig%-out/",
					},
				},
				pickers = {
					find_files = {
						hidden = true,
					},
					buffers = {
						mappings = {
							i = { ["<C-d>"] = actions.delete_buffer },
							n = { ["d"] = actions.delete_buffer },
						},
					},
				},
				extensions = {
					["ui-select"] = {
						require("telescope.themes").get_dropdown(),
					},
				},
			})

			-- Enable Telescope extensions if they are installed
			pcall(require("telescope").load_extension, "fzf")
			pcall(require("telescope").load_extension, "ui-select")

			-- See `:help telescope.builtin`
			local builtin = require("telescope.builtin")
			vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "[F]ind [H]elp" })
			vim.keymap.set("n", "<leader>fk", builtin.keymaps, { desc = "[F]ind [K]eymaps" })
			vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "[F]ind [F]iles" })
			vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "[F]ind [G]rep" })
			vim.keymap.set("n", "<leader>fo", builtin.buffers, { desc = "[F]ind [O]pen Files" })
			vim.keymap.set("n", "<leader>fd", builtin.diagnostics, { desc = "[F]ind [D]iagnostics" })
			vim.keymap.set("n", "<leader>f.", builtin.oldfiles, { desc = '[F]ind Recent Files ("." for repeat)' })
			vim.keymap.set("n", "<leader>fs", function()
				builtin.lsp_document_symbols({ symbols = { "function", "method", "class", "struct" } })
			end, { desc = "[F]ind [D]iagnostics" })

			-- Slightly advanced example of overriding default behavior and theme
			vim.keymap.set("n", "<leader>/", function()
				-- You can pass additional configuration to Telescope to change the theme, layout, etc.
				builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
					winblend = 10,
					previewer = false,
				}))
			end, { desc = "[/] Fuzzily search in current buffer" })

			-- It's also possible to pass additional configuration options.
			--  See `:help telescope.builtin.live_grep()` for information about particular keys
			vim.keymap.set("n", "<leader>s/", function()
				builtin.live_grep({
					grep_open_files = true,
					prompt_title = "Live Grep in Open Files",
				})
			end, { desc = "[S]earch [/] in Open Files" })

			-- Shortcut for searching your Neovim configuration files
			vim.keymap.set("n", "<leader>sn", function()
				builtin.find_files({ cwd = vim.fn.stdpath("config") })
			end, { desc = "[S]earch [N]eovim files" })
		end,
	},

	-- LSP Plugins
	{
		-- `lazydev` configures Lua LSP for your Neovim config, runtime and plugins
		-- used for completion, annotations and signatures of Neovim apis
		"folke/lazydev.nvim",
		ft = "lua",
		opts = {
			library = {
				-- Load luvit types when the `vim.uv` word is found
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
			},
		},
	},
	{
		-- Main LSP Configuration
		"neovim/nvim-lspconfig",
		dependencies = {
			-- Automatically install LSPs and related tools to stdpath for Neovim
			-- Mason must be loaded before its dependents so we need to set it up here.
			-- NOTE: `opts = {}` is the same as calling `require('mason').setup({})`
			{ "mason-org/mason.nvim", opts = {} },
			"mason-org/mason-lspconfig.nvim",
			"WhoIsSethDaniel/mason-tool-installer.nvim",

			-- Useful status updates for LSP.
			{ "j-hui/fidget.nvim", opts = {} },

			-- Allows extra capabilities provided by blink.cmp
			"saghen/blink.cmp",
		},
		config = function()
			-- Brief aside: **What is LSP?**
			--
			-- LSP is an initialism you've probably heard, but might not understand what it is.
			--
			-- LSP stands for Language Server Protocol. It's a protocol that helps editors
			-- and language tooling communicate in a standardized fashion.
			--
			-- In general, you have a "server" which is some tool built to understand a particular
			-- language (such as `gopls`, `lua_ls`, `rust_analyzer`, etc.). These Language Servers
			-- (sometimes called LSP servers, but that's kind of like ATM Machine) are standalone
			-- processes that communicate with some "client" - in this case, Neovim!
			--
			-- LSP provides Neovim with features like:
			--  - Go to definition
			--  - Find references
			--  - Autocompletion
			--  - Symbol Search
			--  - and more!
			--
			-- Thus, Language Servers are external tools that must be installed separately from
			-- Neovim. This is where `mason` and related plugins come into play.
			--
			-- If you're wondering about lsp vs treesitter, you can check out the wonderfully
			-- and elegantly composed help section, `:help lsp-vs-treesitter`

			--  This function gets run when an LSP attaches to a particular buffer.
			--    That is to say, every time a new file is opened that is associated with
			--    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
			--    function will be executed to configure the current buffer
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("kickstart-lsp-attach", { clear = true }),
				callback = function(event)
					-- NOTE: Remember that Lua is a real programming language, and as such it is possible
					-- to define small helper and utility functions so you don't have to repeat yourself.
					--
					-- In this case, we create a function that lets us more easily define mappings specific
					-- for LSP related items. It sets the mode, buffer and description for us each time.
					local map = function(keys, func, desc, mode)
						mode = mode or "n"
						vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
					end

					-- Rename the variable under your cursor.
					--  Most Language Servers support renaming across files, etc.
					map("<leader>rn", vim.lsp.buf.rename, "[R]e[n]ame")

					-- Execute a code action, usually your cursor needs to be on top of an error
					-- or a suggestion from your LSP for this to activate.
					map("gra", vim.lsp.buf.code_action, "[G]oto Code [A]ction", { "n", "x" })

					-- Find references for the word under your cursor. (Find usages)
					map("<leader>fu", require("telescope.builtin").lsp_references, "[F]ind [U]sages")

					-- Jump to the implementation of the word under your cursor.
					--  Useful when your language has ways of declaring types without an actual implementation.
					map("gi", require("telescope.builtin").lsp_implementations, "[G]oto [I]mplementation")

					-- Jump to the definition of the word under your cursor.
					--  This is where a variable was first declared, or where a function is defined, etc.
					--  To jump back, press <C-t>.
					map("gd", require("telescope.builtin").lsp_definitions, "[G]oto [D]efinition")

					-- WARN: This is not Goto Definition, this is Goto Declaration.
					--  For example, in C this would take you to the header.
					map("gD", vim.lsp.buf.declaration, "[G]oto [D]eclaration")

					-- Fuzzy find all the symbols in your current document.
					--  Symbols are things like variables, functions, types, etc.
					map("gO", require("telescope.builtin").lsp_document_symbols, "Open Document Symbols")

					-- Fuzzy find all the symbols in your current workspace.
					--  Similar to document symbols, except searches over your entire project.
					map("gW", require("telescope.builtin").lsp_dynamic_workspace_symbols, "Open Workspace Symbols")

					-- Jump to the type of the word under your cursor.
					--  Useful when you're not sure what type a variable is and you want to see
					--  the definition of its *type*, not where it was *defined*.
					map("gt", require("telescope.builtin").lsp_type_definitions, "[G]oto [T]ype Definition")

					-- Help/documentation for the current line
					map("gh", vim.lsp.buf.hover, "[G]oto [H]over")

					-- Show diagnostic error
					map("ge", vim.diagnostic.open_float, "[G]oto [E]rror")

					-- Signature help
					map("gH", vim.lsp.buf.signature_help, "[G]oto signature [H]elp")

					-- This function resolves a difference between neovim nightly (version 0.11) and stable (version 0.10)
					---@param client vim.lsp.Client
					---@param method vim.lsp.protocol.Method
					---@param bufnr? integer some lsp support methods only in specific files
					---@return boolean
					local function client_supports_method(client, method, bufnr)
						if vim.fn.has("nvim-0.11") == 1 then
							return client:supports_method(method, bufnr)
						else
							return client.supports_method(method, { bufnr = bufnr })
						end
					end

					-- The following two autocommands are used to highlight references of the
					-- word under your cursor when your cursor rests there for a little while.
					--    See `:help CursorHold` for information about when this is executed
					--
					-- When you move your cursor, the highlights will be cleared (the second autocommand).
					local client = vim.lsp.get_client_by_id(event.data.client_id)
					if
						client
						and client_supports_method(
							client,
							vim.lsp.protocol.Methods.textDocument_documentHighlight,
							event.buf
						)
					then
						local highlight_augroup =
							vim.api.nvim_create_augroup("kickstart-lsp-highlight", { clear = false })
						vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
							buffer = event.buf,
							group = highlight_augroup,
							callback = vim.lsp.buf.document_highlight,
						})

						vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
							buffer = event.buf,
							group = highlight_augroup,
							callback = vim.lsp.buf.clear_references,
						})

						vim.api.nvim_create_autocmd("LspDetach", {
							group = vim.api.nvim_create_augroup("kickstart-lsp-detach", { clear = true }),
							callback = function(event2)
								vim.lsp.buf.clear_references()
								vim.api.nvim_clear_autocmds({ group = "kickstart-lsp-highlight", buffer = event2.buf })
							end,
						})
					end

					-- The following code creates a keymap to toggle inlay hints in your
					-- code, if the language server you are using supports them
					--
					-- This may be unwanted, since they displace some of your code
					if
						client
						and client_supports_method(client, vim.lsp.protocol.Methods.textDocument_inlayHint, event.buf)
					then
						map("<leader>th", function()
							vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = event.buf }))
						end, "[T]oggle Inlay [H]ints")
					end
				end,
			})

			-- Diagnostic Config
			-- See :help vim.diagnostic.Opts
			vim.diagnostic.config({
				severity_sort = true,
				float = { border = "rounded", source = "if_many" },
				underline = { severity = vim.diagnostic.severity.ERROR },
				signs = vim.g.have_nerd_font and {
					text = {
						[vim.diagnostic.severity.ERROR] = "󰅚 ",
						[vim.diagnostic.severity.WARN] = "󰀪 ",
						[vim.diagnostic.severity.INFO] = "󰋽 ",
						[vim.diagnostic.severity.HINT] = "󰌶 ",
					},
				} or {},
				virtual_text = {
					source = "if_many",
					spacing = 2,
					format = function(diagnostic)
						local diagnostic_message = {
							[vim.diagnostic.severity.ERROR] = diagnostic.message,
							[vim.diagnostic.severity.WARN] = diagnostic.message,
							[vim.diagnostic.severity.INFO] = diagnostic.message,
							[vim.diagnostic.severity.HINT] = diagnostic.message,
						}
						return diagnostic_message[diagnostic.severity]
					end,
				},
			})

			-- LSP servers and clients are able to communicate to each other what features they support.
			--  By default, Neovim doesn't support everything that is in the LSP specification.
			--  When you add blink.cmp, luasnip, etc. Neovim now has *more* capabilities.
			--  So, we create new capabilities with blink.cmp, and then broadcast that to the servers.
			local capabilities = require("blink.cmp").get_lsp_capabilities()

			-- Enable the following language servers
			--  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
			--
			--  Add any additional override configuration in the following tables. Available keys are:
			--  - cmd (table): Override the default command used to start the server
			--  - filetypes (table): Override the default list of associated filetypes for the server
			--  - capabilities (table): Override fields in capabilities. Can be used to disable certain LSP features.
			--  - settings (table): Override the default settings passed when initializing the server.
			--        For example, to see the options for `lua_ls`, you could go to: https://luals.github.io/wiki/settings/
			local servers = {
				clangd = {
					cmd = {
						"clangd",
						"--clang-tidy",
						"--compile-commands-dir=build",
						"--background-index",
						"--header-insertion=iwyu",
					},
				},
				zls = {
					settings = {
						zls = {
							zig_exe_path = "/usr/bin/zig",
							enable_snippets = true,
							warn_style = true,
						},
					},
				},
				gopls = {},
				-- pyright = {},
				-- rust_analyzer = {},
				-- ... etc. See `:help lspconfig-all` for a list of all the pre-configured LSPs
				--
				-- Some languages (like typescript) have entire language plugins that can be useful:
				--    https://github.com/pmizio/typescript-tools.nvim
				--
				-- But for many setups, the LSP (`ts_ls`) will work just fine
				-- ts_ls = {},
				--

				lua_ls = {
					-- cmd = { ... },
					-- filetypes = { ... },
					-- capabilities = {},
					settings = {
						Lua = {
							completion = {
								callSnippet = "Replace",
							},
							-- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
							-- diagnostics = { disable = { 'missing-fields' } },
						},
					},
				},
				ts_ls = {},
				html = {},
			}

			-- Ensure the servers and tools above are installed
			--
			-- To check the current status of installed tools and/or manually install
			-- other tools, you can run
			--    :Mason
			--
			-- You can press `g?` for help in this menu.
			--
			-- `mason` had to be setup earlier: to configure its options see the
			-- `dependencies` table for `nvim-lspconfig` above.
			--
			-- You can add other tools here that you want Mason to install
			-- for you, so that they are available from within Neovim.
			local ensure_installed = vim.tbl_keys(servers or {})
			vim.list_extend(ensure_installed, {
				"stylua", -- Used to format Lua code
			})
			require("mason-tool-installer").setup({ ensure_installed = ensure_installed })

			require("mason-lspconfig").setup({
				ensure_installed = {}, -- explicitly set to an empty table (Kickstart populates installs via mason-tool-installer)
				automatic_installation = false,
				handlers = {
					function(server_name)
						local server = servers[server_name] or {}
						-- This handles overriding only values explicitly passed
						-- by the server configuration above. Useful when disabling
						-- certain features of an LSP (for example, turning off formatting for ts_ls)
						server.capabilities = vim.tbl_deep_extend("force", {}, capabilities, server.capabilities or {})
						require("lspconfig")[server_name].setup(server)
					end,
				},
			})
		end,
	},
	{ -- Autoformat
		"stevearc/conform.nvim",
		event = { "BufWritePre" },
		cmd = { "ConformInfo" },
		keys = {
			{
				"<leader>cf",
				function()
					require("conform").format({ async = true, lsp_format = "fallback" })
				end,
				mode = "",
				desc = "[F]ormat buffer",
			},
		},
		opts = {
			notify_on_error = false,
			format_on_save = function(bufnr)
				-- Disable "format_on_save lsp_fallback" for languages that don't
				-- have a well standardized coding style. You can add additional
				-- languages here or re-enable it for the disabled ones.
				local disable_filetypes = { c = true, cpp = true }
				if disable_filetypes[vim.bo[bufnr].filetype] then
					return nil
				else
					return {
						timeout_ms = 500,
						lsp_format = "fallback",
					}
				end
			end,
			formatters_by_ft = {
				lua = { "stylua" },
				c = { "clang-format" },
				cpp = { "clang-format" },
				-- Conform can also run multiple formatters sequentially
				-- python = { "isort", "black" },
				--
				-- You can use 'stop_after_first' to run the first available formatter from the list
				-- javascript = { "prettierd", "prettier", stop_after_first = true },
			},
			formatters = {
				["clang-format"] = {
					prepend_args = {
						-- Base it on LLVM (attached braces, type pointers), but force 4 spaces
						-- "--style={BasedOnStyle: LLVM, IndentWidth: 4, TabWidth: 4, UseTab: Never, ColumnLimit: 100, AllowShortBlocksOnASingleLine: true, AllowShortCaseLabelsOnASingleLine: true }",
						-- "--style={BasedOnStyle: LLVM, IndentWidth: 4, TabWidth: 4, UseTab: Never, ColumnLimit: 100, AllowShortBlocksOnASingleLine: Always, AllowShortCaseLabelsOnASingleLine: true, AlignConsecutiveDeclarations: true}",
						"--style={BasedOnStyle: LLVM, IndentWidth: 4, TabWidth: 4, UseTab: Never, ColumnLimit: 100}",
					},
				},
			},
		},
	},
	{ -- Autocompletion
		"saghen/blink.cmp",
		event = "VimEnter",
		version = "1.*",
		dependencies = {
			-- Snippet Engine
			{
				"L3MON4D3/LuaSnip",
				version = "2.*",
				build = (function()
					-- Build Step is needed for regex support in snippets.
					-- This step is not supported in many windows environments.
					-- Remove the below condition to re-enable on windows.
					if vim.fn.has("win32") == 1 or vim.fn.executable("make") == 0 then
						return
					end
					return "make install_jsregexp"
				end)(),
				dependencies = {
					-- `friendly-snippets` contains a variety of premade snippets.
					--    See the README about individual language/framework/plugin snippets:
					--    https://github.com/rafamadriz/friendly-snippets
					-- {
					--   'rafamadriz/friendly-snippets',
					--   config = function()
					--     require('luasnip.loaders.from_vscode').lazy_load()
					--   end,
					-- },
				},
				opts = {},
			},
			"folke/lazydev.nvim",
		},
		--- @module 'blink.cmp'
		--- @type blink.cmp.Config
		opts = {
			keymap = {
				preset = "default",
				["<CR>"] = { "accept", "fallback" },
				["<Tab>"] = { "accept", "fallback" },
				["<C-j>"] = { "select_next", "fallback" },
				["<C-k>"] = { "select_prev", "fallback" },
			},

			appearance = {
				-- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
				-- Adjusts spacing to ensure icons are aligned
				nerd_font_variant = "mono",
			},

			completion = {
				-- By default, you may press `<c-space>` to show the documentation.
				-- Optionally, set `auto_show = true` to show the documentation after a delay.
				documentation = { auto_show = false, auto_show_delay_ms = 500 },
			},

			sources = {
				default = { "lsp", "path", "snippets", "lazydev" },
				providers = {
					lazydev = { module = "lazydev.integrations.blink", score_offset = 100 },
				},
			},

			snippets = { preset = "luasnip" },

			-- Blink.cmp includes an optional, recommended rust fuzzy matcher,
			-- which automatically downloads a prebuilt binary when enabled.
			--
			-- By default, we use the Lua implementation instead, but you may enable
			-- the rust implementation via `'prefer_rust_with_warning'`
			--
			-- See :h blink-cmp-config-fuzzy for more information
			fuzzy = { implementation = "lua" },

			-- Shows a signature help window while you type arguments for a function
			signature = { enabled = true },
		},
	},

	-- { -- You can easily change to a different colorscheme.
	-- 	-- Change the name of the colorscheme plugin below, and then
	-- 	-- change the command in the config to whatever the name of that colorscheme is.
	-- 	--
	-- 	-- If you want to see what colorschemes are already installed, you can use `:Telescope colorscheme`.
	-- 	"folke/tokyonight.nvim",
	-- 	priority = 1000, -- Make sure to load this before all the other start plugins.
	-- 	config = function()
	-- 		---@diagnostic disable-next-line: missing-fields
	-- 		require("tokyonight").setup({
	-- 			styles = {
	-- 				comments = { italic = false }, -- Disable italics in comments
	-- 			},
	-- 		})
	--
	-- 		-- Load the colorscheme here.
	-- 		-- Like many other themes, this one has different styles, and you could load
	-- 		-- any other, such as 'tokyonight-storm', 'tokyonight-moon', or 'tokyonight-day'.
	-- 		vim.cmd.colorscheme("tokyonight-night")
	-- 	end,
	-- },
	{
		"rebelot/kanagawa.nvim",
		priority = 1000, -- Make sure to load this before all the other start plugins.
		config = function()
			require("kanagawa").setup()
			vim.cmd.colorscheme("kanagawa")
		end,
	},
	-- {
	-- 	"sainnhe/gruvbox-material",
	-- 	priority = 1000, -- Make sure to load this before all the other start plugins.
	-- 	config = function()
	-- 		vim.g.gruvbox_material_enable_italic = true
	-- 		vim.cmd.colorscheme("gruvbox-material")
	-- 	end,
	-- },
	-- Highlight todo, notes, etc in comments
	{
		"folke/todo-comments.nvim",
		event = "VimEnter",
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = { signs = false },
	},

	{ -- Collection of various small independent plugins/modules
		"echasnovski/mini.nvim",
		config = function()
			-- Better Around/Inside textobjects
			--
			-- Examples:
			--  - va)  - [V]isually select [A]round [)]paren
			--  - yinq - [Y]ank [I]nside [N]ext [Q]uote
			--  - ci'  - [C]hange [I]nside [']quote
			require("mini.ai").setup({ n_lines = 500 })

			-- Add/delete/replace surroundings (brackets, quotes, etc.)
			--
			-- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
			-- - sd'   - [S]urround [D]elete [']quotes
			-- - sr)'  - [S]urround [R]eplace [)] [']
			require("mini.surround").setup()

			-- Simple and easy statusline.
			--  You could remove this setup call if you don't like it,
			--  and try some other statusline plugin
			local statusline = require("mini.statusline")
			-- set use_icons to true if you have a Nerd Font
			statusline.setup({ use_icons = vim.g.have_nerd_font })

			-- You can configure sections in the statusline by overriding their
			-- default behavior. For example, here we set the section for
			-- cursor location to LINE:COLUMN
			---@diagnostic disable-next-line: duplicate-set-field
			statusline.section_location = function()
				return "%2l:%-2v"
			end

			-- ... and there is more!
			--  Check out: https://github.com/echasnovski/mini.nvim
		end,
	},
	{ -- Highlight, edit, and navigate code
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		main = "nvim-treesitter.configs", -- Sets main module to use for opts
		-- [[ Configure Treesitter ]] See `:help nvim-treesitter`
		opts = {
			ensure_installed = {
				"bash",
				"c",
				"cpp",
				"css",
				"diff",
				"html",
				"javascript",
				"lua",
				"luadoc",
				"markdown",
				"markdown_inline",
				"query",
				"typescript",
				"vim",
				"vimdoc",
				"zig",
			},
			-- Autoinstall languages that are not installed
			auto_install = true,
			highlight = {
				enable = true,
				-- Some languages depend on vim's regex highlighting system (such as Ruby) for indent rules.
				--  If you are experiencing weird indenting issues, add the language to
				--  the list of additional_vim_regex_highlighting and disabled languages for indent.
				additional_vim_regex_highlighting = { "ruby" },
			},
			indent = { enable = true, disable = { "ruby" } },
		},
		-- There are additional nvim-treesitter modules that you can use to interact
		-- with nvim-treesitter. You should go explore a few and see what interests you:
		--
		--    - Incremental selection: Included, see `:help nvim-treesitter-incremental-selection-mod`
		--    - Show your current context: https://github.com/nvim-treesitter/nvim-treesitter-context
		--    - Treesitter + textobjects: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
	},
	{
		"mfussenegger/nvim-dap",
		dependencies = {
			"rcarriga/nvim-dap-ui",
			"nvim-neotest/nvim-nio",
			"williamboman/mason.nvim",
		},
		config = function()
			local dap = require("dap")
			local dapui = require("dapui")

			dapui.setup()

			-- 1. Setup the Adapter for C/C++
			dap.adapters.codelldb = {
				type = "server",
				port = "${port}",
				executable = {
					-- Mason installs codelldb here
					command = vim.fn.stdpath("data") .. "/mason/bin/codelldb",
					args = { "--port", "${port}" },
				},
			}

			-- 2. Setup the Configuration for C
			dap.configurations.c = {
				{
					name = "Launch Debug Build",
					type = "codelldb",
					request = "launch",
					-- This looks for your executable in the build folder automatically
					program = function()
						local path = vim.fn.getcwd() .. "/build/my_program"
						if vim.fn.executable(path) == 1 then
							return path
						else
							return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/build/", "file")
						end
					end,
					cwd = "${workspaceFolder}",
					stopOnEntry = false,
				},
			}

			-- Support C++ by copying the C config
			dap.configurations.cpp = dap.configurations.c

			dap.adapters.go = function(callback, config)
				-- This starts 'dlv' in DAP mode automatically when you start debugging
				callback({
					type = "server",
					port = "${port}",
					executable = {
						command = "dlv",
						args = { "dap", "-l", "127.0.0.1:${port}" },
					},
				})
			end

			-- 3. Automatic UI toggling
			dap.listeners.after.event_initialized["dapui_config"] = dapui.open
			dap.listeners.before.event_terminated["dapui_config"] = dapui.close
			dap.listeners.before.event_exited["dapui_config"] = dapui.close

			-- 4. Keymaps (Standard Kickstart style)
			vim.keymap.set("n", "<F5>", dap.continue, { desc = "Debug: Start/Continue" })
			vim.keymap.set("n", "<F10>", dap.step_over, { desc = "Debug: Step Over" })
			vim.keymap.set("n", "<F11>", dap.step_into, { desc = "Debug: Step Into" })
			vim.keymap.set("n", "<F12>", dap.step_out, { desc = "Debug: Step Out" })
			vim.keymap.set("n", "<leader>dp", dap.toggle_breakpoint, { desc = "[D]ebug: Toggle Break[P]oint" })
			vim.keymap.set("n", "<leader>dq", function()
				dap.terminate()
				dapui.close()
			end, { desc = "[D]ebug [Q]uit/Stop" })
			vim.keymap.set("n", "<leader>du", dapui.toggle, { desc = "Toggle [D]ebug [U]I" })
			vim.keymap.set("n", "<leader>dH", function()
				require("dap.ui.widgets").hover()
			end, { desc = "[D]ebug Hover [V]alue" })
		end,
	},
	{
		"nvim-tree/nvim-tree.lua",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function()
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
		end,
	},
	-- {
	-- 	"akinsho/toggleterm.nvim",
	-- 	config = function()
	-- 		require("toggleterm").setup({
	-- 			size = 20,
	-- 			hide_numbers = true,
	-- 			start_in_insert = true,
	-- 			direction = "float",
	-- 			persist_size = true,
	-- 			float_opts = {
	-- 				border = "curved",
	-- 				winblend = 3,
	-- 			},
	-- 			shade_terminal = false,
	-- 			highlights = {
	-- 				TermCursor = {
	-- 					bg = "#FFFFFF", -- Force a bright white background
	-- 					fg = "#000000", -- Force black text for the character under cursor
	-- 				},
	-- 				TermCursorNC = {
	-- 					bg = "#444444", -- Dimmer cursor for non-focused terminal
	-- 				},
	-- 			},
	-- 		})
	-- 		local opts = { noremap = true, silent = true }
	-- 		vim.keymap.set("n", "<leader>wt", "<cmd>ToggleTerm<CR>", { desc = "Toggle [W]indow [T]erminal" })
	-- 		vim.keymap.set({ "n", "t" }, "<C-Space>", "<cmd>ToggleTerm<CR>", { desc = "Toggle [W]indow [T]erminal" })
	-- 	end,
	-- },
	{
		"synepis/jumper.nvim",
		-- dir = "~/git/jumper.nvim/",
		config = function()
			local jumper = require("jumper")
			jumper.setup()

			vim.keymap.set({ "n", "v" }, ";", function()
				jumper.interactive_search()
			end)
		end,
	},
	-- {
	-- 	dir = "~/git/bookmarks.nvim/",
	-- 	config = function()
	-- 		require("bookmarks").setup()
	--
	-- 		vim.keymap.set({ "n", "v" }, "ml", function()
	-- 			require("bookmarks").show_bookmarks()
	-- 		end, { desc = "[M]arks [L]ist" })
	--
	-- 		vim.keymap.set({ "n", "v" }, "mm", function()
	-- 			require("bookmarks").toggle_bookmark()
	-- 		end, { desc = "[M]arks [M]ark (Toggle)" })
	-- 	end,
	-- },
	-- The following comments only work if you have downloaded the kickstart repo, not just copy pasted the
	-- init.lua. If you want these files, they are in the repository, so you can just download them and
	-- place them in the correct locations.

	-- NOTE: Next step on your Neovim journey: Add/Configure additional plugins for Kickstart
	--
	--  Here are some example plugins that I've included in the Kickstart repository.
	--  Uncomment any of the lines below to enable them (you will need to restart nvim).
	--
	-- require 'kickstart.plugins.debug',
	-- require 'kickstart.plugins.indent_line',
	-- require 'kickstart.plugins.lint',
	require("kickstart.plugins.autopairs"),
	-- require 'kickstart.plugins.neo-tree',
	-- require 'kickstart.plugins.gitsigns', -- adds gitsigns recommend keymaps

	-- NOTE: The import below can automatically add your own plugins, configuration, etc from `lua/custom/plugins/*.lua`
	--    This is the easiest way to modularize your config.
	--
	--  Uncomment the following line and add your plugins to `lua/custom/plugins/*.lua` to get going.
	-- { import = 'custom.plugins' },
	--
	-- For additional information with loading, sourcing and examples see `:help lazy.nvim-🔌-plugin-spec`
	-- Or use telescope!
	-- In normal mode type `<space>sh` then write `lazy.nvim-plugin`
	-- you can continue same window with `<space>sr` which resumes last telescope search
}, {
	ui = {
		-- If you are using a Nerd Font: set icons to an empty table which will use the
		-- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
		icons = vim.g.have_nerd_font and {} or {
			cmd = "⌘",
			config = "🛠",
			event = "📅",
			ft = "📂",
			init = "⚙",
			keys = "🗝",
			plugin = "🔌",
			runtime = "💻",
			require = "🌙",
			source = "📄",
			start = "🚀",
			task = "📌",
			lazy = "💤 ",
		},
	},
})

-- [[ My Plugins ]]

-- Bookmarks
require("my_plugins.bookmarks").setup()

vim.keymap.set("n", "ml", "<cmd>BookmarksShow<CR>", { desc = "[M]arks [L]ist" })
vim.keymap.set("n", "mm", "<cmd>BookmarksToggle<CR>", { desc = "[M]arks [M]ark (Toggle)" })

-- Floating terminal
require("my_plugins.floaterm").setup()

vim.keymap.set({ "n", "t" }, "<leader>wt", "<cmd>FloaTermToggle<CR>", { desc = "Toggle [W]indow [T]erminal" })
vim.keymap.set({ "n", "t" }, "<C-Space>", "<cmd>FloaTermToggle<CR>", { desc = "Toggle [W]indow [T]erminal" })
vim.keymap.set({ "t" }, "<leader>q", "<cmd>close<CR>", { desc = "Quit window in terminal mode" })
vim.keymap.set({ "n" }, "<leader>fq", "<cmd>FloaTermQuickfix<CR>", { desc = "[F]ind [Q]uickfix" })

-- Task Runner
require("my_plugins.runner").setup({
	execFn = function(cmd)
		require("my_plugins.floaterm").send_cmd_to_terminal(cmd)
	end,
})

vim.keymap.set("n", "<leader>rs", "<cmd>RunnerSelectTask<CR>", { desc = "[R]unner [S]elect task" })
vim.keymap.set("n", "<leader>ru", "<cmd>RunnerRunUnderCursor<CR>", { desc = "[R]unner Run [U]under cursor" })
vim.keymap.set(
	"n",
	"<leader>rU",
	"<cmd>RunnerRunUnderCursorDryRun<CR>",
	{ desc = "[R]unner Run [U]under cursor Dry Run" }
)
vim.keymap.set("n", "<leader>rr", "<cmd>RunnerReloadConfig<CR>", { desc = "[R]unner [R]eload config" })

-- vim.keymap.set("n", "<leader>rr", function()
-- 	require("my_plugins.floaterm").send_cmd_to_terminal("zig build && ./zig-out/bin/hello")
-- 	-- require("my_plugins.floaterm").send_cmd_to_terminal("ls -a")
-- end, {})
