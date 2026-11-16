local helpers = require("tests.helpers")
local commands = require("openbao.commands")

describe(":Bao command", function()
  it("is registered by plugin/openbao.lua", function()
    assert.are.equal(2, vim.fn.exists(":Bao"))
  end)

  it("every subcommand has a description and a run function", function()
    for name, sub in pairs(commands.subcommands) do
      assert.is_string(sub.desc, name)
      assert.is_function(sub.run, name)
    end
  end)

  it("complains about an unknown subcommand and lists the valid ones", function()
    local seen
    local original = vim.notify
    vim.notify = function(msg)
      seen = msg
    end
    commands.run({ fargs = { "nope" } })
    vim.notify = original
    assert.matches("usage: :Bao <browse|delete|diff|edit", seen)
  end)

  it("completes subcommands, then arguments", function()
    assert.are.same({ "edit", "env" }, commands.complete("e", "Bao e"))
    assert.are.same({ "pull", "push", "status", "load", "unload", "gitignore" }, commands.complete("", "Bao env "))
    assert.are.same({ "pull", "push" }, commands.complete("pu", "Bao project pu"))
    assert.are.same({ "--prune" }, commands.complete("--p", "Bao env pull --p"))
  end)

  it("completes mounts from the config", function()
    require("openbao.config").setup({ mounts = { "secret", "team/kv" } })
    assert.are.same({ "secret" }, commands.complete("sec", "Bao edit sec"))
  end)

  it(":Bao edit <path> opens the secret", function()
    helpers.setup_fake({ secrets = { ["secret/a"] = { K = "v" } } })
    vim.cmd("Bao edit secret/a")
    assert.is_true(vim.wait(10000, function()
      return require("openbao.buffer").find("secret/a") ~= nil
    end, 10))
    vim.cmd("silent! %bwipeout!")
  end)

  it(":Bao new requires a path", function()
    local seen
    local original = vim.notify
    vim.notify = function(msg)
      seen = msg
    end
    vim.cmd("Bao new")
    vim.notify = original
    assert.matches("usage: :Bao new", seen)
  end)

  it(":Bao delete soft-deletes after confirmation and closes the buffer", function()
    local dir = helpers.setup_fake({ secrets = { ["secret/a"] = { K = "v" } } })
    vim.cmd("Bao edit secret/a")
    local buffer = require("openbao.buffer")
    vim.wait(10000, function()
      return buffer.find("secret/a") ~= nil
    end, 10)
    local restore = helpers.stub_select({ ["Delete latest version"] = "Delete" })
    vim.cmd("Bao delete")
    assert.is_true(vim.wait(10000, function()
      return helpers.store(dir).secrets["secret/a"][1].deleted == true
    end, 10))
    assert.is_true(vim.wait(10000, function()
      return buffer.find("secret/a") == nil
    end, 10))
    restore()
  end)

  it(":Bao status prints the token and :Bao login logs in", function()
    local dir = helpers.setup_fake({ token_valid = false })
    local messages = {}
    local original = vim.notify
    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end
    vim.cmd("Bao status")
    vim.wait(10000, function()
      return #messages > 0
    end, 10)
    assert.matches("not authenticated", messages[1])
    messages = {}
    vim.cmd("Bao login")
    assert.is_true(vim.wait(10000, function()
      return helpers.store(dir).logins == 1
    end, 10))
    vim.wait(1000, function()
      return vim.tbl_contains(messages, "openbao: logged in")
    end, 10)
    vim.cmd("Bao status")
    vim.wait(10000, function()
      return messages[#messages]:find("oidc%-tester") ~= nil
    end, 10)
    vim.notify = original
    assert.matches("user: oidc%-tester", messages[#messages])
  end)

  it(":Bao env without a project file explains what is missing", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.cmd("cd " .. root)
    local seen
    local original = vim.notify
    vim.notify = function(msg)
      seen = msg
    end
    vim.cmd("Bao env pull")
    vim.notify = original
    vim.cmd("cd /")
    assert.matches("no .openbao.lua", seen)
  end)
end)

describe("health", function()
  it("runs against the fake binary without errors", function()
    helpers.setup_fake()
    local report = {}
    local original = {}
    for _, level in ipairs({ "start", "ok", "warn", "error" }) do
      original[level] = vim.health[level]
      vim.health[level] = function(msg)
        report[#report + 1] = level .. ": " .. msg
      end
    end
    require("openbao.health").check()
    for level, f in pairs(original) do
      vim.health[level] = f
    end
    local text = table.concat(report, "\n")
    assert.matches("ok: .*OpenBao v0.0.0%-fake", text)
    assert.matches("ok: authenticated", text)
    assert.matches("ok: KV v2 mounts: secret", text)
    assert.is_nil(text:find("error:", 1, true))
  end)
end)
