---
name: add-cli-call
description: Add a new OpenBao/Vault CLI operation to openbao.nvim (new kv verb, new auth or sys call), including the fake CLI used by tests. Use when the plugin needs data or an action it cannot get yet.
---

# Add a CLI call

1. **Check the CLI syntax** for both `bao` and `vault` (`bao kv --help`). Both must accept the same arguments,
   otherwise handle the difference explicitly.
2. **Add a function in the owning module**, never in a feature module:
   - KV operations: `lua/openbao/kv.lua`, built on the local `kv(sub, full, flags, opts, cb)` helper
     (resolves the mount, adds `-format=json -mount=`, goes through `client.call`).
   - Auth / token: `auth.lua`. Mount discovery: `mounts.lua`.
   Result convention: `cb(err, value)` with `err = { kind = "not_found"|"cas"|"auth"|"error", msg }`.
   Add a `kind` in `classify()` only if callers need to react to it.
3. **Secrets**: a body (values) goes through `opts.stdin` and a trailing `-` argument. Never in arguments.
4. **JSON**: pass `json = true`; empty stdout is accepted (some verbs print nothing). Do not parse text output.
5. **Extend `tests/fixtures/fake-bao`** with the new verb, mirroring real behavior (exit codes, stderr text such as
   `No value found at ...`, JSON shape). Keep it minimal; it is documented at the top of the file.
6. **Tests (mandatory)** in `tests/cli_kv_spec.lua` (or `auth_spec.lua`): success, not-found/denied, and that no value
   shows up in `helpers.calls(dir)`. If you can, add the same operation to `tests/integration/dev_server_spec.lua`.
7. Update `docs/architecture.md` if a new flow appears, and `CHANGELOG.md`.
