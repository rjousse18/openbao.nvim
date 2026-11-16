# AGENTS.md

Instructions for AI coding assistants (and a quick map for humans). Read this before changing anything.

## What this is

`openbao.nvim`: a Neovim plugin (Lua, Neovim >= 0.10) that edits and syncs OpenBao / Vault KV v2 secrets
by driving the `bao` / `vault` CLI. User docs: [README.md](README.md). Design: [docs/architecture.md](docs/architecture.md),
decisions: [docs/decisions.md](docs/decisions.md).

## Commands

```sh
make test                 # all specs (clones plenary into ./.deps on first run)
SPEC=env make test        # one spec: tests/env_spec.lua
make test DEPS=~/.local/share/nvim/lazy   # reuse existing plenary
make integration          # optional, needs a real `bao` binary (starts `bao server -dev`)
stylua lua plugin tests   # format (CI checks it)
```

## Rules

1. **Every change comes with tests.** New behavior, fix, command, option: add or update a spec in `tests/`
   in the same change. A bug fix starts with a spec that fails. Run `make test` until 0 failures before concluding.
2. **Docs follow code.** Behavior, command or option change: update `README.md` (and `docs/` if concerned)
   and `CHANGELOG.md` (`## [Unreleased]`) in the same change.
3. **Only `lua/openbao/cli.lua` spawns processes** (except `git check-ignore` in `env.lua`).
   Every other module calls the CLI through `client.call` (adds re-login) via `kv.lua` / `mounts.lua` / `auth.lua`.
4. **Never put a secret value in a CLI argument, a notification, a log or an error message.**
   Values go through stdin (`kv.put`). Messages may name keys and paths, never values.
5. **Files holding secrets are created `0600`** and the user is steered to `.gitignore` (see `env.write_file`, `project.write_secure`).
6. **Keep pure logic pure**: `format.lua` and `env.plan_push` have no UI/CLI, so they stay unit-testable.
7. **Async everywhere**: CLI calls use callbacks, never block the UI (`:checkhealth` is the only place that waits).
   Callbacks always run on the main loop (`cli.run` schedules them).
8. No new dependency. Pickers are optional and detected at runtime (`picker.lua`); nothing else is required.
9. Prefer an existing plugin/Neovim API over custom code, and justify custom code in a comment (*why*).

## Layout

| Path | Role |
| --- | --- |
| `plugin/openbao.lua` | Registers `:Bao` (lazy: requires modules on use) |
| `lua/openbao/init.lua` | Public API (`setup`, `edit`, `browse`, `env_pull`...) |
| `config.lua` | Defaults, `setup(opts)` merge, option docs (LuaLS) |
| `cli.lua` | Spawns the binary (`vim.system`), env, JSON decode. **The only process spawner** |
| `client.lua` | `call()` = `cli.run` + auth-failure detection + login + retry |
| `auth.lua` | `token lookup`, `login` (shared between concurrent calls), status |
| `mounts.lua` | KV v2 mount discovery, `mount/path` splitting (longest match) |
| `kv.lua` | get / put (cas) / list / versions / rollback / delete / undelete / walk |
| `format.lua` | Pure: dotenv and JSON text <-> secret, diff |
| `buffer.lua` | `openbao://` buffers, `BufWriteCmd`, conceal, hardening |
| `picker.lua` | `select()` over snacks / telescope / fzf-lua / `vim.ui.select` |
| `browse.lua` | `:Bao browse` and `:Bao search` |
| `history.lua` | `:Bao versions` |
| `env.lua` | Project file, profiles, pull / status / push |
| `project.lua` | Local mirror directory (pull / status / push) |
| `commands.lua` | `:Bao` subcommands and completion |
| `health.lua` | `:checkhealth openbao` |
| `tests/` | plenary specs; `fixtures/fake-bao` is a fake CLI (see below) |

## Tests

- Specs: `tests/*_spec.lua` (plenary busted). `tests/helpers.lua` gives `setup_fake`, `await`, `stub_select`, `latest`, `calls`.
- **No real server in unit specs.** `tests/fixtures/fake-bao` is a Lua script run by `nvim -l`; it keeps a KV v2 store in
  `$FAKE_BAO_DIR/store.json` and logs calls to `calls.log`. Extend it when a new CLI verb is used (keep it minimal).
- Stub prompts with `helpers.stub_select({ ["prompt substring"] = "Choice" })`; always call the returned restore function.
- `vim.notify(..., ERROR)` raises when triggered synchronously inside `vim.cmd(...)` in headless mode: wrap with `pcall`.
- `tests/integration/` runs against a real binary and is skipped by default.

## Style

- Lua, 2 spaces, `stylua` (`.stylua.toml`). LuaLS annotations (`---@param`, `---@return`, `---@class`) on public functions.
- Comments explain *why*, in English, only where the code is not obvious. Small focused modules.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`).

## Skills

Step-by-step recipes for common changes are in `.github/skills/`:
`add-subcommand`, `add-cli-call`, `write-spec`.
