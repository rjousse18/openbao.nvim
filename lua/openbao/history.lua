--- `:Bao versions`: KV v2 history of a secret (view, rollback, undelete).
local buffer = require("openbao.buffer")
local kv = require("openbao.kv")
local picker = require("openbao.picker")
local util = require("openbao.util")

local M = {}

---@param v OpenBaoVersion
---@param current integer?
---@return string
local function label(v, current)
  local flags = {}
  if v.version == current then
    flags[#flags + 1] = "current"
  end
  if v.destroyed then
    flags[#flags + 1] = "destroyed"
  elseif v.deleted then
    flags[#flags + 1] = "deleted"
  end
  return ("v%d  %s%s"):format(
    v.version,
    v.created or "",
    #flags > 0 and ("  (" .. table.concat(flags, ", ") .. ")") or ""
  )
end

---@param full string
function M.show(full)
  kv.versions(full, function(err, versions, current)
    if err then
      return util.error(err.msg)
    end
    local items, by_label = {}, {}
    for _, v in ipairs(versions) do
      local l = label(v, current)
      items[#items + 1] = l
      by_label[l] = v
    end
    picker.select(items, { prompt = "History of " .. full }, function(choice)
      local v = choice and by_label[choice]
      if not v or v.destroyed then
        return
      end
      local actions = v.deleted and { "Undelete" } or { "View", "Rollback to this version" }
      vim.ui.select(actions, { prompt = ("%s v%d"):format(full, v.version) }, function(action)
        if action == "View" then
          buffer.open(full, { version = v.version })
        elseif action == "Undelete" then
          kv.undelete(full, { v.version }, function(e)
            util.notify(e and e.msg or ("undeleted v" .. v.version))
          end)
        elseif action == "Rollback to this version" then
          kv.rollback(full, v.version, function(e)
            if e then
              return util.error(e.msg)
            end
            util.notify(("rolled back %s to v%d (new version created)"):format(full, v.version))
            local buf = buffer.find(full)
            if buf and not vim.bo[buf].modified then
              buffer.reload(buf)
            end
          end)
        end
      end)
    end)
  end)
end

return M
