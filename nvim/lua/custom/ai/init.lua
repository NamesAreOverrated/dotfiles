-- custom.ai - aggregated AI suite
-- Extracted from nvim/init.lua do-block (originally ~1600 lines)
-- Each submodule registers its own keymaps via M.setup()

local M = {}

function M.setup(opts)
  opts = opts or {}
  -- Allow overriding config if passed from init.lua
  local config = require("custom.ai.config")
  if opts.ollama_host then config.OLLAMA_HOST = opts.ollama_host end
  if opts.ollama_model then config.OLLAMA_MODEL = opts.ollama_model end
  if opts.searxng_host then config.SEARXNG_HOST = opts.searxng_host end

  -- Core helpers (no side-effects, just to ensure they load)
  require("custom.ai.context")
  require("custom.ai.ui")
  require("custom.ai.util")

  -- Feature modules - each registers keymaps
  require("custom.ai.ask").setup()
  require("custom.ai.commit").setup()
  require("custom.ai.doc").setup()
  require("custom.ai.insert").setup()
  require("custom.ai.inspect").setup()
  require("custom.ai.search").setup()
end

return M
