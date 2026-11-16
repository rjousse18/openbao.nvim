# Changelog

## [Unreleased]

### Added
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
