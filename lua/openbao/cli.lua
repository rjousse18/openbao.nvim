--- Thin wrapper around the `bao` / `vault` binary. The only place that spawns processes.
local config = require("openbao.config")

local M = {}

---@class OpenBaoResult
---@field ok boolean exit code 0
---@field code integer
---@field stdout string
---@field stderr string
---@field json? any decoded stdout when `opts.json` and decoding succeeded

--- Resolves the binary: the `binary` option, else `bao`, else `vault`.
---@return string? path
---@return string? err
function M.binary()
  local wanted = config.options.binary
  if wanted then
    if vim.fn.executable(wanted) == 1 then
      return wanted
    end
    return nil, ("binary '%s' is not executable"):format(wanted)
  end
  for _, name in ipairs({ "bao", "vault" }) do
    if vim.fn.executable(name) == 1 then
      return name
    end
  end
  return nil, "neither `bao` nor `vault` found in $PATH (see the `binary` option)"
end

---@return table<string, string>
local function child_env()
  local env = {}
  local address = config.options.address
  if address then
    env.BAO_ADDR = address
    env.VAULT_ADDR = address
  end
  return vim.tbl_extend("force", env, config.options.env)
end

--- Runs the CLI. `cb` is always called on the main loop, never synchronously.
--- Secrets must go through `opts.stdin`, never through `args` (visible in `ps`).
---@param args string[]
---@param opts? { stdin?: string, json?: boolean, timeout?: integer, on_output?: fun(chunk: string) }
---@param cb fun(res: OpenBaoResult)
function M.run(args, opts, cb)
  opts = opts or {}
  local bin, err = M.binary()
  if not bin then
    return vim.schedule(function()
      cb({ ok = false, code = -1, stdout = "", stderr = err or "" })
    end)
  end
  local function forward(_, data)
    if data and opts.on_output then
      vim.schedule(function()
        opts.on_output(data)
      end)
    end
  end
  vim.system(vim.list_extend({ bin }, args), {
    text = true,
    stdin = opts.stdin,
    env = child_env(),
    timeout = opts.timeout or config.options.timeout,
    stdout = opts.on_output and forward or nil,
    stderr = opts.on_output and forward or nil,
  }, function(obj)
    vim.schedule(function()
      local res = {
        ok = obj.code == 0,
        code = obj.code,
        stdout = obj.stdout or "",
        stderr = vim.trim(obj.stderr or ""),
      }
      if res.ok and opts.json and vim.trim(res.stdout) ~= "" then
        local ok, decoded = pcall(vim.json.decode, res.stdout)
        if ok then
          res.json = decoded
        else
          res.ok, res.stderr = false, "invalid JSON from CLI: " .. tostring(decoded)
        end
      end
      cb(res)
    end)
  end)
end

return M
