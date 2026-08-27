local M = {}

M.OLLAMA_HOST = "http://127.0.0.1:11434"
M.OLLAMA_MODEL = "hf.co/bloomer010/Ling-3.0-tiny-GGUF:Q4_K_M"
M.SEARXNG_HOST = "http://127.0.0.1:8888"

-- Extmark namespace for tracking async insertions (solves drift when typing during generation)
M.ai_ns = vim.api.nvim_create_namespace("ai_dynamic_tracker")

return M
