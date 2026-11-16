--- KV v2 operations through the CLI. Paths are always "mount/relative/path".
local client = require("openbao.client")
local mounts = require("openbao.mounts")
local util = require("openbao.util")

local M = {}

---@class OpenBaoError
---@field kind "not_found"|"cas"|"auth"|"error"
---@field msg string

---@param msg string CLI stderr
---@return OpenBaoError
local function classify(msg)
  local kind = "error"
  local lower = msg:lower()
  if lower:find("no value found", 1, true) then
    kind = "not_found"
  elseif lower:find("check-and-set", 1, true) then
    kind = "cas"
  elseif client.looks_like_auth_error({ stderr = msg }) then
    kind = "auth"
  end
  return { kind = kind, msg = msg }
end

---@param res OpenBaoResult
---@return OpenBaoError
local function to_error(res)
  return classify(res.stderr ~= "" and res.stderr or ("exit code " .. res.code))
end

--- Resolves the mount then runs `bao kv <sub> -mount=... [flags] [rel] [extra]`.
---@param sub string[] e.g. { "get" } or { "metadata", "get" }
---@param full string
---@param flags string[]
---@param opts? { stdin?: string, positional?: boolean }
---@param cb fun(err: OpenBaoError?, res: OpenBaoResult?)
local function kv(sub, full, flags, opts, cb)
  opts = opts or {}
  mounts.resolve(full, function(mount, rel, err)
    if not mount then
      return cb(classify(err or "unknown mount"))
    end
    local args = { "kv" }
    vim.list_extend(args, sub)
    vim.list_extend(args, { "-format=json", "-mount=" .. mount })
    vim.list_extend(args, flags)
    if rel ~= "" then
      args[#args + 1] = rel
    end
    if opts.stdin then
      args[#args + 1] = "-"
    end
    client.call(args, { json = true, stdin = opts.stdin }, function(res)
      if res.ok then
        res.mount, res.rel = mount, rel
        return cb(nil, res)
      end
      cb(to_error(res), res)
    end)
  end)
end

---@class OpenBaoSecret
---@field data table<string, any>
---@field version integer

--- Reads a secret (latest version, or `opts.version`).
---@param full string
---@param opts? { version?: integer }
---@param cb fun(err: OpenBaoError?, secret: OpenBaoSecret?)
function M.get(full, opts, cb)
  local flags = {}
  if opts and opts.version then
    flags[1] = "-version=" .. opts.version
  end
  kv({ "get" }, full, flags, nil, function(err, res)
    if err then
      return cb(err)
    end
    local d = (res.json or {}).data or {}
    if type(d.data) ~= "table" then
      return cb({ kind = "not_found", msg = "secret has no data (deleted version?)" })
    end
    cb(nil, { data = d.data, version = (d.metadata or {}).version or 0 })
  end)
end

--- Writes a secret. `opts.cas`: expected current version (0 = must not exist yet).
---@param full string
---@param data table<string, any>
---@param opts? { cas?: integer }
---@param cb fun(err: OpenBaoError?, version: integer?)
function M.put(full, data, opts, cb)
  local flags = {}
  if opts and opts.cas then
    flags[1] = "-cas=" .. opts.cas
  end
  local body = next(data) == nil and "{}" or vim.json.encode(data)
  kv({ "put" }, full, flags, { stdin = body }, function(err, res)
    if err then
      return cb(err)
    end
    cb(nil, ((res.json or {}).data or {}).version)
  end)
end

--- Lists one level. Entries ending with "/" are folders. An empty folder yields {}.
---@param full string "mount" or "mount/folder"
---@param cb fun(err: OpenBaoError?, entries: string[]?)
function M.list(full, cb)
  kv({ "list" }, full, {}, nil, function(err, res)
    if err then
      if err.kind == "not_found" or (res and res.code == 2 and err.msg:lower():find("no value", 1, true)) then
        return cb(nil, {})
      end
      return cb(err)
    end
    local entries = res.json or {}
    table.sort(entries)
    cb(nil, entries)
  end)
end

---@class OpenBaoVersion
---@field version integer
---@field created? string
---@field deleted boolean
---@field destroyed boolean

---@param full string
---@param cb fun(err: OpenBaoError?, versions: OpenBaoVersion[]?, current: integer?)
function M.versions(full, cb)
  kv({ "metadata", "get" }, full, {}, nil, function(err, res)
    if err then
      return cb(err)
    end
    local d = (res.json or {}).data or {}
    local out = {}
    for n, v in pairs(d.versions or {}) do
      out[#out + 1] = {
        version = tonumber(n),
        created = v.created_time,
        deleted = (v.deletion_time or "") ~= "",
        destroyed = v.destroyed == true,
      }
    end
    table.sort(out, function(a, b)
      return a.version > b.version
    end)
    cb(nil, out, d.current_version)
  end)
end

--- Makes an old version the newest one (creates a new version).
---@param full string
---@param version integer
---@param cb fun(err: OpenBaoError?)
function M.rollback(full, version, cb)
  kv({ "rollback" }, full, { "-version=" .. version }, nil, function(err)
    cb(err)
  end)
end

--- Soft-deletes the latest version (recoverable with `undelete`).
---@param full string
---@param cb fun(err: OpenBaoError?)
function M.delete(full, cb)
  kv({ "delete" }, full, {}, nil, function(err)
    cb(err)
  end)
end

---@param full string
---@param versions integer[]
---@param cb fun(err: OpenBaoError?)
function M.undelete(full, versions, cb)
  kv({ "undelete" }, full, { "-versions=" .. table.concat(versions, ",") }, nil, function(err)
    cb(err)
  end)
end

--- Every secret under `prefix` (recursive). Returns full paths, sorted.
---@param prefix string "mount" or "mount/folder"
---@param opts { concurrency: integer, max_depth: integer }
---@param cb fun(err: OpenBaoError?, paths: string[]?)
function M.walk(prefix, opts, cb)
  local found, first_err = {}, nil
  local function visit(folder, depth, done)
    M.list(folder, function(err, entries)
      if err then
        first_err = first_err or err
        return done()
      end
      local subfolders = {}
      for _, e in ipairs(entries) do
        if e:sub(-1) == "/" then
          if depth < opts.max_depth then
            subfolders[#subfolders + 1] = util.join(folder, e)
          end
        else
          found[#found + 1] = util.join(folder, e)
        end
      end
      util.map_limit(subfolders, opts.concurrency, function(sub, d)
        visit(sub, depth + 1, d)
      end, function()
        done()
      end)
    end)
  end
  visit(prefix, 1, function()
    table.sort(found)
    cb(first_err, found)
  end)
end

return M
