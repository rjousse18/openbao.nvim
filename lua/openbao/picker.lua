--- One `select(items, opts, cb)` entry point over the user's picker (snacks, telescope, fzf-lua)
--- with `vim.ui.select` as the fallback.
local config = require("openbao.config")

local M = {}

---@return "snacks"|"telescope"|"fzf-lua"|"select"
function M.detect()
  local wanted = config.options.picker
  if wanted ~= "auto" then
    return wanted
  end
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    return "snacks"
  end
  if pcall(require, "telescope") then
    return "telescope"
  end
  if pcall(require, "fzf-lua") then
    return "fzf-lua"
  end
  return "select"
end

local backends = {}

function backends.snacks(items, opts, cb)
  require("snacks").picker.select(items, { prompt = opts.prompt }, function(choice)
    cb(choice)
  end)
end

function backends.telescope(items, opts, cb)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values
  pickers
    .new({}, {
      prompt_title = opts.prompt,
      finder = finders.new_table({ results = items }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_buf)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_buf)
          if entry then
            cb(entry[1])
          end
        end)
        return true
      end,
    })
    :find()
end

backends["fzf-lua"] = function(items, opts, cb)
  require("fzf-lua").fzf_exec(items, {
    prompt = (opts.prompt or "") .. "> ",
    actions = {
      ["default"] = function(selected)
        if selected and selected[1] then
          cb(selected[1])
        end
      end,
    },
  })
end

function backends.select(items, opts, cb)
  vim.ui.select(items, { prompt = opts.prompt }, cb)
end

---@param items string[]
---@param opts { prompt: string }
---@param cb fun(choice: string?)
function M.select(items, opts, cb)
  backends[M.detect()](items, opts, cb)
end

return M
