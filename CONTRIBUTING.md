# Contributing

Thanks for helping! Bug reports are most useful with: Neovim version, `bao`/`vault` version,
what you ran, and the output of `:checkhealth openbao` (remove addresses/secrets).

AI assistants: read [AGENTS.md](AGENTS.md), it has the rules and the module map.

## Setup and tests

```sh
make test                                 # clones plenary into ./.deps, runs all specs
SPEC=buffer make test                     # one spec file
make test DEPS=~/.local/share/nvim/lazy   # reuse existing checkouts
make integration                          # optional: real `bao server -dev` (needs the bao binary)
stylua lua plugin tests                   # format
```

The unit specs use `tests/fixtures/fake-bao`, a fake CLI, so no OpenBao install is needed.
CI runs the suite on Neovim stable and nightly, plus the integration test and `stylua --check`.

## Rules of the project

- **Every change needs a test** (new behavior, bug fix, option, command). Bug fix: write the failing spec first.
- **Docs in the same change**: `README.md`, `docs/`, and `CHANGELOG.md` under `## [Unreleased]`.
- Secrets never appear in CLI arguments, logs or messages (key names are fine).
- Only `lua/openbao/cli.lua` spawns the binary.

## Architecture in one paragraph

`:Bao <sub>` (`commands.lua`) calls feature modules (`buffer`, `browse`, `history`, `env`, `project`). They talk to
OpenBao only through `kv.lua` / `mounts.lua` / `auth.lua`, which use `client.call` (CLI + automatic re-login) on top of
`cli.run` (the only `vim.system` caller). `format.lua` converts secrets to and from buffer text and is pure.
Details and diagrams of the flows: [docs/architecture.md](docs/architecture.md). Why things are the way they are:
[docs/decisions.md](docs/decisions.md).

## Commits and versioning

[Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `test:`, `chore:`.
[Semantic Versioning](https://semver.org/). Keep `CHANGELOG.md` up to date.
