-- Minimal Neovim config for the test suite: puts the plugin and plenary on the runtimepath.
-- plenary is looked up in ./.deps (see `make deps`) or in $OPENBAO_DEPS.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local deps = vim.env.OPENBAO_DEPS or (root .. "/.deps")

package.path = root .. "/?.lua;" .. package.path
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(deps .. "/plenary.nvim")
vim.cmd("runtime plugin/plenary.vim")
vim.cmd("runtime plugin/openbao.lua")
vim.opt.swapfile = false
