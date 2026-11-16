--- `:Bao env`: sync OpenBao secrets with the environment of a project.
--- The project file (`.openbao.lua` or `.openbao.json`) maps OpenBao paths to environment
--- variables. It holds paths only, never secret values, so it can be committed.
local config = require("openbao.config")
local format = require("openbao.format")
local kv = require("openbao.kv")
local util = require("openbao.util")

local M = {}

---@class OpenBaoSource
---@field path string "mount/path" of the secret
---@field prefix string prepended to each key to build the variable name
---@field only? string[] keys to keep (default: all)
---@field to_env? boolean rewrite names that are not environment-style (`a.b-c` -> `A_BC`), see `M.env_name`

---@class OpenBaoProfile
---@field name string
---@field sources OpenBaoSource[] later sources override earlier ones
---@field file? string absolute path of the generated .env file
---@field vim_env boolean also set `vim.env` (default true)
---@field push_to integer index in `sources` receiving new variables on push (default: the last)
---@field root string directory of the project file

---@param start? string
---@return string? path
function M.find_file(start)
  return vim.fs.find(config.options.env_files, { upward = true, path = start or vim.fn.getcwd(), type = "file" })[1]
end

--- Reads the project file. `.lua` files are code, so they go through Neovim's trust prompt.
---@param path string
---@return table? cfg
---@return string? err
function M.load(path)
  if path:match("%.json$") then
    local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
    if not ok or type(decoded) ~= "table" then
      return nil, path .. ": invalid JSON"
    end
    return decoded
  end
  local content = vim.secure.read(path)
  if not content then
    return nil, path .. " is not trusted (see :h vim.secure.read)"
  end
  local chunk, err = load(content, "@" .. path, "t", {})
  if not chunk then
    return nil, err
  end
  local ok, cfg = pcall(chunk)
  if not ok or type(cfg) ~= "table" then
    return nil, path .. ": the file must `return { ... }`"
  end
  return cfg
end

