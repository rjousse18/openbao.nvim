--- `cli.run` plus automatic re-authentication: every module talks to the CLI through here.
local auth = require("openbao.auth")
local cli = require("openbao.cli")
local config = require("openbao.config")

local M = {}

local AUTH_HINTS = { "permission denied", "missing client token", "invalid token", "token is expired", "code: 403" }

---@param res OpenBaoResult
---@return boolean
function M.looks_like_auth_error(res)
  local err = res.stderr:lower()
  for _, hint in ipairs(AUTH_HINTS) do
    if err:find(hint, 1, true) then
      return true
    end
  end
  return false
end

--- On an auth-looking failure, checks the token: a valid token means a policy denial
--- (reported as is); an invalid one offers to log in, then retries the call once.
---@param args string[]
---@param opts? { stdin?: string, json?: boolean, timeout?: integer }
---@param cb fun(res: OpenBaoResult)
function M.call(args, opts, cb)
  cli.run(args, opts, function(res)
    if res.ok or not config.options.login.auto or not M.looks_like_auth_error(res) then
      return cb(res)
    end
    auth.check(function(valid)
      if valid then
        return cb(res)
      end
      auth.prompt_login(function(logged_in)
        if logged_in then
          cli.run(args, opts, cb)
        else
          cb(res)
        end
      end)
    end)
  end)
end

return M
