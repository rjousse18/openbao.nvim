local helpers = require("tests.helpers")
local project = require("openbao.project")

local function mirror(path)
  return vim.fn.getcwd() .. "/.openbao/" .. path
end

describe("project mirror", function()
  local dir
  before_each(function()
    dir = helpers.setup_fake({
      secrets = {
        ["secret/app/db"] = { USER = "u", PASS = "p" },
        ["secret/app/api/key"] = { K = "1" },
        ["secret/other"] = { X = "1" },
      },
    })
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.cmd("cd " .. root)
  end)
  after_each(function()
    vim.cmd("cd /")
  end)

  local function pull(prefixes, opts)
    return helpers.await(function(done)
      project.pull(prefixes, opts, done)
    end)
  end

  it("pulls every secret under a prefix, one 0600 file each, self-ignored", function()
    local err, written = pull({ "secret/app" })
    assert.is_nil(err)
    assert.are.equal(2, written)
    assert.are.same({ "PASS=p", "USER=u" }, vim.fn.readfile(mirror("secret/app/db.env")))
    assert.are.equal(1, vim.fn.filereadable(mirror("secret/app/api/key.env")))
    assert.are.equal(0, vim.fn.filereadable(mirror("secret/other.env")))
    assert.are.equal("600", string.format("%o", vim.uv.fs_stat(mirror("secret/app/db.env")).mode % 512))
    assert.are.same({ "*" }, vim.fn.readfile(mirror(".gitignore")))
  end)

  it("re-pulls the remembered prefixes without arguments", function()
    pull({ "secret/app" })
    os.remove(mirror("secret/app/db.env"))
    local _, written = pull({})
    assert.are.equal(2, written)
    assert.are.equal(1, vim.fn.filereadable(mirror("secret/app/db.env")))
  end)

  it("requires a prefix the first time", function()
    local err = helpers.await(function(done)
      pcall(project.pull, {}, nil, done)
    end)
    assert.matches("usage", err)
  end)

  it("writes JSON files for non-flat secrets", function()
    helpers.await(function(done)
      require("openbao.kv").put("secret/app/cfg", { n = 1 }, { cas = 0 }, done)
    end)
    pull({ "secret/app" })
    assert.are.equal(1, vim.fn.filereadable(mirror("secret/app/cfg.json")))
  end)

  it("reports status: clean, modified, new, outdated, conflict", function()
    pull({ "secret/app" })
    local function statuses()
      local rows = helpers.await(function(done)
        project.scan(done)
      end)
      local out = {}
      for _, r in ipairs(rows) do
        out[r.file.full] = r.status
      end
      return out
    end
    assert.are.same({ ["secret/app/api/key"] = "clean", ["secret/app/db"] = "clean" }, statuses())

    vim.fn.writefile({ "PASS=changed", "USER=u" }, mirror("secret/app/db.env"))
    vim.fn.writefile({ "A=1" }, mirror("secret/app/fresh.env"))
    local s = statuses()
    assert.are.equal("modified", s["secret/app/db"])
    assert.are.equal("new", s["secret/app/fresh"])

    helpers.await(function(done)
      require("openbao.kv").put("secret/app/api/key", { K = "remote" }, { cas = 1 }, done)
    end)
    assert.are.equal("outdated", statuses()["secret/app/api/key"])

    helpers.await(function(done)
      require("openbao.kv").put("secret/app/db", { USER = "remote" }, { cas = 1 }, done)
    end)
    assert.are.equal("conflict", statuses()["secret/app/db"])
  end)

  it("pushes modified and new files but never a conflict without --force", function()
    pull({ "secret/app" })
    vim.fn.writefile({ "PASS=changed", "USER=u" }, mirror("secret/app/db.env"))
    vim.fn.writefile({ "A=1" }, mirror("secret/app/fresh.env"))
    local restore = helpers.stub_select({ ["Push to OpenBao"] = "Push" })
    local err = helpers.await(function(done)
      project.push(nil, done)
    end)
    assert.is_nil(err)
    assert.are.same({ USER = "u", PASS = "changed" }, helpers.latest(dir, "secret/app/db"))
    assert.are.same({ A = "1" }, helpers.latest(dir, "secret/app/fresh"))

    -- second round: remote moved and local edited -> conflict is blocked
    vim.fn.writefile({ "PASS=again", "USER=u" }, mirror("secret/app/db.env"))
    helpers.await(function(done)
      require("openbao.kv").put("secret/app/db", { USER = "theirs" }, nil, done)
    end)
    helpers.await(function(done)
      project.push(nil, done)
    end)
    assert.are.same({ USER = "theirs" }, helpers.latest(dir, "secret/app/db"))
    helpers.await(function(done)
      project.push({ force = true }, done)
    end)
    restore()
    assert.are.same({ USER = "u", PASS = "again" }, helpers.latest(dir, "secret/app/db"))
  end)

  it("does not overwrite local edits on pull unless --force", function()
    pull({ "secret/app" })
    vim.fn.writefile({ "PASS=mine", "USER=u" }, mirror("secret/app/db.env"))
    helpers.await(function(done)
      require("openbao.kv").put("secret/app/db", { USER = "remote" }, { cas = 1 }, done)
    end)
    pull({})
    assert.are.same({ "PASS=mine", "USER=u" }, vim.fn.readfile(mirror("secret/app/db.env")))
    pull({}, { force = true })
    assert.are.same({ "USER=remote" }, vim.fn.readfile(mirror("secret/app/db.env")))
  end)
end)
