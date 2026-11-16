--- Shared test helpers: a fake `bao` binary with a throw-away store, and async waiting.
local config = require("openbao.config")

local M = {}

M.fake = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/fixtures/fake-bao"

--- Points the plugin at the fake binary with a fresh store; returns the store dir.
---@param seed? { secrets?: table<string, table[]>, token_valid?: boolean, mounts?: string[], login_fails?: boolean }
---@return string dir
function M.setup_fake(seed)
  seed = seed or {}
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local secrets = {}
  for path, data in pairs(seed.secrets or {}) do
    secrets[path] = { { data = data, created = "2026-01-01T00:00:00Z", deleted = false, destroyed = false } }
  end
  local store = {
    token_valid = seed.token_valid ~= false,
    mounts = seed.mounts or { "secret" },
    secrets = secrets,
    login_fails = seed.login_fails,
  }
  vim.fn.writefile({ vim.json.encode(store) }, dir .. "/store.json")
  config.setup({ binary = M.fake, env = { FAKE_BAO_DIR = dir }, login = { auto = true } })
  return dir
end

---@param dir string
---@return table
function M.store(dir)
  return vim.json.decode(table.concat(vim.fn.readfile(dir .. "/store.json"), "\n"))
end

---@param dir string
---@param path string
---@return table? latest data
function M.latest(dir, path)
  local versions = M.store(dir).secrets[path]
  return versions and versions[#versions].data
end

---@param dir string
---@return string[]
function M.calls(dir)
  return vim.fn.filereadable(dir .. "/calls.log") == 1 and vim.fn.readfile(dir .. "/calls.log") or {}
end

--- Runs an async function and waits for its callback; returns the callback arguments.
---@param start fun(done: fun(...))
---@return any ...
function M.await(start)
  local result, finished = nil, false
  start(function(...)
    result = vim.F.pack_len(...)
    finished = true
  end)
  assert(
    vim.wait(10000, function()
      return finished
    end, 10),
    "timed out waiting for callback"
  )
  return vim.F.unpack_len(result)
end

--- Replaces vim.ui.select with a stub answering from `answers` (matched by prompt substring).
--- Returns a restore function and the list of prompts seen.
---@param answers table<string, string> prompt substring -> choice
---@return fun() restore, string[] prompts
function M.stub_select(answers)
  local original = vim.ui.select
  local prompts = {}
  vim.ui.select = function(items, opts, cb)
    local prompt = (opts or {}).prompt or ""
    prompts[#prompts + 1] = prompt
    for needle, choice in pairs(answers) do
      if prompt:find(needle, 1, true) then
        return vim.schedule(function()
          cb(choice, vim.fn.index(items, choice) + 1)
        end)
      end
    end
    vim.schedule(function()
      cb(nil)
    end)
  end
  return function()
    vim.ui.select = original
  end, prompts
end

return M
