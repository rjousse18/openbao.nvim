---
name: write-spec
description: Write or extend a plenary spec for openbao.nvim using the fake CLI helpers. Use for every change (tests are mandatory), including bug fixes (write the failing spec first).
---

# Write a spec

Specs live in `tests/<area>_spec.lua` (plenary busted). Reuse the existing file of the area
(`format`, `cli_kv`, `auth`, `buffer`, `browse`, `env`, `project`, `commands`); create a new one only for a new module.

## Skeleton

```lua
local helpers = require("tests.helpers")
local kv = require("openbao.kv")

describe("my feature", function()
  local dir
  before_each(function()
    dir = helpers.setup_fake({ secrets = { ["secret/app/db"] = { USER = "u" } } }) -- fresh store + config
  end)
  after_each(function()
    vim.cmd("silent! %bwipeout!")
  end)

  it("does the thing", function()
    local err, secret = helpers.await(function(done)
      kv.get("secret/app/db", nil, done)
    end)
    assert.is_nil(err)
    assert.are.same({ USER = "u" }, secret.data)
  end)
end)
```

## Helpers (`tests/helpers.lua`)

- `setup_fake(seed)`: new store + points `config` at `tests/fixtures/fake-bao`. Seed: `secrets`, `mounts`, `token_valid`, `login_fails`.
- `await(function(done) ... end)`: waits for an async callback, returns its arguments (10 s timeout).
- `stub_select({ ["prompt substring"] = "Choice" })`: answers `vim.ui.select`; returns `restore, prompts`. Always call `restore()`.
- `latest(dir, "mount/path")`: current remote data. `store(dir)`: whole fake store. `calls(dir)`: logged CLI arguments.

## Tips

- Prefer asserting on the remote state (`helpers.latest`) over internal variables.
- Async UI (`:write`, `:Bao ...`): `vim.wait(10000, function() return <condition> end, 10)`.
- `vim.notify(..., ERROR)` raises inside `vim.cmd(...)` in headless mode: use `pcall(vim.cmd, ...)` for failure paths,
  or replace `vim.notify` to capture messages (restore it afterwards).
- Change directories for project tests with `vim.cmd("cd " .. tmp)` and go back in `after_each`.
- Test a failure path and an edge case, not only the happy path. Do not test constants or defaults.

## Run

```sh
SPEC=<area> make test     # one file
make test                 # everything, must end with 0 failures
```
