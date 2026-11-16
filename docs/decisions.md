# Design decisions

Short records: what was decided, why, and what was rejected.

## Drive the CLI, not the HTTP API
- **Why**: `bao` / `vault` already handle OIDC/LDAP login, token helper, TLS, namespaces. Re-implementing OIDC over HTTP is the costly part.
- **Also**: one code path works for OpenBao and Vault (same CLI syntax), with `binary` to force one.
- **Cost**: needs the binary installed. All spawning is in `cli.lua`, so an HTTP backend could replace it later.
- **Rejected**: direct `curl` calls; a `bao`-only plugin (compat costs almost nothing).

## KV v2 only
- v2 gives versions, check-and-set and soft delete, which the plugin relies on. KV v1 has no equivalent.

## One buffer per secret, `:w` saves (plus an optional mirror)
- Same model as oil.nvim: familiar, no state to sync. A mirror directory exists for bulk work (`:Bao project`) but is opt-in.

## `put` with a confirmation on removals, plus check-and-set
- `put` replaces the whole secret, matching what the buffer shows. Removing a key is destructive, so it is confirmed.
- `cas` prevents silently overwriting someone else's change. `:w!` is the explicit override.

## dotenv in buffers, JSON when lossless is impossible
- dotenv is what people read and edit. Non-string values or unusual key names would be corrupted by it, so those secrets open as JSON.

## Login only when the token is the problem
- "permission denied" is ambiguous (expired token vs policy). The plugin runs `token lookup` before offering a login,
  so a policy denial never triggers a pointless browser login.

## Env sync driven by a project file of paths
- The file (`.openbao.json|lua`) holds paths, no values, so it is committable and the same for the whole team.
- Profiles and ordered sources cover "common + per environment" without templating.
- `.lua` is allowed for comments/logic but goes through `vim.secure.read` and runs in an empty environment.

## Secret hygiene
- Values only through stdin, concealed in buffers, `0600` generated files, `.gitignore` offer, key names only in messages.
- Known limit: yanked values live in registers/shada, as for any text in Neovim.

## Single `:Bao` command
- One global command with subcommands and completion instead of a dozen `:BaoXxx` commands.
