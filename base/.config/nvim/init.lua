-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
vim.g.mapleader = " "

-- Use system clipboard by default
vim.opt.clipboard = "unnamedplus"

-- Insert mode: 'jk' to escape
vim.keymap.set("i", "jk", "<Esc>", { noremap = true })

-- Visual mode: 'jk' to escape
vim.keymap.set("v", "jk", "<Esc>", { noremap = true })

-- H and L for home/end
vim.keymap.set({"n", "v", "o"}, "H", "0", { noremap = true })
vim.keymap.set({"n", "v", "o"}, "L", "$", { noremap = true })

-- Window movement
vim.keymap.set("n", "<leader>wh", "<C-w>h", { noremap = true })
vim.keymap.set("n", "<leader>wj", "<C-w>j", { noremap = true })
vim.keymap.set("n", "<leader>wk", "<C-w>k", { noremap = true })
vim.keymap.set("n", "<leader>wl", "<C-w>l", { noremap = true })
