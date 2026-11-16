# Copilot instructions

Follow [AGENTS.md](../AGENTS.md): it holds the rules, the module map and the test commands.

The three rules that matter most:

1. Every change comes with tests in `tests/` (`make test` must pass with 0 failures).
2. Update `README.md` / `docs/` and `CHANGELOG.md` in the same change.
3. Secrets never appear in CLI arguments, logs or messages. Only `lua/openbao/cli.lua` spawns the binary.

Recipes for common tasks are in `.github/skills/`.
