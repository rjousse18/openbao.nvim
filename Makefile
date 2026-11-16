# Test suite: needs plenary.nvim, cloned into ./.deps on first run.
# The CLI is replaced by tests/fixtures/fake-bao (a Lua script run by nvim), so no OpenBao server is needed.
DEPS ?= .deps

deps:
	@mkdir -p $(DEPS)
	@[ -d $(DEPS)/plenary.nvim ] || git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(DEPS)/plenary.nvim

# SPEC=format make test  -> runs tests/format_spec.lua only
test: deps
	@chmod +x tests/fixtures/fake-bao
	OPENBAO_DEPS=$(abspath $(DEPS)) nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/$(if $(SPEC),$(SPEC)_spec.lua,) { minimal_init = 'tests/minimal_init.lua', sequential = true }"

# Optional: runs against a real `bao server -dev` (needs the bao binary).
integration: deps
	OPENBAO_INTEGRATION=1 OPENBAO_DEPS=$(abspath $(DEPS)) nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedFile tests/integration/dev_server_spec.lua"

.PHONY: deps test integration
