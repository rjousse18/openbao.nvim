local helpers = require("tests.helpers")
local config = require("openbao.config")
local generate = require("openbao.generate")

describe("generate.add_profile", function()
  it("adds a profile with a .env.<name> file and keeps the existing default", function()
    local cfg = { default = "dev", profiles = { dev = { sources = { "secret/a" } } } }
    local out = assert(generate.add_profile(cfg, "uat1", { "secret/a", "secret/b" }))
    assert.are.same({ "secret/a", "secret/b" }, out.profiles.uat1.sources)
    assert.are.equal(".env.uat1", out.profiles.uat1.file)
    assert.are.equal("dev", out.default)
    assert.is_nil(cfg.profiles.uat1)
  end)

  it("refuses to replace a profile without force, and rejects bad input", function()
    local cfg = { profiles = { dev = { sources = { "secret/a" } } } }
    assert.matches("already exists", select(2, generate.add_profile(cfg, "dev", { "secret/b" })))
    assert.are.equal("secret/b", generate.add_profile(cfg, "dev", { "secret/b" }, true).profiles.dev.sources[1])
    assert.matches("invalid profile name", select(2, generate.add_profile({}, "a/b", { "secret/a" })))
    assert.matches("no source", select(2, generate.add_profile({}, "dev", {})))
  end)

  it("encodes readable JSON that decodes back", function()
    local cfg = assert(generate.add_profile({}, "uat1", { "secret/a" }))
    local text = generate.encode(cfg)
    assert.matches('"default": "uat1"', text, 1, true)
    assert.are.same(cfg, vim.json.decode(text))
  end)
end)

describe(":Bao generate-conf", function()
  local root, messages, original

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.git", "p")
    vim.cmd("cd " .. root)
    messages = {}
    original = vim.notify
    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end
  end)

  after_each(function()
    vim.notify = original
    vim.cmd("cd /")
  end)

  local function read()
    return vim.json.decode(table.concat(vim.fn.readfile(root .. "/.openbao.json"), "\n"))
  end

  it("creates the project file and git-ignores the env file", function()
    generate.run("uat1", { "secret/app/common", "secret/app/uat1" })
    assert.are.same({
      default = "uat1",
      profiles = { uat1 = { sources = { "secret/app/common", "secret/app/uat1" }, file = ".env.uat1" } },
    }, read())
    assert.is_true(vim.tbl_contains(vim.fn.readfile(root .. "/.gitignore"), ".env.uat1"))
    assert.matches("Next: :Bao env pull uat1", messages[#messages])
  end)

  it("adds a second profile next to the first, and needs --force to replace one", function()
    generate.run("uat1", { "secret/app/uat1" })
    generate.run("uat2", { "secret/app/uat2" })
    assert.are.same({ "uat1", "uat2" }, require("openbao.util").sorted_keys(read().profiles))
    assert.are.equal("uat1", read().default)
    assert.are.equal("secret/app/uat2", read().profiles.uat2.sources[1])
    generate.run("uat1", { "secret/other" })
    assert.matches("already exists", messages[#messages])
    assert.are.equal("secret/app/uat1", read().profiles.uat1.sources[1])
    generate.run("uat1", { "secret/other" }, true)
    assert.are.equal("secret/other", read().profiles.uat1.sources[1])
  end)

  it("refuses to edit a .openbao.lua project file", function()
    vim.fn.writefile({ "return {}" }, root .. "/.openbao.lua")
    generate.run("uat1", { "secret/app" })
    assert.matches("add the profile by hand", messages[#messages])
    assert.are.equal(0, vim.fn.filereadable(root .. "/.openbao.json"))
  end)

  it("asks for the sources through the picker when none is given", function()
    helpers.setup_fake({ secrets = { ["secret/app/common"] = { A = "1" }, ["secret/app/uat1"] = { B = "2" } } })
    config.options.picker = "select"
    local queue = { "secret/app/common", "secret/app/uat1", "-- done --" }
    local select = vim.ui.select
    vim.ui.select = function(items, _, cb)
      local choice = table.remove(queue, 1)
      assert.is_true(vim.tbl_contains(items, choice))
      vim.schedule(function()
        cb(choice)
      end)
    end
    generate.run("uat1", {})
    local ok = vim.wait(10000, function()
      return vim.fn.filereadable(root .. "/.openbao.json") == 1
    end, 20)
    vim.ui.select = select
    assert.is_true(ok)
    assert.are.same({ "secret/app/common", "secret/app/uat1" }, read().profiles.uat1.sources)
  end)

  it("is dispatched by :Bao and completes paths after the profile name", function()
    local commands = require("openbao.commands")
    assert.are.same({ "generate-conf" }, commands.complete("g", "Bao g"))
    assert.are.same({}, commands.complete("", "Bao generate-conf "))
    assert.is_true(vim.tbl_contains(commands.complete("", "Bao generate-conf uat1 "), "--force"))
    vim.cmd("Bao generate-conf uat3 secret/app/uat3")
    assert.are.equal(".env.uat3", read().profiles.uat3.file)
  end)
end)
