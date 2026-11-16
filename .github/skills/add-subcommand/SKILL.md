---
name: add-subcommand
description: Add or change a `:Bao` subcommand in openbao.nvim (name, args, flags, completion, docs, tests). Use when a new user-facing command or flag is requested.
---

# Add a `:Bao` subcommand

1. **Logic first, outside `commands.lua`.** Put behavior in the right feature module (`buffer`, `browse`, `history`,
   `env`, `project`) or a new `lua/openbao/<feature>.lua`. `commands.lua` only parses arguments and calls it.
   Talk to OpenBao through `kv` / `mounts` / `auth` only (see the `add-cli-call` skill).
2. **Register** in `M.subcommands` of `lua/openbao/commands.lua`:
   ```lua
   name = {
     desc = "one line shown in docs",
     run = function(args, flags) ... end,   -- flags: `--force` -> flags.force = true
     complete = function(args) return { ... } end, -- args = words already typed after the subcommand
   },
   ```
   Report errors with `util.error`, info with `util.notify` (key names and paths only, never values).
3. **Public API** (optional): expose it in `lua/openbao/init.lua` if scripting it makes sense.
4. **Tests (mandatory)**: see the `write-spec` skill. At minimum: the happy path, one failure path, and the
   completion if arguments are completed. Add the command to `tests/commands_spec.lua` when it only dispatches.
5. **Docs (mandatory)**: command table in `README.md`, `CHANGELOG.md` under `## [Unreleased]`, and
   `docs/architecture.md` if a new module or flow appears.
6. `make test` and `stylua lua plugin tests`.
