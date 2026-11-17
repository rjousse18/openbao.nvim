if vim.g.loaded_openbao or vim.fn.has("nvim-0.10") == 0 then
  return
end
vim.g.loaded_openbao = true

vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWritePost" }, {
  pattern = { ".env", ".env.*" },
  desc = "OpenBao: mark the .env file loaded in vim.env",
  callback = function(ev)
    require("openbao.env").decorate(ev.buf)
  end,
})

vim.api.nvim_create_user_command("Bao", function(opts)
  require("openbao.commands").run(opts)
end, {
  nargs = "*",
  desc = "OpenBao / Vault: edit secrets, sync environment variables",
  complete = function(arglead, cmdline)
    return require("openbao.commands").complete(arglead, cmdline)
  end,
})
