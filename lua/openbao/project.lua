--- `:Bao project`: a local mirror directory of OpenBao secrets, one file per secret.
---
--- Layout (relative to the cwd, `project.dir` option, git-ignored by its own `.gitignore`):
---   .openbao/secret/app/db.env     dotenv secret (`.json` when the secret is not flat strings)
---   .openbao/.state.json           prefixes pulled + version/hash of each file when pulled
local config = require("openbao.config")
local format = require("openbao.format")
local kv = require("openbao.kv")
local util = require("openbao.util")

local M = {}

local MODE = tonumber("600", 8)

---@return string
local function root()
  return vim.fs.joinpath(vim.fn.getcwd(), config.options.project.dir)
end

---@param full string
---@param fmt "dotenv"|"json"
---@return string
local function file_for(full, fmt)
  return vim.fs.joinpath(root(), full .. (fmt == "json" and ".json" or ".env"))
end

---@class OpenBaoMirrorState
---@field prefixes string[]
---@field files table<string, { version: integer, hash: string }>

---@return OpenBaoMirrorState
local function load_state()
  local path = vim.fs.joinpath(root(), ".state.json")
  if vim.fn.filereadable(path) == 1 then
    local ok, state = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
    if ok and type(state) == "table" then
      state.prefixes, state.files = state.prefixes or {}, state.files or {}
      return state
    end
  end
  return { prefixes = {}, files = {} }
end

---@param state OpenBaoMirrorState
local function save_state(state)
  vim.fn.mkdir(root(), "p")
  vim.fn.writefile({ vim.json.encode(state) }, vim.fs.joinpath(root(), ".state.json"))
end

