-- Optional end-to-end test against a real `bao server -dev` (or `vault server -dev`).
-- Run with `make integration`. Skipped unless OPENBAO_INTEGRATION=1 and the binary exists.
-- Not part of `make test`: it lives outside the *_spec.lua pattern scanned by PlenaryBustedDirectory.
local config = require("openbao.config")
local kv = require("openbao.kv")

local function await(start)
  local result, finished = nil, false
  start(function(...)
    result = vim.F.pack_len(...)
    finished = true
  end)
  assert(vim.wait(15000, function()
    return finished
  end, 20))
  return vim.F.unpack_len(result)
end

local bin = vim.fn.executable("bao") == 1 and "bao" or (vim.fn.executable("vault") == 1 and "vault" or nil)

if vim.env.OPENBAO_INTEGRATION ~= "1" or not bin then
  describe("integration (dev server)", function()
    pending("set OPENBAO_INTEGRATION=1 and install bao/vault to run")
  end)
  return
end

describe("integration (dev server)", function()
  local server
  setup(function()
    server = vim.system({ bin, "server", "-dev", "-dev-root-token-id=root", "-dev-listen-address=127.0.0.1:18200" })
    config.setup({
      env = {
        BAO_ADDR = "http://127.0.0.1:18200",
        VAULT_ADDR = "http://127.0.0.1:18200",
        BAO_TOKEN = "root",
        VAULT_TOKEN = "root",
      },
    })
    assert(
      vim.wait(20000, function()
        local res = await(function(done)
          require("openbao.cli").run({ "status" }, nil, done)
        end)
        return res.ok
      end, 300),
      "dev server did not start"
    )
  end)

  teardown(function()
    server:kill(15)
  end)

  it("detects the default KV v2 mount", function()
    local mounts = await(function(done)
      require("openbao.mounts").list(done)
    end)
    assert.is_true(vim.tbl_contains(mounts, "secret"))
  end)

  it("round-trips a secret with check-and-set, history and listing", function()
    assert.is_nil((await(function(done)
      kv.put("secret/it/app", { A = "1", B = "two words" }, { cas = 0 }, done)
    end)))
    local _, secret = await(function(done)
      kv.get("secret/it/app", nil, done)
    end)
    assert.are.same({ A = "1", B = "two words" }, secret.data)
    local err = await(function(done)
      kv.put("secret/it/app", { A = "2" }, { cas = 0 }, done)
    end)
    assert.are.equal("cas", err.kind)
    local _, entries = await(function(done)
      kv.list("secret/it", done)
    end)
    assert.are.same({ "app" }, entries)
    local _, versions = await(function(done)
      kv.versions("secret/it/app", done)
    end)
    assert.are.equal(1, #versions)
  end)
end)
