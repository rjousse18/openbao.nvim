local M = {}

---@param msg string
---@param level? integer
function M.notify(msg, level)
  vim.notify("openbao: " .. msg, level or vim.log.levels.INFO)
end

---@param msg string
function M.error(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

--- Runs `fn(item, done)` over `items` with at most `limit` calls in flight.
--- `done(result)` must be called exactly once per item; `final(results)` gets results in item order.
---@generic T, R
---@param items T[]
---@param limit integer
---@param fn fun(item: T, done: fun(res: R))
---@param final fun(results: R[])
function M.map_limit(items, limit, fn, final)
  local n = #items
  if n == 0 then
    return final({})
  end
  local results, next_i, running, finished = {}, 1, 0, 0
  local function launch()
    while running < limit and next_i <= n do
      local i = next_i
      next_i = next_i + 1
      running = running + 1
      fn(items[i], function(res)
        results[i] = res
        running = running - 1
        finished = finished + 1
        if finished == n then
          final(results)
        else
          launch()
        end
      end)
    end
  end
  launch()
end

---@param t table
---@return string[]
function M.sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

--- Joins path segments with a single "/" and no leading/trailing "/".
---@param ... string
---@return string
function M.join(...)
  local parts = {}
  for _, p in ipairs({ ... }) do
    p = p:gsub("^/+", ""):gsub("/+$", "")
    if p ~= "" then
      parts[#parts + 1] = p
    end
  end
  return table.concat(parts, "/")
end

---@param path string
---@return string
function M.parent(path)
  return (path:gsub("/?[^/]*$", ""))
end

return M
