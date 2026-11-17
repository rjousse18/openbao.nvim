local M = {}

--- Optional: only needed to change the defaults (see `openbao.config`).
---@param opts? OpenBaoOpts
function M.setup(opts)
  require("openbao.config").setup(opts)
end

--- Opens `mount/path` in a buffer (`:w` saves it to OpenBao).
---@param full string
function M.edit(full)
  require("openbao.buffer").open(full)
end

M.browse = function(prefix)
  require("openbao.browse").browse(prefix)
end

M.search = function(prefix)
  require("openbao.browse").search(prefix)
end

M.login = function()
  require("openbao.auth").login()
end

--- Loads a project profile into `vim.env` (and its .env file, if configured).
---@param profile? string
M.env_pull = function(profile)
  local p, err = require("openbao.env").resolve(profile)
  if not p then
    return require("openbao.util").error(err or "no profile")
  end
  require("openbao.env").pull(p)
end

--- Text for a statusline: the `.env` file (or profile) loaded in `vim.env`, empty when none.
--- lualine: `sections = { lualine_x = { require("openbao").statusline } }`
---@return string
M.statusline = function()
  return require("openbao.env").statusline()
end

return M
