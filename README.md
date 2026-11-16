# openbao.nvim

Browse, edit and sync [OpenBao](https://openbao.org) (and HashiCorp Vault) secrets without leaving Neovim.
It drives the `bao` / `vault` CLI, so login, TLS and namespaces behave exactly like in your terminal.

> Not affiliated with the OpenBao project or the Linux Foundation.

- **Edit** a secret like a file: `:Bao edit secret/app/db`, change it, `:w` sends it to OpenBao.
- **Browse and search** mounts, folders and every secret path with your picker (snacks, telescope, fzf-lua).
- **Log in from Neovim**: `:Bao login`, and an automatic prompt when a call fails because the token expired.
- **Sync environment variables** of a project from OpenBao into `vim.env` and/or a `.env` file, and push changes back.
- **History**: view, roll back or undelete KV v2 versions.
- **Safe by default**: values hidden, no swap/undo files, check-and-set so you never overwrite a remote change silently.

## Requirements

- Neovim >= 0.10
- `bao` or `vault` in `$PATH`, with `BAO_ADDR` (or `VAULT_ADDR`) set, e.g. `export BAO_ADDR=https://bao.example.com`
- A KV **v2** mount (KV v1 is not supported)

### Installing the CLI

The plugin does **not** install or manage the binary: it only runs the one it finds. Install one of them yourself.

| System | OpenBao (`bao`) |
|---|---|
| macOS | `brew install openbao` |
| Arch | `sudo pacman -Sy openbao` |
| Fedora / RHEL | `sudo dnf install -y epel-release openbao` (EPEL on RHEL) |
| Debian / Ubuntu | `.deb` from the [downloads page](https://openbao.org/downloads/) |
| Any | unzip the release archive, put `bao` in your `$PATH` |

Vault users: the HashiCorp `vault` binary works too (auto-detected when `bao` is absent, or set `binary = "vault"`).
Other options: [openbao.org/docs/install](https://openbao.org/docs/install/).

Then set the address (shell profile) and check:

```sh
export BAO_ADDR=https://bao.example.com
bao version
```

In Neovim: `:checkhealth openbao`, then `:Bao login`.

## Install

lazy.nvim:

```lua
{
  "rjousse18/openbao.nvim",
  cmd = "Bao",
  opts = {}, -- see Configuration
}
```

Run `:checkhealth openbao` to verify the binary, address, login and mounts.

## Quick start

```vim
:Bao login                      " opens your browser (OIDC)
:Bao browse                     " mounts > folders > secrets
:Bao search                     " fuzzy search over every secret path
:Bao edit secret/app/db         " edit, then :w
:Bao new secret/app/other       " create a secret
```

## Commands

| Command | What it does |
| --- | --- |
| `:Bao login` | `bao login -method=<login.method>` (OIDC by default) |
| `:Bao status` | Show who you are logged in as (user, policies, ttl) |
| `:Bao browse [prefix]` | Navigate level by level; `../` goes up, `+ new secret here` creates one |
| `:Bao search [prefix]` | Fuzzy list of every secret path (cached `search.cache_ttl` seconds) |
| `:Bao edit [path]` | Open a secret in a buffer; without a path, same as `browse` |
| `:Bao new <path>` | Open an empty buffer; `:w` creates the secret (fails if it appeared meanwhile) |
| `:Bao reload` | Re-read the current secret (asks before dropping unsaved edits) |
| `:Bao diff` | Side-by-side diff of the buffer vs. the server's current version (shows values) |
| `:Bao reveal` | Show / hide values (also `<LocalLeader>r`) |
| `:Bao versions [path]` | History: view, roll back, undelete |
| `:Bao delete [path]` | Soft-delete the latest version (recoverable from `:Bao versions`) |
| `:Bao env pull\|push\|status\|gitignore [profile] [--prune]` | Sync a project's environment, see below |
| `:Bao project pull\|status\|push [prefixes] [--force]` | Local mirror directory of secrets, see below |

Paths are always `mount/path/to/secret`. The mount is detected with `secrets list`
(or set `mounts` / `default_mount` when your token cannot read `sys/mounts`).

## The secret buffer

`:Bao edit secret/app/db` opens `openbao://secret/app/db`:

```dotenv
PASS="p w"
USER=u
```

- `:w` writes the whole secret (KV `put`), with check-and-set on the version you opened.
  - Keys removed from the buffer are listed in a confirmation prompt first.
  - Each successful write creates a **new KV v2 version** (see `:Bao versions`). Preview with `:Bao diff` first.
  - Remote changed meanwhile: the write is refused. `:Bao reload` to refresh or `:w!` to overwrite.
  - `:wq` only quits once the (asynchronous) save has finished: use `:w` then `:q` if it stays open.
- Format: `KEY=value` lines, quoted when needed (`"a b"`, `\n` escapes). Comments and blank lines are
  allowed but not stored. Secrets with non-string values or odd key names open as JSON instead (lossless).
- Values are concealed. They are plain text in the buffer, so `yy` copies them to registers
  (and possibly shada). Use `:Bao reveal` only when you need to read them.

## Sync environment variables of a project

Put a **`.openbao.json`** (or `.openbao.lua`) at the project root. It lists paths, never values,
so it is safe to commit:

```json
{
  "default": "dev",
  "profiles": {
    "dev": {
      "sources": ["secret/myapp/common", { "path": "secret/myapp/dev", "prefix": "APP_" }],
      "file": ".env.local"
    }
  }
}
```

```vim
:Bao env pull        " OpenBao -> vim.env (+ .env.local, mode 0600)
:Bao env status      " diff of variable NAMES, remote vs local
:Bao env push        " .env.local -> OpenBao, after a confirmation listing the changes
```

- Sources are merged in order, **later sources win**. `prefix` is prepended to every key (`TOKEN` becomes `APP_TOKEN`).
- `vim.env` is set by default (terminals and jobs started from Neovim inherit it). Disable with `"vim_env": false`.
- `file` is **fully generated**: keep hand-written local variables in another file.
- `push` needs `file`. Changed values go back to the source that owns them, new variables to `push_to`
  (default: the last source), other keys of the secret are preserved. Removals need `--prune`.
- `.openbao.lua` runs code, so Neovim asks you to trust it first (`:h vim.secure.read`) and it is sandboxed
  (no globals). Prefer JSON unless you need comments.
- When the generated file is not git-ignored, you are offered to add it to `.gitignore`.

More patterns (direnv, per-environment profiles, team workflow): [docs/env-sync.md](docs/env-sync.md).

## Local mirror of a folder (optional)

When you want a whole folder as files (grep it, diff it, edit many secrets):

```vim
:Bao project pull secret/myapp     " writes .openbao/secret/myapp/**/*.env
:Bao project status                " clean / modified / outdated / conflict / new
:Bao project push                  " pushes modified and new files (never a conflict, unless --force)
```

The directory is git-ignored by its own `.gitignore` and files are `0600`. Deleting a local file does not
delete the remote secret. `pull` never overwrites a file you edited unless you pass `--force`.

## Configuration

Defaults, all optional (`require("openbao").setup({...})`):

```lua
{
  binary = nil,            -- default: "bao", then "vault"
  address = nil,           -- BAO_ADDR / VAULT_ADDR for the CLI (else your shell's)
  env = {},                -- extra CLI environment, e.g. { BAO_NAMESPACE = "team" }
  timeout = 30000,         -- ms per CLI call
  mounts = nil,            -- KV v2 mounts; default: detected with `secrets list`
  default_mount = nil,     -- fallback when the token cannot list mounts
  login = { method = "oidc", args = {}, timeout = 300000, auto = true },
  cas = true,              -- check-and-set on every write
  confirm_deletions = true,
  conceal = true,
  reveal_key = "<LocalLeader>r",
  search = { concurrency = 8, max_depth = 10, cache_ttl = 60 },
  picker = "auto",         -- "auto" | "snacks" | "telescope" | "fzf-lua" | "select"
  project = { dir = ".openbao" },
  env_files = { ".openbao.lua", ".openbao.json" },
}
```

## Security notes

- Secrets are sent to the CLI through stdin, never as arguments (not visible in `ps`).
- Secret buffers have no swap, undo or backup file, and are never written to disk.
- Generated files (`.env`, mirror) are created `0600`. Their content is plain text: keep them out of git.
- The plugin never logs values; messages list key names only.

## Troubleshooting

- `:checkhealth openbao` first.
- "permission denied" with a valid token: a policy problem, not a login problem (no login prompt is shown).
- "no KV v2 mount matches": set `mounts = { "secret" }` or `default_mount`.
- Namespaces: `env = { BAO_NAMESPACE = "..." }` (or `VAULT_NAMESPACE`).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md) (also for AI assistants). MIT licensed.
