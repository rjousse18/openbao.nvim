--- The `:Bao` command: subcommand dispatch and completion.
local util = require("openbao.util")

local M = {}

---@class OpenBaoSubcommand
---@field desc string
---@field run fun(args: string[], flags: table<string, boolean>)
---@field complete? fun(args: string[]): string[]

---@return string? full path of the OpenBao buffer in the current window
local function current_path()
  local st = require("openbao.buffer").state(vim.api.nvim_get_current_buf())
  return st and st.full or nil
end

---@param args string[]
---@return string?
local function path_arg(args)
  return args[1] or current_path()
end

---@return string[]
local function path_candidates()
  local out = vim.deepcopy(require("openbao.config").options.mounts or {})
  vim.list_extend(out, require("openbao.browse").known_paths())
  return out
end

---@param name string
---@return OpenBaoProfile?
local function profile_or_error(name)
  local profile, err = require("openbao.env").resolve(name)
  if not profile then
    util.error(err or "no profile")
  end
  return profile
end

---@type table<string, OpenBaoSubcommand>
M.subcommands = {
  login = {
    desc = "log in (config.login.method, oidc by default)",
    run = function()
      require("openbao.auth").login()
    end,
  },
  status = {
    desc = "show the current token (user, policies, ttl)",
    run = function()
      require("openbao.auth").status(function(lines, err)
        if lines then
          util.notify(table.concat(lines, "\n"))
        else
          util.error("not authenticated: " .. tostring(err) .. "\n(run :Bao login)")
        end
      end)
    end,
  },
  browse = {
    desc = "browse mounts and folders level by level",
    run = function(args)
      require("openbao.browse").browse(args[1])
    end,
    complete = path_candidates,
  },
  search = {
    desc = "fuzzy-search every secret path (optionally under a prefix)",
    run = function(args)
      require("openbao.browse").search(args[1])
    end,
    complete = path_candidates,
  },
  edit = {
    desc = "edit a secret in a buffer (:w writes to OpenBao)",
    run = function(args)
      if args[1] then
        require("openbao.buffer").open(args[1])
      else
        require("openbao.browse").browse("")
      end
    end,
    complete = path_candidates,
  },
  new = {
    desc = "create a secret (the buffer is written with :w)",
    run = function(args)
      if not args[1] then
        return util.error("usage: :Bao new <mount/path>")
      end
      require("openbao.buffer").open(args[1], { create = true })
    end,
    complete = path_candidates,
  },
  reload = {
    desc = "re-read the secret of the current buffer",
    run = function()
      require("openbao.buffer").reload()
    end,
  },
  diff = {
    desc = "diff the current secret buffer against the server version",
    run = function()
      require("openbao.buffer").diff()
    end,
  },
  reveal = {
    desc = "show / hide values in the current secret buffer",
    run = function()
      require("openbao.buffer").toggle_reveal(vim.api.nvim_get_current_buf())
    end,
  },
  versions = {
    desc = "history of a secret: view, rollback, undelete",
    run = function(args)
      local path = path_arg(args)
      if not path then
        return util.error("usage: :Bao versions <mount/path>")
      end
      require("openbao.history").show(path)
    end,
    complete = path_candidates,
  },
  delete = {
    desc = "soft-delete the latest version of a secret (undo from :Bao versions)",
    run = function(args)
      local path = path_arg(args)
      if not path then
        return util.error("usage: :Bao delete <mount/path>")
      end
      vim.ui.select({ "Delete", "Cancel" }, { prompt = "Delete latest version of " .. path .. "?" }, function(choice)
        if choice ~= "Delete" then
          return
        end
        require("openbao.kv").delete(path, function(err)
          if err then
            return util.error(err.msg)
          end
          util.notify("deleted " .. path .. " (recover it from :Bao versions)")
          local buf = require("openbao.buffer").find(path)
          if buf then
            vim.api.nvim_buf_delete(buf, { force = true })
          end
        end)
      end)
    end,
    complete = path_candidates,
  },
  env = {
    desc = "env pull|push|status|gitignore [profile] [--prune]: sync a project's environment",
    run = function(args, flags)
      local action, name = args[1], args[2]
      local env = require("openbao.env")
      if action == "pull" then
        local p = profile_or_error(name)
        if p then
          env.pull(p)
        end
      elseif action == "push" then
        local p = profile_or_error(name)
        if p then
          env.push(p, { prune = flags.prune })
        end
      elseif action == "status" then
        local p = profile_or_error(name)
        if p then
          env.status(p, function(err, diff)
            if err then
              return util.error(err)
            end
            local f = require("openbao.format")
            util.notify(
              f.is_empty(diff) and "local and remote are in sync"
                or ("remote -> local: " .. f.describe(diff) .. "\n(+ only local, ~ different, - missing locally)")
            )
          end)
        end
      elseif action == "gitignore" then
        local p = profile_or_error(name)
        if p and p.file then
          util.notify(env.gitignore(p.file) and "added to .gitignore" or "already in .gitignore")
        elseif p then
          util.error("this profile has no `file`")
        end
      else
        util.error("usage: :Bao env pull|push|status|gitignore [profile] [--prune]")
      end
    end,
    complete = function(args)
      if #args == 0 then
        return { "pull", "push", "status", "gitignore" }
      end
      return { "--prune" }
    end,
  },
  project = {
    desc = "project pull|status|push [prefixes] [--force]: local mirror of secrets",
    run = function(args, flags)
      local action = table.remove(args, 1)
      local project = require("openbao.project")
      if action == "pull" then
        project.pull(args, { force = flags.force })
      elseif action == "status" then
        project.status()
      elseif action == "push" then
        project.push({ force = flags.force })
      else
        util.error("usage: :Bao project pull|status|push [prefixes] [--force]")
      end
    end,
    complete = function(args)
      if #args == 0 then
        return { "pull", "status", "push" }
      end
      return vim.list_extend({ "--force" }, path_candidates())
    end,
  },
}

---@param opts { fargs: string[] }
function M.run(opts)
  local name = opts.fargs[1]
  local sub = name and M.subcommands[name]
  if not sub then
    local names = util.sorted_keys(M.subcommands)
    return util.error(("usage: :Bao <%s>"):format(table.concat(names, "|")))
  end
  local args, flags = {}, {}
  for i = 2, #opts.fargs do
    local a = opts.fargs[i]
    if a:sub(1, 2) == "--" then
      flags[a:sub(3)] = true
    else
      args[#args + 1] = a
    end
  end
  sub.run(args, flags)
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  local parts = vim.split(vim.trim(cmdline), "%s+")
  local typing_new = cmdline:match("%s$") ~= nil
  local nargs = #parts - 1 + (typing_new and 1 or 0)
  local candidates
  if nargs <= 1 then
    candidates = util.sorted_keys(M.subcommands)
  else
    local sub = M.subcommands[parts[2]]
    local given = vim.list_slice(parts, 3, typing_new and #parts or #parts - 1)
    candidates = sub and sub.complete and sub.complete(given) or {}
  end
  return vim.tbl_filter(function(c)
    return vim.startswith(c, arglead)
  end, candidates)
end

return M
