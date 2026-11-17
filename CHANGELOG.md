# Changelog

## [Unreleased]

### Fixed
- Mount discovery crashed (`attempt to index vim.NIL`) when `secrets list` returned a mount with `"options": null`.

### Added
- Show which env is loaded in `vim.env`: `✔` in the `:Bao env load` picker, a virtual-text mark in the `.env` buffer (`⚠` when it changed since), and `require("openbao").statusline()`.
- `:Bao env pull` keeps variables commented out in the `.env` file (`# KEY=value`) commented, refreshes their value, and skips them in `vim.env`; `status` and `push --prune` ignore them.
- `:Bao env load [file]` and `:Bao env unload`: inject a `.env*` file of the project into `vim.env` (picker when several files exist; no shell, so `$` and accents are safe).
- `to_env` option on env sources: rewrites keys such as `a.b-c` into environment-style names (`A_BC`) on pull.
- `:Bao generate-conf [profile] [paths...] [--force]`: scaffolds a profile (`.env.<profile>`) in `.openbao.json`.
- Initial version: `:Bao` command with `login`, `status`, `browse`, `search`, `edit`, `new`, `reload`, `diff`, `reveal`,
  `versions`, `delete`, `env` and `project`.
- Secret buffers (`openbao://mount/path`): dotenv or JSON, `:w` writes with check-and-set, confirmation before removing keys,
  concealed values, no swap/undo files.
- Automatic login prompt when a call fails because of authentication; policy denials are reported as is.
- Project environment sync (`.openbao.json` / `.openbao.lua` profiles): pull to `vim.env` and a `0600` `.env` file,
  status, push with diff and optional `--prune`.
- Local mirror of a folder (`:Bao project`).
- KV v2 history: view, rollback, undelete.
- Pickers: snacks, telescope, fzf-lua, `vim.ui.select` fallback. `:checkhealth openbao`.
