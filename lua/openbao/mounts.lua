--- KV mount discovery and `mount/relative/path` splitting.
local client = require("openbao.client")
local config = require("openbao.config")

local M = {}

---@type string[]?
local cache = nil

function M.reset()
  cache = nil
end

--- KV v2 mounts, without trailing slash. Uses the `mounts` option, else `secrets list`,
--- else falls back to `default_mount` when the token cannot read sys/mounts.
---@param cb fun(mounts: string[]?, err: string?)
function M.list(cb)
  if config.options.mounts then
    return vim.schedule(function()
      cb(config.options.mounts)
    end)
  end
  if cache then
    return vim.schedule(function()
      cb(cache)
    end)
  end
  client.call({ "secrets", "list", "-format=json" }, { json = true }, function(res)
    if not res.ok then
      local fallback = config.options.default_mount
      return cb(fallback and { fallback } or nil, res.stderr)
    end
    local mounts = {}
    for path, info in pairs(res.json or {}) do
      local version = info.options and info.options.version
      if info.type == "kv" and tostring(version) == "2" then
        mounts[#mounts + 1] = (path:gsub("/$", ""))
      end
    end
    table.sort(mounts)
    cache = mounts
    cb(mounts)
  end)
end

--- Splits "secret/app/db" into ("secret", "app/db") using the longest matching mount.
---@param full string
---@param cb fun(mount: string?, rel: string?, err: string?)
function M.resolve(full, cb)
  full = full:gsub("^/+", ""):gsub("/+$", "")
  M.list(function(mounts, err)
    local best
    for _, m in ipairs(mounts or {}) do
      if (full == m or vim.startswith(full, m .. "/")) and (not best or #m > #best) then
        best = m
      end
    end
    if best then
      return cb(best, (full:sub(#best + 2)))
    end
    local default = config.options.default_mount
    if default then
      return cb(default, full)
    end
    cb(nil, nil, err or ("no KV v2 mount matches '%s' (mounts: %s)"):format(full, table.concat(mounts or {}, ", ")))
  end)
end

return M