---@param cfg table
---@param name? string
---@param root string
---@return OpenBaoProfile? profile
---@return string? err
function M.profile(cfg, name, root)
  local profiles = cfg.profiles or {}
  local names = util.sorted_keys(profiles)
  name = name or cfg.default or (#names == 1 and names[1] or nil)
  if not name then
    return nil, "several profiles, pick one: " .. table.concat(names, ", ")
  end
  local raw = profiles[name]
  if not raw then
    return nil, ("unknown profile '%s' (available: %s)"):format(name, table.concat(names, ", "))
  end
  local sources = {}
  for _, s in ipairs(raw.sources or {}) do
    local source = type(s) == "string" and { path = s } or vim.deepcopy(s)
    if type(source.path) ~= "string" then
      return nil, ("profile '%s': each source needs a `path`"):format(name)
    end
    source.prefix = source.prefix or ""
    sources[#sources + 1] = source
  end
  if #sources == 0 then
    return nil, ("profile '%s' has no sources"):format(name)
  end
  local push_to = #sources
  if raw.push_to then
    push_to = nil
    for i, s in ipairs(sources) do
      if s.path == raw.push_to then
        push_to = i
      end
    end
    if not push_to then
      return nil, ("profile '%s': push_to '%s' is not one of the sources"):format(name, raw.push_to)
    end
  end
  return {
    name = name,
    sources = sources,
    file = raw.file and vim.fs.joinpath(root, raw.file) or nil,
    vim_env = raw.vim_env ~= false,
    push_to = push_to,
    root = root,
  }
end

--- Finds, loads and resolves the profile for the current project.
---@param name? string
---@return OpenBaoProfile? profile
---@return string? err
function M.resolve(name)
  local path = M.find_file()
  if not path then
    return nil, "no " .. table.concat(config.options.env_files, " / ") .. " found (see README)"
  end
  local cfg, err = M.load(path)
  if not cfg then
    return nil, err
  end
  return M.profile(cfg, name, vim.fs.dirname(path))
end

---@class OpenBaoFetch
---@field env table<string, string> variable name -> value (merged)
---@field owner table<string, integer> variable name -> index of the source providing it
---@field remote { data: table, version: integer }[] raw secret of each source
---@field skipped string[] non-string values that cannot be environment variables
---@field key table<string, string> variable name -> original key in its source (differs with `to_env`)
---@field collisions string[] variables where two keys of one source map to the same name (`to_env`)

--- Spring Boot's relaxed binding for environment variables: dots become `_`, dashes are dropped,
--- upper case. Names that already look like variables (`MY_VAR`) are left alone. Pure.
---@param name string
---@return string
function M.env_name(name)
  if name:match("^[A-Z_][A-Z0-9_]*$") then
    return name
  end
  local out = name:gsub("%-", ""):gsub("[^%w]", "_"):upper()
  return (out:gsub("^(%d)", "_%1"))
end

---@param profile OpenBaoProfile
---@param cb fun(err: string?, fetched: OpenBaoFetch?)
function M.fetch(profile, cb)
  util.map_limit(profile.sources, 4, function(source, done)
    kv.get(source.path, nil, function(err, secret)
      done({ err = err, secret = secret })
    end)
  end, function(results)
    local fetched = { env = {}, owner = {}, remote = {}, skipped = {}, key = {}, collisions = {} }
    for i, r in ipairs(results) do
      if r.err then
        return cb(("%s: %s"):format(profile.sources[i].path, r.err.msg))
      end
      fetched.remote[i] = r.secret
      local only
      if profile.sources[i].only then
        only = {}
        for _, k in ipairs(profile.sources[i].only) do
          only[k] = true
        end
      end
      for _, key in ipairs(util.sorted_keys(r.secret.data)) do
        local value = r.secret.data[key]
        local name = profile.sources[i].prefix .. key
        if profile.sources[i].to_env then
          name = M.env_name(name)
        end
        if only and not only[key] then
          -- filtered out on purpose
        elseif type(value) ~= "string" then
          fetched.skipped[#fetched.skipped + 1] = name
        elseif fetched.owner[name] == i then
          -- keys are visited in sorted order: the first one is kept, the other is reported
          fetched.collisions[#fetched.collisions + 1] = name
        else
          fetched.env[name] = value
          fetched.owner[name] = i
          fetched.key[name] = key
        end
      end
    end
    cb(nil, fetched)
  end)
end

--- Creates the file with owner-only permissions before any secret is written to it.
---@param path string
---@param env table<string, string>
---@param sources OpenBaoSource[]
---@param disabled? table<string, true> variables written commented out (`# KEY=value`)
function M.write_file(path, env, sources, disabled)
  disabled = disabled or {}
  local fd = assert(vim.uv.fs_open(path, "w", tonumber("600", 8)))
  vim.uv.fs_close(fd)
  vim.uv.fs_chmod(path, tonumber("600", 8))
  local from = vim.tbl_map(function(s)
    return s.path
  end, sources)
  local lines = { "# Generated by openbao.nvim from: " .. table.concat(from, ", "), "# Do not commit." }
  for _, name in ipairs(util.sorted_keys(env)) do
    local line = format.dotenv_lines({ [name] = env[name] })[1]
    lines[#lines + 1] = disabled[name] and ("# " .. line) or line
  end
  vim.fn.writefile(lines, path)
end

--- Adds `path` (by basename) to the .gitignore next to it, if missing.
---@param path string
---@return boolean added
function M.gitignore(path)
  local gitignore = vim.fs.joinpath(vim.fs.dirname(path), ".gitignore")
  local name = vim.fs.basename(path)
  local lines = vim.fn.filereadable(gitignore) == 1 and vim.fn.readfile(gitignore) or {}
  if vim.tbl_contains(lines, name) or vim.tbl_contains(lines, "/" .. name) then
    return false
  end
  lines[#lines + 1] = name
  vim.fn.writefile(lines, gitignore)
  return true
end

--- Offers to .gitignore the generated file when git does not ignore it yet.
---@param path string
local function offer_gitignore(path)
  vim.system({ "git", "check-ignore", "-q", path }, { cwd = vim.fs.dirname(path) }, function(r)
    if r.code ~= 1 then
      return -- ignored already (0) or not a git repository (128)
    end
    vim.schedule(function()
      vim.ui.select({ "Add to .gitignore", "Not now" }, {
        prompt = vim.fs.basename(path) .. " holds secrets and is not git-ignored",
      }, function(choice)
        if choice == "Add to .gitignore" then
          M.gitignore(path)
          util.notify("added " .. vim.fs.basename(path) .. " to .gitignore")
        end
      end)
    end)
  end)
end

---@param profile OpenBaoProfile
---@param cb? fun(err: string?, count: integer?)
function M.pull(profile, cb)
  cb = cb or function() end
  M.fetch(profile, function(err, fetched)
    if err then
      util.error(err)
      return cb(err)
    end
    local count = vim.tbl_count(fetched.env)
    -- lines the user commented out in the file stay commented (with the fresh value) and are not injected
    local disabled = {}
    if profile.file and vim.fn.filereadable(profile.file) == 1 then
      for name in pairs(format.disabled_names(vim.fn.readfile(profile.file))) do
        disabled[name] = fetched.env[name] ~= nil or nil
      end
    end
    if profile.vim_env then
      for name, value in pairs(fetched.env) do
        if not disabled[name] then
          vim.env[name] = value
        end
      end
    end
    if profile.file then
      M.write_file(profile.file, fetched.env, profile.sources, disabled)
      offer_gitignore(profile.file)
    end
    local where = {}
    if profile.vim_env then
      where[#where + 1] = "vim.env"
    end
    if profile.file then
      where[#where + 1] = vim.fs.basename(profile.file)
    end
    util.notify(("pulled %d variable(s) [%s] into %s"):format(count, profile.name, table.concat(where, " + ")))
    if #fetched.skipped > 0 then
      util.notify("skipped non-string values: " .. table.concat(fetched.skipped, ", "), vim.log.levels.WARN)
    end
    if #fetched.collisions > 0 then
      util.notify(
        "several keys map to the same variable, only the first is kept: " .. table.concat(fetched.collisions, ", "),
        vim.log.levels.WARN
      )
    end
    cb(nil, count)
  end)
end

---@type string[] names set by the last `load_file`, removed again by the next load or `unload`
local loaded = {}

--- Directory searched for `.env*` files: the project file's, else the cwd.
---@return string
function M.files_root()
  local project = M.find_file()
  return project and vim.fs.dirname(project) or vim.fn.getcwd()
end

--- `.env` and `.env.*` files of a directory, sorted.
---@param root? string
---@return string[] names basenames
function M.list_files(root)
  local names = {}
  for name, kind in vim.fs.dir(root or M.files_root()) do
    if kind == "file" and (name == ".env" or name:find("^%.env%.")) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

--- Remove from `vim.env` the variables set by the previous `load_file`.
---@return integer count
function M.unload()
  local count = #loaded
  for _, name in ipairs(loaded) do
    vim.env[name] = nil
  end
  loaded = {}
  return count
end

--- Put the variables of a dotenv file into `vim.env` (no shell involved: `$`, backticks and accents are kept as is).
--- Edit the file first to load only some of them. Replaces what the previous `load_file` set.
---@param path string
---@return integer? count
---@return string? err
function M.load_file(path)
  path = vim.fn.fnamemodify(path, ":p")
  if vim.fn.filereadable(path) == 0 then
    return nil, "cannot read " .. path
  end
  local data, errors = format.parse_dotenv(vim.fn.readfile(path))
  if not data then
    return nil, ("%s: %s"):format(vim.fs.basename(path), table.concat(errors or {}, "; "))
  end
  M.unload()
  for _, name in ipairs(util.sorted_keys(data)) do
    vim.env[name] = data[name]
    loaded[#loaded + 1] = name
  end
  return #loaded
end

--- Local values to compare with: the generated file, else the current `vim.env`.
---@param profile OpenBaoProfile
---@param names string[]
---@return table<string, string>? values
---@return string? err
---@return table<string, true>? disabled
local function local_values(profile, names)
  if profile.file then
    if vim.fn.filereadable(profile.file) == 0 then
      return {}
    end
    local data, errs = format.parse_dotenv(vim.fn.readfile(profile.file))
    if not data then
      return nil, profile.file .. ": " .. table.concat(errs, "; ")
    end
    -- a commented-out variable is a deliberate choice, not a difference: treat it as equal to the remote
    local disabled = format.disabled_names(vim.fn.readfile(profile.file))
    return data, nil, disabled
  end
  local values = {}
  for _, name in ipairs(names) do
    values[name] = vim.env[name]
  end
  return values
end

--- Remote vs local: `added` = only local, `removed` = only remote.
---@param profile OpenBaoProfile
---@param cb fun(err: string?, diff: OpenBaoDiff?)
function M.status(profile, cb)
  M.fetch(profile, function(err, fetched)
    if err then
      return cb(err)
    end
    local values, lerr, disabled = local_values(profile, util.sorted_keys(fetched.env))
    if not values then
      return cb(lerr)
    end
    for name in pairs(disabled or {}) do
      if values[name] == nil then
        values[name] = fetched.env[name]
      end
    end
    cb(nil, format.diff(fetched.env, values))
  end)
end

---@class OpenBaoPushPlan
---@field source_idx integer
---@field data table<string, any> new content of the source secret
---@field diff OpenBaoDiff

--- Pure: what a push would write, per source. New variables go to `push_to`; removals need `prune`.
---@param profile OpenBaoProfile
---@param fetched OpenBaoFetch
---@param values table<string, string> local variables
---@param prune boolean
---@return OpenBaoPushPlan[] plans
---@return string[] warnings
function M.plan_push(profile, fetched, values, prune)
  local sets, removes, warnings = {}, {}, {}
  local function bucket(t, idx)
    t[idx] = t[idx] or {}
    return t[idx]
  end
  -- `to_env` renames are one-way, so the original key is remembered at fetch time
  local function key_of(name, idx)
    return fetched.key and fetched.key[name] or name:sub(#profile.sources[idx].prefix + 1)
  end
  for name, value in pairs(values) do
    local idx = fetched.owner[name]
    if idx then
      if fetched.env[name] ~= value then
        bucket(sets, idx)[key_of(name, idx)] = value
      end
    else
      local target = profile.sources[profile.push_to]
      local only = target.only and vim.tbl_contains(target.only, name:sub(#target.prefix + 1))
      if target.to_env then
        warnings[#warnings + 1] = ("%s ignored: new variables cannot be pushed to %s (`to_env` renames are one-way)"):format(
          name,
          target.path
        )
      elseif name:sub(1, #target.prefix) ~= target.prefix then
        warnings[#warnings + 1] = ("%s ignored: it does not start with the prefix '%s' of %s"):format(
          name,
          target.prefix,
          target.path
        )
      elseif target.only and not only then
        warnings[#warnings + 1] = ("%s ignored: not in the `only` list of %s"):format(name, target.path)
      else
        bucket(sets, profile.push_to)[name:sub(#target.prefix + 1)] = value
      end
    end
  end
  if prune then
    for name, idx in pairs(fetched.owner) do
      if values[name] == nil then
        table.insert(bucket(removes, idx), key_of(name, idx))
      end
    end
  end
  local plans = {}
  for idx = 1, #profile.sources do
    if sets[idx] or removes[idx] then
      local old = fetched.remote[idx].data
      local new = vim.deepcopy(old)
      for k, v in pairs(sets[idx] or {}) do
        new[k] = v
      end
      for _, k in ipairs(removes[idx] or {}) do
        new[k] = nil
      end
      local diff = format.diff(old, new)
      if not format.is_empty(diff) then
        plans[#plans + 1] = { source_idx = idx, data = new, diff = diff }
      end
    end
  end
  return plans, warnings
end

---@param profile OpenBaoProfile
---@param opts? { prune?: boolean }
---@param cb? fun(err: string?)
function M.push(profile, opts, cb)
  opts, cb = opts or {}, cb or function() end
  if not profile.file then
    local msg = "push needs a `file` in the profile (the .env file is the local source of truth)"
    util.error(msg)
    return cb(msg)
  end
  if vim.fn.filereadable(profile.file) == 0 then
    local msg = profile.file .. " does not exist: run `:Bao env pull` first"
    util.error(msg)
    return cb(msg)
  end
  local values, perr, disabled = local_values(profile, {})
  if not values then
    util.error(perr)
    return cb(perr)
  end
  M.fetch(profile, function(err, fetched)
    if err then
      util.error(err)
      return cb(err)
    end
    -- commented-out variables must neither be pruned nor pushed
    for name in pairs(disabled or {}) do
      if values[name] == nil then
        values[name] = fetched.env[name]
      end
    end
    local plans, warnings = M.plan_push(profile, fetched, values, opts.prune == true)
    for _, w in ipairs(warnings) do
      util.notify(w, vim.log.levels.WARN)
    end
    if #plans == 0 then
      util.notify("nothing to push")
      return cb(nil)
    end
    local summary = {}
    for _, p in ipairs(plans) do
      summary[#summary + 1] = profile.sources[p.source_idx].path .. ": " .. format.describe(p.diff)
    end
    vim.ui.select(
      { "Push", "Cancel" },
      { prompt = "Push to OpenBao?\n" .. table.concat(summary, "\n") },
      function(choice)
        if choice ~= "Push" then
          return cb("cancelled")
        end
        util.map_limit(plans, 1, function(plan, done)
          local source = profile.sources[plan.source_idx]
          kv.put(
            source.path,
            plan.data,
            { cas = config.options.cas and fetched.remote[plan.source_idx].version or nil },
            function(perr2)
              done(perr2 and (source.path .. ": " .. perr2.msg) or false)
            end
          )
        end, function(results)
          local failures = vim.tbl_filter(function(r)
            return r
          end, results)
          if #failures > 0 then
            util.error("push failed:\n" .. table.concat(failures, "\n"))
            return cb(table.concat(failures, "; "))
          end
          util.notify(("pushed %d secret(s)"):format(#plans))
          cb(nil)
        end)
      end
    )
  end)
end

return M
