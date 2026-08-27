local config = require("custom.ai.config")
local context = require("custom.ai.context")
local ui = require("custom.ai.ui")

local OLLAMA_HOST = config.OLLAMA_HOST
local OLLAMA_MODEL = config.OLLAMA_MODEL

local get_treesitter_related_context = context.get_treesitter_related_context
local create_vertical_scratch = ui.create_vertical_scratch
local open_prompt_floating_buffer = ui.open_prompt_floating_buffer

local M = {}

function M.setup()
	-- 功能 1：【选代码提问/查Bug/写单测】(Visual 模式按 <leader>aia)
	-- =================================================================
	vim.keymap.set("v", "<leader>aia", function()
		local current_buf = vim.api.nvim_get_current_buf()
		local ft = vim.bo[current_buf].filetype
		local filename = vim.fn.expand("%:t")
		if filename == "" then
			filename = "untitled"
		end

		-- 🔴 1. 抓取行号范围并提取 Tree-sitter 依赖定义
		local start_row = math.min(vim.fn.line("v"), vim.fn.line(".")) - 1
		local end_row = math.max(vim.fn.line("v"), vim.fn.line(".")) - 1
		local related_defs = get_treesitter_related_context(current_buf, start_row, end_row)

		vim.cmd('noau normal! "yy')
		local snippet = vim.fn.getreg('"')

		-- 传专属标题进弹窗
		open_prompt_floating_buffer(" 💡 Ask AI about selected code (<C-s> Submit | q to Cancel) ", function(prompt)
			if prompt == "" then
				print("⚠️ Prompt is empty, canceled.")
				return
			end

			local target_buf =
				create_vertical_scratch("markdown", "⏳ Generating response from " .. OLLAMA_MODEL .. "...")

			-- 🔴 2. 如果有提取到相关依赖，拼入独立的只读区域
			local user_content = ""
			if related_defs ~= "" then
				user_content = string.format(
					[[<instruction>
%s
</instruction>

<reference_context>
// Read-only background definitions (do not modify or review these unless asked):
```%s
%s
```
</reference_context>

<target_code file="%s" lang="%s">
```%s
%s
```
</target_code>]],
					prompt,
					ft,
					related_defs,
					filename,
					ft,
					ft,
					snippet
				)
			else
				user_content = string.format(
					[[<instruction>
%s
</instruction>

<target_code file="%s" lang="%s">
```%s
%s
```
</target_code>]],
					prompt,
					filename,
					ft,
					ft,
					snippet
				)
			end

			local payload = vim.fn.json_encode({
				model = OLLAMA_MODEL,
				messages = {
					{
						role = "system",
						content = "You are an expert programmer. Strictly follow the user's <instruction>. Focus your analysis, refactoring, or answer ONLY on the code inside <target_code>. Use <reference_context> merely as background knowledge. Output high quality code and concise explanations.",
					},
					{
						role = "user",
						content = user_content,
					},
				},
				options = {
					num_thread = 8,
					num_ctx = 16384,
				},
				think = true,
				stream = false,
			})
			vim.fn.jobstart({ "curl", "-s", "-X", "POST", OLLAMA_HOST .. "/api/chat", "-d", payload }, {
				stdout_buffered = true,
				on_stdout = function(_, data)
					local raw = table.concat(data, "")
					local ok, res = pcall(vim.fn.json_decode, raw)
					vim.schedule(function()
						if ok and res.message and res.message.content then
							local msg = res.message.content
							if msg:find("</think>") then
								msg = msg:match("</think>%s*(.*)") or msg
							end
							local lines = vim.split(msg, "\n")
							vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, lines)
						else
							vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, { "❌ Error calling Ollama:", raw })
						end
					end)
				end,
			})
		end)
	end, { desc = "AI: Ask/Analyze Code (Floating Editor -> Vertical Split)" })

	-- =================================================================
end

return M
