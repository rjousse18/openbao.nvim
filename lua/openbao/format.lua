--- Pure text <-> secret conversion (no Neovim UI, no CLI): dotenv for flat string secrets, JSON otherwise.
local util = require("openbao.util")

local M = {}

local KEY_PATTERN = "^[%w_%.%-]+$"
local BARE_PATTERN = "^[%w_%./:@%+,=%%%-]*$"

---@param s string
---@return string
local function quote(s)
  if s:match(BARE_PATTERN) then
    return s
  end
  local escaped = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
  return '"' .. escaped .. '"'
end

---@param s string body of a double-quoted value (without the quotes)
---@return string
local function unescape(s)
  local map = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\" }
  return (s:gsub("\\(.)", function(c)
    return map[c] or ("\\" .. c)
  end))
end

--- "dotenv" when every key is dotenv-safe and every value a string, else "json" (lossless).
---@param data table<string, any>
---@return "dotenv"|"json"
function M.classify(data)
  for k, v in pairs(data) do
    if type(v) ~= "string" or not k:match(KEY_PATTERN) then
      return "json"
    end
  end
  return "dotenv"
end

---@param data table<string, string>
---@return string[] lines
function M.dotenv_lines(data)
  local lines = {}
  for _, k in ipairs(util.sorted_keys(data)) do
    lines[#lines + 1] = k .. "=" .. quote(data[k])
  end
  return lines
end

--- Parses `KEY=value` lines. Blank lines and `#` comments are ignored (and not stored).
---@param lines string[]
---@return table<string, string>? data
---@return string[]? errors "line N: message"
function M.parse_dotenv(lines)
  local data, errors = {}, {}
  for i, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
      trimmed = trimmed:gsub("^export%s+", "")
      local key, raw = trimmed:match("^([^=%s]+)%s*=%s*(.*)$")
      if not key then
        errors[#errors + 1] = ("line %d: expected KEY=value"):format(i)
      elseif data[key] ~= nil then
        errors[#errors + 1] = ("line %d: duplicate key '%s'"):format(i, key)
      elseif raw:sub(1, 1) == '"' then
        local body = raw:match('^"(.*)"%s*$')
        local trailing = body and body:match("\\*$") or ""
        if body and #trailing % 2 == 0 then
          data[key] = unescape(body)
        else
          errors[#errors + 1] = ("line %d: unterminated quote"):format(i)
        end
      elseif raw:sub(1, 1) == "'" then
        local body = raw:match("^'(.*)'%s*$")
        if body then
          data[key] = body
        else
          errors[#errors + 1] = ("line %d: unterminated quote"):format(i)
        end
      else
        data[key] = vim.trim(raw)
      end
    end
  end
  if #errors > 0 then
    return nil, errors
  end
  return data
end

---@param v any
---@param indent string
---@return string
local function encode_pretty(v, indent)
  if type(v) ~= "table" then
    return vim.json.encode(v)
  end
  if next(v) == nil then
    return vim.islist(v) and getmetatable(v) == nil and "[]" or "{}"
  end
  local inner = indent .. "  "
  local parts = {}
  if vim.islist(v) then
    for _, item in ipairs(v) do
      parts[#parts + 1] = inner .. encode_pretty(item, inner)
    end
    return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
  end
  for _, k in ipairs(util.sorted_keys(v)) do
    parts[#parts + 1] = inner .. vim.json.encode(k) .. ": " .. encode_pretty(v[k], inner)
  end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

---@param data table
---@return string[] lines
function M.json_lines(data)
  return vim.split(encode_pretty(data, ""), "\n", { plain = true })
end

---@param lines string[]
---@return table? data
---@return string[]? errors
function M.parse_json(lines)
  local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok then
    return nil, { tostring(decoded) }
  end
  if type(decoded) ~= "table" or (next(decoded) ~= nil and vim.islist(decoded)) then
    return nil, { "the top level must be a JSON object" }
  end
  return decoded
end

---@param format "dotenv"|"json"
---@param data table
---@return string[]
function M.to_lines(format, data)
  if format == "json" then
    return M.json_lines(data)
  end
  return M.dotenv_lines(data)
end

---@param format "dotenv"|"json"
---@param lines string[]
---@return table? data
---@return string[]? errors
function M.parse(format, lines)
  if format == "json" then
    return M.parse_json(lines)
  end
  return M.parse_dotenv(lines)
end

---@class OpenBaoDiff
---@field added string[]
---@field changed string[]
---@field removed string[]

---@param old table<string, any>
---@param new table<string, any>
---@return OpenBaoDiff
function M.diff(old, new)
  local d = { added = {}, changed = {}, removed = {} }
  for _, k in ipairs(util.sorted_keys(new)) do
    if old[k] == nil then
      d.added[#d.added + 1] = k
    elseif not vim.deep_equal(old[k], new[k]) then
      d.changed[#d.changed + 1] = k
    end
  end
  for _, k in ipairs(util.sorted_keys(old)) do
    if new[k] == nil then
      d.removed[#d.removed + 1] = k
    end
  end
  return d
end

---@param d OpenBaoDiff
---@return boolean
function M.is_empty(d)
  return #d.added + #d.changed + #d.removed == 0
end

--- "+A ~B -C" style one-liner (key names only, never values).
---@param d OpenBaoDiff
---@return string
function M.describe(d)
  local parts = {}
  for _, k in ipairs(d.added) do
    parts[#parts + 1] = "+" .. k
  end
  for _, k in ipairs(d.changed) do
    parts[#parts + 1] = "~" .. k
  end
  for _, k in ipairs(d.removed) do
    parts[#parts + 1] = "-" .. k
  end
  return table.concat(parts, " ")
end

return M
