local cli = require("openbao.cli")
local config = require("openbao.config")
local util = require("openbao.util")

local M = {}

---@type fun(ok: boolean)[]?
local waiting = nil

--- Checks the current token (`token lookup`).
---@param cb fun(valid: boolean, res: OpenBaoResult)
function M.check(cb)
  cli.run({ "token", "lookup", "-format=json" }, { json = true }, function(res)
    cb(res.ok, res)
  end)
end

--- Runs `login -method=...`. Concurrent calls share a single login.
---@param cb? fun(ok: boolean)
function M.login(cb)
  cb = cb or function() end
  if waiting then
    waiting[#waiting + 1] = cb
    return
  end
  waiting = { cb }
  local o = config.options.login
  local args = { "login", "-no-print", "-method=" .. o.method }
  vim.list_extend(args, o.args)
  util.notify(("logging in (%s)... finish in your browser if it opens"):format(o.method))
  local url_shown = false
  cli.run(args, {
    timeout = o.timeout,
    on_output = function(chunk)
      local url = not url_shown and chunk:match("https?://%S+")
      if url then
        url_shown = true
        util.notify("if no browser opened, visit: " .. url)
      end
    end,
  }, function(res)
    local callbacks = waiting or {}
    waiting = nil
    if res.ok then
      util.notify("logged in")
    else
      util.error("login failed: " .. res.stderr)
    end
    for _, f in ipairs(callbacks) do
      f(res.ok)
    end
  end)
end

--- Asks before logging in, for the automatic path (a failed call).
---@param cb fun(ok: boolean)
function M.prompt_login(cb)
  if waiting then
    waiting[#waiting + 1] = cb
    return
  end
  vim.ui.select({ "Log in", "Cancel" }, { prompt = "OpenBao: not authenticated" }, function(choice)
    if choice == "Log in" then
      M.login(cb)
    else
      cb(false)
    end
  end)
end

--- Human-readable token summary for `:Bao status`.
---@param cb fun(lines: string[]?, err: string?)
function M.status(cb)
  M.check(function(valid, res)
    if not valid then
      return cb(nil, res.stderr)
    end
    local d = (res.json or {}).data or {}
    cb({
      "user: " .. tostring(d.display_name),
      "policies: " .. table.concat(d.policies or {}, ", "),
      "ttl: " .. tostring(d.ttl) .. "s",
    })
  end)
end

return M
