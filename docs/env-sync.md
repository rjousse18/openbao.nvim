# Environment sync: patterns and advice

`:Bao env` keeps the environment variables of a project in line with OpenBao.
This page explains which form fits which situation. Reference: [README](../README.md#sync-environment-variables-of-a-project).

## Which target?

| Need | Use | Why |
| --- | --- | --- |
| Run tests / LSP / terminals from Neovim | `vim.env` (default) | Nothing on disk; children of Neovim inherit it |
| Another tool must read the values (docker compose, shell, IDE) | `"file": ".env.local"` | A file is the common denominator |
| Both | both (default + `file`) | `pull` writes both |

Prefer `vim.env` only when you can: no file means no leak. Run `:Bao env pull` once per Neovim session
(or call `require("openbao").env_pull()` from an autocmd on `DirChanged` if you want it automatic).

## One profile per environment

```json
{
  "default": "dev",
  "profiles": {
    "dev":     { "sources": ["secret/myapp/common", "secret/myapp/dev"],     "file": ".env.local" },
    "staging": { "sources": ["secret/myapp/common", "secret/myapp/staging"], "file": ".env.staging" }
  }
}
```

`:Bao env pull staging`. Shared values live in `common`, overrides in the environment secret (later wins).

## Prefixes and filters

- `prefix` avoids collisions when two secrets use the same key (`DB_URL` in `app` and `billing`).
- `only` limits what you pull (`"only": ["DB_URL", "API_KEY"]`): useful for a secret that holds more than the app needs.
- Values that are not strings (numbers, nested objects) are skipped on pull with a warning, and preserved on push.

## Push, safely

1. Edit `.env.local`.
2. `:Bao env status` shows variable names that differ (never values).
3. `:Bao env push` shows `path: +NEW ~CHANGED -REMOVED` and asks. Removals only appear with `--prune`.
4. The write uses check-and-set: if someone else changed the secret since your `pull`, it fails instead of overwriting.
   Run `:Bao env pull` again and redo your edit.

## With direnv (outside Neovim)

The plugin does not replace your shell tooling. If you also want the variables in a terminal that was not
started from Neovim, either source the generated file (`dotenv .env.local` in `.envrc`) or use the CLI
directly (`bao kv get -format=json ...`). Keep one source of truth: OpenBao.

## Team workflow

- Commit `.openbao.json` (paths only). Never commit `.env.local`: the plugin offers to add it to `.gitignore`.
- New teammate: `:Bao login`, `:Bao env pull`. Nothing else to share.
- Rotate a secret in OpenBao, everyone runs `:Bao env pull`.

## Limits

- The generated file is overwritten on every pull.
- No automatic polling or watching of remote changes.
- Only KV v2 sources.
