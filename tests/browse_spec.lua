local helpers = require("tests.helpers")
local browse = require("openbao.browse")
local buffer = require("openbao.buffer")
local config = require("openbao.config")
local history = require("openbao.history")
local picker = require("openbao.picker")

describe("picker.detect", function()
  it("honours an explicit choice", function()
    config.setup({ picker = "telescope" })
    assert.are.equal("telescope", picker.detect())
  end)

  it("falls back to vim.ui.select when no picker plugin is installed", function()
    config.setup({ picker = "auto" })
    assert.are.equal("select", picker.detect())
  end)

  it("uses vim.ui.select as a backend", function()
    config.setup({ picker = "select" })
    local restore = helpers.stub_select({ Prompt = "b" })
    local choice = helpers.await(function(done)
      picker.select({ "a", "b" }, { prompt = "Prompt" }, done)
    end)
    restore()
    assert.are.equal("b", choice)
  end)
end)

describe("browse and search", function()
  local seeded
  before_each(function()
    seeded = {
      secrets = {
        ["secret/app/db"] = { USER = "u" },
        ["secret/app/api/key"] = { K = "1" },
        ["secret/top"] = { T = "1" },
      },
    }
    helpers.setup_fake(seeded)
    config.options.picker = "select"
    browse.reset()
  end)
  after_each(function()
    vim.cmd("silent! %bwipeout!")
  end)

  local function wait_buffer(full)
    assert.is_true(vim.wait(10000, function()
      return buffer.find(full) ~= nil
    end, 10))
  end

  it("drills down mount > folder > secret", function()
    local seen = {}
    local original = vim.ui.select
    local answers = { "secret/", "app/", "db" }
    vim.ui.select = function(items, opts, cb)
      seen[#seen + 1] = { prompt = opts.prompt, items = items }
      local choice = table.remove(answers, 1)
      vim.schedule(function()
        cb(choice)
      end)
    end
    browse.browse("")
    wait_buffer("secret/app/db")
    vim.ui.select = original
    assert.are.same({ "secret/" }, seen[1].items)
    assert.are.same({ "../", "+ new secret here", "app/", "top" }, seen[2].items)
    assert.are.equal("OpenBao: secret/app", seen[3].prompt)
  end)

  it("goes up with ../", function()
    local prompts = {}
    local answers = { "../", nil }
    local original = vim.ui.select
    vim.ui.select = function(_, opts, cb)
      prompts[#prompts + 1] = opts.prompt
      local choice = table.remove(answers, 1)
      vim.schedule(function()
        cb(choice)
      end)
    end
    browse.browse("secret/app")
    vim.wait(2000, function()
      return #prompts == 2
    end)
    vim.ui.select = original
    assert.are.same({ "OpenBao: secret/app", "OpenBao: secret" }, prompts)
  end)

  it("creates a new secret from the browser", function()
    local original_select, original_input = vim.ui.select, vim.ui.input
    vim.ui.select = function(_, _, cb)
      vim.schedule(function()
        cb("+ new secret here")
      end)
    end
    vim.ui.input = function(_, cb)
      cb("fresh")
    end
    browse.browse("secret/app")
    wait_buffer("secret/app/fresh")
    vim.ui.select, vim.ui.input = original_select, original_input
    assert.is_true(buffer.state(vim.api.nvim_get_current_buf()).new)
  end)

  it("searches every secret and caches the index", function()
    local dir = helpers.setup_fake(seeded)
    config.options.picker = "select"
    local listed
    local restore = helpers.stub_select({ ["OpenBao search"] = "secret/top" })
    local original = vim.ui.select
    vim.ui.select = function(items, opts, cb)
      listed = items
      original(items, opts, cb)
    end
    browse.search("")
    wait_buffer("secret/top")
    restore()
    assert.are.same({ "secret/app/api/key", "secret/app/db", "secret/top" }, listed)
    local calls_before = #helpers.calls(dir)
    local _, paths = helpers.await(function(done)
      browse.all_secrets("", done)
    end)
    assert.are.equal(3, #paths)
    assert.are.equal(calls_before, #helpers.calls(dir))
    assert.are.equal(3, #browse.known_paths())
  end)
end)

describe("history", function()
  after_each(function()
    vim.cmd("silent! %bwipeout!")
  end)

  it("rolls back to a chosen version", function()
    local dir = helpers.setup_fake({ secrets = { ["secret/a"] = { K = "v1" } } })
    config.options.picker = "select"
    helpers.await(function(done)
      require("openbao.kv").put("secret/a", { K = "v2" }, { cas = 1 }, done)
    end)
    local restore = helpers.stub_select({
      ["History of"] = "v1  2026-01-01T00:00:00Z",
      ["secret/a v1"] = "Rollback to this version",
    })
    history.show("secret/a")
    assert.is_true(vim.wait(10000, function()
      return #helpers.store(dir).secrets["secret/a"] == 3
    end, 10))
    restore()
    assert.are.same({ K = "v1" }, helpers.latest(dir, "secret/a"))
  end)
end)
