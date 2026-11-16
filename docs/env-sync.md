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

## Spring Boot: environment variables override `application.properties`

Spring Boot binds environment variables to properties by itself ("relaxed binding"): the variable
`RECEIVIT_KAFKAFRAMEWORK_SECURITY_SASL_PASSWORD` is matched to `receivit.kafka-framework.security.sasl.password`
and **wins over the value in `application.properties`**. Nothing to change in the application.
The rule: upper case, dots become `_`, dashes are dropped. So the variable must keep the full name, a shortened one
would not be matched to any property.

### Property-style keys (`to_env`)

When the secret stores property names (`receivit.kafka-framework.security.sasl.password`), a shell cannot export them.
`{ "path": "secret/app/uat1", "to_env": true }` renames them on pull with the rule above, so `.env.uat1` can be
sourced and Spring still binds the property. Names already in `MY_VAR` style are kept.
`push` maps a changed value back to its original key; new variables cannot be pushed to a `to_env` source.

### Launch the application with the variables

```sh
:Bao env pull uat1                  # in Neovim, once per session (the token lasts a few hours)
set -a; source .env.uat1; set +a    # in the shell: export every variable of the file
./mvnw spring-boot:run
```

- From a terminal opened in Neovim (`:terminal`), the variables are already there after `:Bao env pull`:
  `vim.env` is inherited, no `source` needed.
- IntelliJ: an "EnvFile" plugin pointing at `.env.uat1`, or paste the variables in "Environment variables".
- A value containing `$` or a backtick is expanded by the shell when sourced: check such values.
- Variables you do not pull keep the default of `application.properties`.
- Pointing the app at UAT services from your machine is a real connection (Kafka consumer group, database).

### Several `.env` files: pick the one to inject

```
:Bao env load            " picker over .env, .env.uat1, .env.dev... of the project
:Bao env load .env.uat1  " directly
:Bao env unload          " remove what was loaded
```

- The file is read and put in `vim.env` by Neovim itself: no shell, so `$`, backticks and accents are kept as is.
- Hybrid: the file is plain text. Delete or comment (`#`) the lines you do not want before loading;
  those properties keep the default of `application.properties`. `:Bao env pull` does not touch the choice,
  `:Bao env load` simply reads the file as it is now.
- Commented lines survive `:Bao env pull`: a line written `# NAME=value` stays commented and gets the fresh value.
  It is not put in `vim.env`, `:Bao env status` does not report it, and `push --prune` never deletes it from OpenBao.
  To enable it again, remove the `# `.
- Loading another file first removes the variables of the previous one, so two environments never mix.
- Then run the application from a `:terminal` (or your run config): children of Neovim inherit `vim.env`.
- Files searched: `.env` and `.env.*` next to the project file (`.openbao.json`), else in the cwd.
- Nothing is injected outside Neovim; use `source` (see above) for a shell.

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
