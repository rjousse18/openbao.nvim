--- `:Bao browse` (level by level) and `:Bao search` (flat fuzzy list of every secret).
local buffer = require("openbao.buffer")
local config = require("openbao.config")
local kv = require("openbao.kv")
local mounts = require("openbao.mounts")
local picker = require("openbao.picker")
local util = require("openbao.util")

local M = {}

local NEW = "+ new secret here"
local UP = "../"

---@type table<string, { time: integer, paths: string[] }>
local index = {}

function M.reset()
  index = {}
end

--- Paths known from earlier searches, for command-line completion.
---@return string[]
function M.known_paths()
  local out = {}
  for _, entry in pairs(index) do
    vim.list_extend(out, entry.paths)
  end
  return out
end

---@param prefix string
---@param cb fun(err: string?, entries: string[]?)
local function list_level(prefix, cb)
  if prefix == "" then
    return mounts.list(function(list, err)
      if not list then
        return cb(err or "no mounts")
      end
      cb(
        nil,
        vim.tbl_map(function(m)
          return m .. "/"
        end, list)
      )
    end)
  end
  kv.list(prefix, function(err, entries)
    cb(err and err.msg, entries)
  end)
end

---@param prefix? string "" or nil lists the mounts
function M.browse(prefix)
  prefix = (prefix or ""):gsub("/+$", "")
  list_level(prefix, function(err, entries)
    if err then
      return util.error(err)
    end
    local items = {}
    if prefix ~= "" then
      items[#items + 1] = UP
      items[#items + 1] = NEW
    end
    vim.list_extend(items, entries)
    picker.select(items, { prompt = "OpenBao: " .. (prefix == "" and "/" or prefix) }, function(choice)
      if not choice then
        return
      end
      if choice == UP then
        return M.browse(util.parent(prefix))
      elseif choice == NEW then
        return vim.ui.input({ prompt = "New secret name: " }, function(name)
          if name and name ~= "" then
            buffer.open(util.join(prefix, name), { create = true })
          end
        end)
      end
      local full = util.join(prefix, choice)
      if choice:sub(-1) == "/" then
        M.browse(full)
      else
        buffer.open(full)
      end
    end)
  end)
end

--- Lists every secret under `prefix` (all mounts when empty), cached for `search.cache_ttl` seconds.
---@param prefix string
---@param cb fun(err: string?, paths: string[]?)
local function all_secrets(prefix, cb)
  local cached = index[prefix]
  if cached and os.time() - cached.time < config.options.search.cache_ttl then
    return cb(nil, cached.paths)
  end
  local function done(err, paths)
    if err then
      return cb(err.msg)
    end
    index[prefix] = { time = os.time(), paths = paths }
    cb(nil, paths)
  end
  if prefix ~= "" then
    return kv.walk(prefix, config.options.search, done)
  end
  mounts.list(function(list, err)
    if not list then
      return cb(err or "no mounts")
    end
    local all = {}
    util.map_limit(list, 2, function(mount, next_mount)
      kv.walk(mount, config.options.search, function(_, paths)
        next_mount(paths or {})
      end)
    end, function(results)
      for _, paths in ipairs(results) do
        vim.list_extend(all, paths)
      end
      table.sort(all)
      done(nil, all)
    end)
  end)
end

---@param prefix? string
function M.search(prefix)
  prefix = (prefix or ""):gsub("/+$", "")
  util.notify("indexing " .. (prefix == "" and "all mounts" or prefix) .. "...")
  all_secrets(prefix, function(err, paths)
    if err then
      return util.error(err)
    end
    if #paths == 0 then
      return util.notify("no secret found")
    end
    picker.select(paths, { prompt = "OpenBao search" }, function(choice)
      if choice then
        buffer.open(choice)
      end
    end)
  end)
end

M.all_secrets = all_secrets

return M
