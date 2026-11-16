--- Secret buffers: `openbao://mount/path`, `:w` writes back to OpenBao.
local config = require("openbao.config")
local format = require("openbao.format")
local kv = require("openbao.kv")
local util = require("openbao.util")

local M = {}

local ns = vim.api.nvim_create_namespace("openbao")

---@class OpenBaoBufState
---@field full string
---@field format "dotenv"|"json"
---@field data table<string, any> last known remote content
---@field version integer 0 for a secret that does not exist yet
---@field new boolean
---@field readonly boolean
---@field saving boolean
---@field revealed boolean

---@type table<integer, OpenBaoBufState>
local states = {}

---@param buf integer
---@return OpenBaoBufState?
function M.state(buf)
  return states[buf]
end

---@param full string
---@param version? integer
---@return string
function M.name(full, version)
  return "openbao://" .. full .. (version and ("@v" .. version) or "")
end

--- Finds the buffer showing `full` (latest version), if any.
---@param full string
---@return integer?
function M.find(full)
  for buf, st in pairs(states) do
    if st.full == full and not st.readonly and vim.api.nvim_buf_is_valid(buf) then
      return buf
    end
  end
end

--- Value column of a line, or nil when the line holds no value.
---@param line string
---@param fmt "dotenv"|"json"
---@return integer?
local function value_col(line, fmt)
  local prefix
  if fmt == "json" then
    prefix = line:match('^%s*"[^"]*":%s*')
  else
    prefix = line:match("^%s*[^=%s#][^=]*=")
  end
  if prefix and #prefix < #line then
    return #prefix
  end
end

---@param buf integer
local function apply_conceal(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local st = states[buf]
  if not st or st.revealed or not config.options.conceal then
    return
  end
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local col = value_col(line, st.format)
    if col then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col, { end_col = #line, conceal = "*" })
    end
  end
end

---@param buf integer
function M.toggle_reveal(buf)
  local st = states[buf]
  if st then
    st.revealed = not st.revealed
    apply_conceal(buf)
  end
end

--- Secrets must not leak to disk through swap or undo files (BufWriteCmd never writes the buffer to disk).
---@param buf integer
local function harden(buf)
  vim.bo[buf].swapfile = false
  vim.bo[buf].undofile = false
  vim.bo[buf].undolevels = -1
end

---@param buf integer
---@param force boolean `:w!` skips check-and-set
function M.write(buf, force)
  local st = states[buf]
  if not st or st.readonly then
    return util.error("this buffer is read-only")
  end
  if st.saving then
    return
  end
  local data, errs = format.parse(st.format, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if not data then
    return util.error("cannot save, fix first:\n" .. table.concat(errs, "\n"))
  end
  if next(data) == nil then
    return util.error("refusing to write an empty secret (use `:Bao delete`)")
  end
  local diff = format.diff(st.data, data)
  if format.is_empty(diff) and not st.new then
    vim.bo[buf].modified = false
    return util.notify("no changes")
  end

  local function send()
    st.saving = true
    local cas = (config.options.cas and not force) and st.version or nil
    kv.put(st.full, data, { cas = cas }, function(err, version)
      st.saving = false
      if err then
        if err.kind == "cas" then
          return util.error("changed remotely since you opened it: `:Bao reload` to refresh, `:w!` to overwrite")
        end
        return util.error("save failed: " .. err.msg)
      end
      st.data, st.new = data, false
      st.version = version or (st.version + 1)
      if vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modified = false
        apply_conceal(buf)
      end
      util.notify(("saved %s (v%d)"):format(st.full, st.version))
    end)
  end

  if #diff.removed > 0 and config.options.confirm_deletions then
    vim.ui.select({ "Write", "Cancel" }, {
      prompt = "Keys will be REMOVED from " .. st.full .. ": " .. table.concat(diff.removed, ", "),
    }, function(choice)
      if choice == "Write" then
        send()
      end
    end)
  else
    send()
  end
end

---@param full string
---@param secret OpenBaoSecret
---@param opts { version?: integer, new?: boolean }
---@return integer buf
local function show(full, secret, opts)
  local name = M.name(full, opts.version)
  local buf
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b) == name then
      buf = b
    end
  end
  if not buf then
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
  end
  local fmt = format.classify(secret.data)
  states[buf] = {
    full = full,
    format = fmt,
    data = secret.data,
    version = opts.version or secret.version,
    new = opts.new or false,
    readonly = opts.version ~= nil,
    saving = false,
    revealed = false,
  }
  harden(buf)
  vim.bo[buf].buftype = opts.version and "nofile" or "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, format.to_lines(fmt, secret.data))
  vim.bo[buf].filetype = fmt
  vim.bo[buf].modified = opts.new or false
  vim.bo[buf].modifiable = not opts.version
  vim.b[buf].openbao = { path = full, version = states[buf].version }

  local group = vim.api.nvim_create_augroup("openbao_buf_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "BufWriteCmd" }, {
    group = group,
    buffer = buf,
    callback = function()
      M.write(buf, vim.v.cmdbang == 1)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function()
      apply_conceal(buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      states[buf] = nil
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = buf,
    callback = function()
      if config.options.conceal then
        vim.wo.conceallevel = 2
        vim.wo.concealcursor = "nvic"
      end
    end,
  })
  if config.options.reveal_key then
    vim.keymap.set("n", config.options.reveal_key, function()
      M.toggle_reveal(buf)
    end, { buffer = buf, desc = "OpenBao: show / hide values" })
  end
  apply_conceal(buf)
  return buf
end

--- Opens a secret in a window.
---@param full string "mount/path"
---@param opts? { version?: integer, create?: boolean }
function M.open(full, opts)
  opts = opts or {}
  local existing = not opts.version and M.find(full)
  if existing and vim.bo[existing].modified then
    return vim.api.nvim_win_set_buf(0, existing)
  end
  kv.get(full, { version = opts.version }, function(err, secret)
    if err and opts.create and err.kind == "not_found" then
      err, secret = nil, { data = {}, version = 0 }
    end
    if err then
      local hint = err.kind == "not_found" and " (create it with `:Bao new " .. full .. "`)" or ""
      return util.error(("%s: %s%s"):format(full, err.msg, hint))
    end
    local buf = show(full, secret, { version = opts.version, new = opts.create and secret.version == 0 })
    vim.api.nvim_win_set_buf(0, buf)
  end)
end

--- Re-reads the secret behind `buf` (asks before dropping unsaved edits).
---@param buf? integer
function M.reload(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local st = states[buf]
  if not st then
    return util.error("not an OpenBao buffer")
  end
  local function go()
    kv.get(st.full, { version = st.readonly and st.version or nil }, function(err, secret)
      if err then
        return util.error(err.msg)
      end
      show(st.full, secret, { version = st.readonly and st.version or nil })
    end)
  end
  if vim.bo[buf].modified then
    vim.ui.select({ "Discard my changes", "Cancel" }, { prompt = "Unsaved changes in " .. st.full }, function(choice)
      if choice == "Discard my changes" then
        go()
      end
    end)
  else
    go()
  end
end

return M
