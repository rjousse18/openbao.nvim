# Architecture

## Layers

```
:Bao <sub>                      plugin/openbao.lua, commands.lua
   |
   +-- buffer.lua   browse.lua   history.lua   env.lua   project.lua      features (UI + logic)
   |        \           |            |            |           /
   |         +----------+------ kv.lua / mounts.lua / auth.lua ------+      OpenBao operations
   |                                  |
   |                              client.lua       call() = run + detect auth failure + login + retry once
   |                                  |
   |                               cli.lua          the ONLY place that spawns bao / vault (vim.system)
   |
   +-- format.lua (pure: text <-> secret, diff)     picker.lua (snacks / telescope / fzf-lua / ui.select)
```

Rule of thumb: a feature module never builds CLI arguments itself; it asks `kv` / `mounts` / `auth`.

## Calling the CLI

`kv.lua` resolves `mount/rel/path` with `mounts.resolve` (longest matching KV v2 mount), then runs
`bao kv <verb> -format=json -mount=<mount> [flags] <rel> [-]`. A body goes through stdin (`-`), never arguments.
Results are `cb(err, value)` where `err = { kind = "not_found"|"cas"|"auth"|"error", msg }`.

## Authentication flow

```
call() -> failure looks like auth (permission denied / missing client token / 403)?
   no  -> return the error
   yes -> `token lookup`
            valid   -> it is a policy denial: return the error, no login prompt
            invalid -> prompt "Log in" -> `login -method=...` (one shared login for concurrent calls) -> retry the call once
```

## Saving a secret buffer

```
:w -> BufWriteCmd -> parse text (format.parse) -> errors? abort
   -> diff vs last known remote data -> removed keys? confirm
   -> kv.put(..., { cas = version opened }) -> ok: modified=false, version updated
                                            -> cas error: "changed remotely" (:Bao reload, or :w! to skip cas)
```

`:w!` skips check-and-set. A new secret uses `cas = 0` ("must not exist yet").

## Env sync

`generate.lua` (`:Bao generate-conf`) writes profiles into `.openbao.json`.
`.openbao.json|lua` -> `env.profile` -> `env.fetch` (all sources in parallel, merged in order, `owner[NAME]` = last source
providing it) -> `pull` writes `vim.env` / file. `push` runs `env.plan_push` (pure): changed values go to their owner,
new variables to `push_to`, removals only with `prune`; then one `kv.put` per touched source with its own `cas`.

## Local mirror

`.openbao/<mount>/<path>.env|json` + `.openbao/.state.json` (`version` and content `hash` at pull time).
Status per file: `clean`, `modified` (local edit, remote unchanged), `outdated` (remote moved, no local edit),
`conflict` (both), `new` (not on remote). Push skips `conflict` unless `--force`.

## Testing approach

Unit specs run the real `cli.lua` against `tests/fixtures/fake-bao` (a Lua script run by `nvim -l`) that implements
the few KV v2 verbs used. This tests argument building, JSON decoding and the async plumbing without a server.
`tests/integration/` checks the same operations against a real `bao server -dev`.
