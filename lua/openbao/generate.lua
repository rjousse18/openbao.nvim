--- `:Bao generate-conf`: scaffolds a profile in the project file (`.openbao.json`). Paths only, never values.
local browse = require("openbao.browse")
local env = require("openbao.env")
local picker = require("openbao.picker")
local util = require("openbao.util")

local M = {}

local FILE = ".openbao.json"
local DONE = "-- done --"
-- Stable, human-friendly key order: vim.json.encode cannot indent and orders keys randomly.
local ORDER = { "default", "profiles", "sources", "file", "path", "prefix", "only", "to_env", "push_to", "vim_env" }

---@param t table
---@return string[]
local function ordered_keys(t)
  local keys = {}
  for _, k in ipairs(ORDER) do
    if t[k] ~= nil then
      keys[#keys + 1] = k
    end
  end
  local rest = vim.tbl_filter(function(k)
    return not vim.tbl_contains(ORDER, k)
  end, util.sorted_keys(t))
  return vim.list_extend(keys, rest)
end

--- Pretty JSON with a stable key order (pure).
---@param value any
---@param indent? string
---@return string
function M.encode(value, indent)
  indent = indent or ""
  if type(value) ~= "table" then
    return vim.json.encode(value)
  end
  local inner = indent .. "  "
  local parts = {}
  if vim.islist(value) then
    if #value == 0 then
      return "[]"
    end
    for _, v in ipairs(value) do
      parts[#parts + 1] = inner .. M.encode(v, inner)
    end
    return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
  end
  for _, k in ipairs(ordered_keys(value)) do
    parts[#parts + 1] = inner .. vim.json.encode(k) .. ": " .. M.encode(value[k], inner)
  end
  if #parts == 0 then
    return "{}"
  end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

--- Returns a copy of `cfg` with the profile added (pure). The `.env.<name>` file is the profile's local file.
---@param cfg table
---@param name string
---@param sources string[]
---@param force? boolean replace an existing profile
---@return table? cfg
---@return string? err
function M.add_profile(cfg, name, sources, force)
  if not name:match("^[%w_.-]+$") then
    return nil, ("invalid profile name '%s' (letters, digits, _ . -)"):format(name)
  end
  if #sources == 0 then
    return nil, "no source: pass at least one secret path"
  end
  local out = vim.deepcopy(cfg)
  out.profiles = out.profiles or {}
  if out.profiles[name] and not force then
    return nil, ("profile '%s' already exists (use --force to replace it)"):format(name)
  end
  out.profiles[name] = { sources = sources, file = ".env." .. name }
  out.default = out.default or name
  return out
end

--- The project file to update: the nearest existing one, else a new one at the git root (or cwd).
---@return string? path
---@return string? err
---@return boolean? in_git
function M.target()
  local cwd = vim.fn.getcwd()
  local git_root = vim.fs.root(cwd, ".git")
  local existing = env.find_file(cwd)
  if existing then
    if not existing:match("%.json$") then
      return nil, existing .. " is code: add the profile by hand (see README)"
    end
    return existing, nil, git_root ~= nil
  end
  return vim.fs.joinpath(git_root or cwd, FILE), nil, git_root ~= nil
end

---@param name string
---@param sources string[]
---@param force? boolean
function M.write(name, sources, force)
  local path, err, in_git = M.target()
  if not path then
    return util.error(err)
  end
  local cfg = {}
  if vim.fn.filereadable(path) == 1 then
    cfg, err = env.load(path)
    if not cfg then
      return util.error(err)
    end
  end
  local updated, perr = M.add_profile(cfg, name, sources, force)
  if not updated then
    return util.error(perr)
  end
  vim.fn.writefile(vim.split(M.encode(updated), "\n"), path)
  local file = updated.profiles[name].file
  local note = ""
  if in_git and env.gitignore(vim.fs.joinpath(vim.fs.dirname(path), file)) then
    note = (" (%s added to .gitignore)"):format(file)
  end
  util.notify(
    ("%s: profile '%s' with %d source(s) -> %s%s\nNext: :Bao env pull %s"):format(
      vim.fn.fnamemodify(path, ":~:."),
      name,
      #sources,
      file,
      note,
      name
    )
  )
end

---@param paths string[]
---@param chosen string[]
---@param cb fun(sources: string[]?) nil when cancelled
local function choose(paths, chosen, cb)
  local items = { DONE }
  for _, p in ipairs(paths) do
    if not vim.tbl_contains(chosen, p) then
      items[#items + 1] = p
    end
  end
  local prompt = ("OpenBao sources (%d selected, a later source wins)"):format(#chosen)
  picker.select(items, { prompt = prompt }, function(choice)
    if not choice then
      return cb(nil)
    elseif choice == DONE then
      return cb(chosen)
    end
    chosen[#chosen + 1] = choice
    choose(paths, chosen, cb)
  end)
end

--- With paths: writes directly. Without: asks for the sources through the picker.
---@param name? string
---@param sources string[]
---@param force? boolean
function M.run(name, sources, force)
  local function with_name(n)
    if not n or n == "" then
      return
    end
    if #sources > 0 then
      return M.write(n, sources, force)
    end
    util.notify("indexing secrets...")
    browse.all_secrets("", function(err, paths)
      if err then
        return util.error(err)
      end
      choose(paths, {}, function(chosen)
        if chosen and #chosen > 0 then
          M.write(n, chosen, force)
        end
      end)
    end)
  end
  if name then
    return with_name(name)
  end
  vim.ui.input({ prompt = "Profile name (e.g. uat1): ", default = "dev" }, with_name)
end

return M
