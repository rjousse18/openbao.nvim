local M = {}

function M.check()
  local health = vim.health
  health.start("openbao.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim >= 0.10")
  else
    health.error("Neovim >= 0.10 is required (vim.system)")
  end

  local cli = require("openbao.cli")
  local bin, err = cli.binary()
  if not bin then
    return health.error(err or "no binary")
  end
  local vdone, version = false, nil
  cli.run({ "version" }, nil, function(res)
    vdone, version = true, res
  end)
  vim.wait(10000, function()
    return vdone
  end, 20)
  if version and version.ok then
    health.ok(("%s: %s"):format(bin, vim.trim(version.stdout)))
  else
    health.warn(("`%s version` failed: %s"):format(bin, version and version.stderr or "timeout"))
  end

  local config = require("openbao.config").options
  local addr = config.address or vim.env.BAO_ADDR or vim.env.VAULT_ADDR
  if addr then
    health.ok("address: " .. addr)
  else
    health.warn("no address (set BAO_ADDR / VAULT_ADDR or the `address` option)")
  end

  local done, valid, res = false, false, nil
  require("openbao.auth").check(function(v, r)
    done, valid, res = true, v, r
  end)
  vim.wait(10000, function()
    return done
  end, 20)
  if valid then
    health.ok("authenticated")
  else
    health.warn(
      "not authenticated: run :Bao login"
        .. (res and res.stderr ~= "" and (" (" .. res.stderr:gsub("\n", " ") .. ")") or "")
    )
  end

  if config.mounts or config.default_mount then
    health.ok("mounts configured by option")
  elseif valid then
    done = false
    local list
    require("openbao.mounts").list(function(m)
      done, list = true, m
    end)
    vim.wait(10000, function()
      return done
    end, 20)
    if list and #list > 0 then
      health.ok("KV v2 mounts: " .. table.concat(list, ", "))
    else
      health.warn("no KV v2 mount found: set the `mounts` or `default_mount` option")
    end
  end

  local picker = require("openbao.picker").detect()
  health.ok("picker: " .. picker)
end

return M
