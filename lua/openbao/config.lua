local M = {}

---@class OpenBaoLoginOpts
---@field method string `bao login -method=<method>`
---@field args string[] extra arguments, e.g. { "role=dev" }
---@field timeout integer ms to wait for the (browser) login to complete
---@field auto boolean offer to log in when a call fails because of authentication

---@class OpenBaoOpts
---@field binary? string CLI to use; default: `bao`, then `vault`
---@field address? string passed to the CLI as BAO_ADDR / VAULT_ADDR
---@field env table<string, string> extra environment variables for the CLI (BAO_NAMESPACE...)
---@field timeout integer ms before a CLI call is killed
---@field mounts? string[] KV v2 mounts; default: detected with `secrets list`
---@field default_mount? string used when detection is impossible (token cannot read sys/mounts)
---@field login OpenBaoLoginOpts
---@field cas boolean send check-and-set so a remote change is never overwritten silently
---@field confirm_deletions boolean ask before writing a buffer that removes keys
---@field conceal boolean hide values in secret buffers
---@field reveal_key? string buffer-local mapping toggling the concealment
---@field search { concurrency: integer, max_depth: integer, cache_ttl: integer }
---@field picker "auto"|"snacks"|"telescope"|"fzf-lua"|"select"
---@field project { dir: string } mirror directory (relative to cwd) of `:Bao project`
---@field env_files string[] project file names looked up (upwards) by `:Bao env`

---@type OpenBaoOpts
M.defaults = {
  binary = nil,
  address = nil,
  env = {},
  timeout = 30000,
  mounts = nil,
  default_mount = nil,
  login = { method = "oidc", args = {}, timeout = 300000, auto = true },
  cas = true,
  confirm_deletions = true,
  conceal = true,
  reveal_key = "<LocalLeader>r",
  search = { concurrency = 8, max_depth = 10, cache_ttl = 60 },
  picker = "auto",
  project = { dir = ".openbao" },
  env_files = { ".openbao.lua", ".openbao.json" },
}

---@type OpenBaoOpts
M.options = vim.deepcopy(M.defaults)

---@param opts? table
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  require("openbao.mounts").reset()
end

return M