--- Owner-only file; the mirror directory ignores itself in git.
---@param path string
---@param lines string[]
local function write_secure(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local ignore = vim.fs.joinpath(root(), ".gitignore")
  if vim.fn.filereadable(ignore) == 0 then
    vim.fn.writefile({ "*" }, ignore)
  end
  local fd = assert(vim.uv.fs_open(path, "w", MODE))
  vim.uv.fs_close(fd)
  vim.uv.fs_chmod(path, MODE)
  vim.fn.writefile(lines, path)
end

---@param path string
---@return string content
local function read(path)
  return table.concat(vim.fn.readfile(path), "\n")
end

---@param content string
---@return string
local function hash(content)
  return vim.fn.sha256(content)
end

---@class OpenBaoMirrorFile
---@field full string
---@field path string
---@field fmt "dotenv"|"json"

---@return OpenBaoMirrorFile[]
local function local_files()
  local files = {}
  if vim.fn.isdirectory(root()) == 0 then
    return files
  end
  for name, type_ in vim.fs.dir(root(), { depth = 20 }) do
    local base = vim.fs.basename(name)
    if type_ == "file" and not vim.startswith(base, ".") then
      local stem, ext = name:match("^(.*)%.(%w+)$")
      if ext == "env" or ext == "json" then
        files[#files + 1] =
          { full = stem, path = vim.fs.joinpath(root(), name), fmt = ext == "json" and "json" or "dotenv" }
      end
    end
  end
  table.sort(files, function(a, b)
    return a.full < b.full
  end)
  return files
end

---@param prefixes string[]
---@param cb fun(err: string?, paths: string[]?)
local function remote_paths(prefixes, cb)
  local seen, all = {}, {}
  util.map_limit(prefixes, 2, function(prefix, done)
    kv.walk(prefix, config.options.search, function(err, paths)
      done({ err = err, paths = paths or {} })
    end)
  end, function(results)
    for _, r in ipairs(results) do
      if r.err then
        return cb(r.err.msg)
      end
      for _, p in ipairs(r.paths) do
        if not seen[p] then
          seen[p] = true
          all[#all + 1] = p
        end
      end
    end
    table.sort(all)
    cb(nil, all)
  end)
end

---@param prefixes? string[] defaults to the prefixes pulled before
---@param opts? { force?: boolean }
---@param cb? fun(err: string?, written: integer?)
function M.pull(prefixes, opts, cb)
  opts, cb = opts or {}, cb or function() end
  local state = load_state()
  prefixes = (prefixes and #prefixes > 0) and prefixes or state.prefixes
  if #prefixes == 0 then
    local msg = "usage: :Bao project pull <mount/prefix> [more prefixes]"
    util.error(msg)
    return cb(msg)
  end
  remote_paths(prefixes, function(err, paths)
    if err then
      util.error(err)
      return cb(err)
    end
    local written, skipped = 0, {}
    util.map_limit(paths, config.options.search.concurrency, function(full, done)
      kv.get(full, nil, function(gerr, secret)
        if gerr then
          skipped[#skipped + 1] = full .. " (" .. gerr.msg .. ")"
          return done(false)
        end
        local fmt = format.classify(secret.data)
        local path = file_for(full, fmt)
        local lines = format.to_lines(fmt, secret.data)
        local known = state.files[full]
        if vim.fn.filereadable(path) == 1 and not opts.force then
          local current = read(path)
          local edited = not known or hash(current) ~= known.hash
          if edited and current ~= table.concat(lines, "\n") then
            skipped[#skipped + 1] = full .. " (modified locally, use --force)"
            return done(false)
          end
        end
        write_secure(path, lines)
        state.files[full] = { version = secret.version, hash = hash(table.concat(lines, "\n")) }
        written = written + 1
        done(true)
      end)
    end, function()
      for _, p in ipairs(prefixes) do
        if not vim.tbl_contains(state.prefixes, p) then
          state.prefixes[#state.prefixes + 1] = p
        end
      end
      save_state(state)
      util.notify(("pulled %d secret(s) into %s"):format(written, config.options.project.dir))
      if #skipped > 0 then
        util.notify("skipped:\n" .. table.concat(skipped, "\n"), vim.log.levels.WARN)
      end
      cb(nil, written)
    end)
  end)
end

---@alias OpenBaoMirrorStatus "clean"|"modified"|"outdated"|"conflict"|"new"|"invalid"

---@class OpenBaoMirrorRow
---@field file OpenBaoMirrorFile
---@field status OpenBaoMirrorStatus
---@field data? table parsed local content
---@field remote? OpenBaoSecret

--- Compares every local file with OpenBao.
---@param cb fun(rows: OpenBaoMirrorRow[])
function M.scan(cb)
  local state = load_state()
  util.map_limit(local_files(), config.options.search.concurrency, function(file, done)
    local content = read(file.path)
    local data = format.parse(file.fmt, vim.split(content, "\n", { plain = true }))
    if not data then
      return done({ file = file, status = "invalid" })
    end
    kv.get(file.full, nil, function(err, remote)
      if err then
        return done({ file = file, status = err.kind == "not_found" and "new" or "invalid", data = data })
      end
      local known = state.files[file.full]
      local local_changed = not vim.deep_equal(data, remote.data)
      local touched = not known or hash(content) ~= known.hash
      local remote_moved = not known or known.version ~= remote.version
      local status = "clean"
      if local_changed and touched and remote_moved then
        status = "conflict"
      elseif local_changed and touched then
        status = "modified"
      elseif local_changed then
        status = "outdated"
      end
      done({ file = file, status = status, data = data, remote = remote })
    end)
  end, cb)
end

---@param cb? fun(rows: OpenBaoMirrorRow[])
function M.status(cb)
  M.scan(function(rows)
    local lines = {}
    for _, r in ipairs(rows) do
      if r.status ~= "clean" then
        lines[#lines + 1] = ("%-9s %s"):format(r.status, r.file.full)
      end
    end
    util.notify(#lines == 0 and ("%d file(s), all in sync"):format(#rows) or table.concat(lines, "\n"))
    if cb then
      cb(rows)
    end
  end)
end

--- Pushes `modified` and `new` files; `conflict` ones only with `force` (no check-and-set then).
---@param opts? { force?: boolean }
---@param cb? fun(err: string?)
function M.push(opts, cb)
  opts, cb = opts or {}, cb or function() end
  M.scan(function(rows)
    local todo, blocked = {}, {}
    for _, r in ipairs(rows) do
      if r.status == "modified" or r.status == "new" or (r.status == "conflict" and opts.force) then
        todo[#todo + 1] = r
      elseif r.status == "conflict" or r.status == "invalid" then
        blocked[#blocked + 1] = r.status .. " " .. r.file.full
      end
    end
    if #blocked > 0 then
      util.notify(
        "not pushed:\n" .. table.concat(blocked, "\n") .. "\n(pull --force or push --force to resolve)",
        vim.log.levels.WARN
      )
    end
    if #todo == 0 then
      util.notify("nothing to push")
      return cb(nil)
    end
    local summary = vim.tbl_map(function(r)
      local diff = r.remote and format.describe(format.diff(r.remote.data, r.data)) or "(new)"
      return r.file.full .. ": " .. diff
    end, todo)
    vim.ui.select(
      { "Push", "Cancel" },
      { prompt = "Push to OpenBao?\n" .. table.concat(summary, "\n") },
      function(choice)
        if choice ~= "Push" then
          return cb("cancelled")
        end
        local state = load_state()
        local failures = {}
        util.map_limit(todo, 1, function(r, done)
          local cas
          if config.options.cas and r.status ~= "conflict" then
            cas = r.remote and r.remote.version or 0
          end
          kv.put(r.file.full, r.data, { cas = cas }, function(err, version)
            if err then
              failures[#failures + 1] = r.file.full .. ": " .. err.msg
            else
              state.files[r.file.full] = { version = version or 0, hash = hash(read(r.file.path)) }
            end
            done()
          end)
        end, function()
          save_state(state)
          if #failures > 0 then
            util.error("push failed:\n" .. table.concat(failures, "\n"))
            return cb(table.concat(failures, "; "))
          end
          util.notify(("pushed %d secret(s)"):format(#todo))
          cb(nil)
        end)
      end
    )
  end)
end

return M
