local config = require("custom.ai.config")
local context = require("custom.ai.context")
local ui = require("custom.ai.ui")

local OLLAMA_HOST = config.OLLAMA_HOST
local OLLAMA_MODEL = config.OLLAMA_MODEL
local ai_ns = config.ai_ns

local get_treesitter_related_context = context.get_treesitter_related_context
local create_vertical_scratch = ui.create_vertical_scratch
local open_prompt_floating_buffer = ui.open_prompt_floating_buffer

local M = {}

function M.setup()
	-- 功能 4：【写代码并直接插入光标/选区下方 (动态锚点)】(Normal & Visual 模式按 <leader>aii)
	-- =================================================================
	local function ai_generate_and_insert(is_visual)
		local current_buf = vim.api.nvim_get_current_buf()
		local ft = vim.bo[current_buf].filetype
		local filename = vim.fn.expand("%:t")
		if filename == "" then
			filename = "untitled"
		end

		local snippet = ""
		local target_row = 0
		local related_defs = ""

		if is_visual then
			-- 🔴 1. Visual 模式下提取选区范围和 Tree-sitter 依赖
			local start_row = math.min(vim.fn.line("v"), vim.fn.line(".")) - 1
			target_row = math.max(vim.fn.line("v"), vim.fn.line(".")) - 1
			related_defs = get_treesitter_related_context(current_buf, start_row, target_row)

			vim.cmd('noau normal! "yy')
			snippet = vim.fn.getreg('"')
		else
			target_row = vim.api.nvim_win_get_cursor(0)[1] - 1
		end

		local target_line_text = vim.api.nvim_buf_get_lines(current_buf, target_row, target_row + 1, false)[1] or ""
		local base_indent = target_line_text:match("^(%s*)") or ""

		open_prompt_floating_buffer(" 💻 AI Code Generator (<C-s> to Insert | q to Cancel) ", function(prompt)
			if prompt == "" then
				print("⚠️ Prompt is empty, canceled.")
				return
			end

			local mark_id = vim.api.nvim_buf_set_extmark(current_buf, ai_ns, target_row, 0, {
				virt_text = { { " ⏳ AI is generating code here...", "Comment" } },
				virt_text_pos = "eol",
				invalidate = false,
			})

			print("⏳ Generating code for " .. ft .. "...")

			-- 🔴 2. 注入 Tree-sitter 依赖定义
			local user_content = ""
			if snippet ~= "" then
				local defs_block = ""
				if related_defs ~= "" then
					defs_block = string.format(
						[[<reference_context>
// Background dependencies:
```%s
%s
```
</reference_context>

]],
						ft,
						related_defs
					)
				end

				user_content = string.format(
					[[<instruction>
%s
</instruction>

%s<target_context file="%s" lang="%s">
```%s
%s
```
</target_context>]],
					prompt,
					defs_block,
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

<file_context file="%s" lang="%s" />]],
					prompt,
					filename,
					ft
				)
			end

			local payload = vim.fn.json_encode({
				model = OLLAMA_MODEL,
				messages = {
					{
						role = "system",
						content = "You are a code generation engine tailored for "
							.. ft
							.. ". Strictly follow the <instruction>. Base your generation on <target_context> and <reference_context> if provided. Output ONLY valid raw code to be inserted. NO markdown backticks (no ```). NO explanations, thoughts, or filler text.",
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
				think = false,
				stream = false,
			})

			vim.fn.jobstart({ "curl", "-s", "-X", "POST", OLLAMA_HOST .. "/api/chat", "-d", payload }, {
				stdout_buffered = true,
				on_stdout = function(_, data)
					local raw = table.concat(data, "")
					local ok, res = pcall(vim.fn.json_decode, raw)
					vim.schedule(function()
						-- 找回 mark 漂移后的最新行号
						local mark_pos = vim.api.nvim_buf_get_extmark_by_id(current_buf, ai_ns, mark_id, {})
						local current_row = target_row
						if mark_pos and #mark_pos >= 1 then
							current_row = mark_pos[1]
						end
						vim.api.nvim_buf_del_extmark(current_buf, ai_ns, mark_id)

						if ok and res.message and res.message.content then
							local msg = res.message.content

							if msg:find("</think>") then
								msg = msg:match("</think>%s*(.*)") or msg
							end

							-- 剥离 Markdown 代码块标签
							msg = msg:gsub("^```%w*%s*\n?", ""):gsub("\n?%s*```$", "")
							msg = vim.trim(msg)

							local lines = {}
							for _, line in ipairs(vim.split(msg, "\n")) do
								if vim.trim(line) == "" then
									table.insert(lines, "")
								else
									table.insert(lines, base_indent .. line)
								end
							end

							-- 插入在最新标记行的正下方（current_row + 1）
							vim.api.nvim_buf_set_lines(current_buf, current_row + 1, current_row + 1, false, lines)
							print("✓ Code generated and inserted successfully!")
						else
							print("❌ Failed to generate code:", raw)
						end
					end)
				end,
			})
		end)
	end

	vim.keymap.set("n", "<leader>aii", function()
		ai_generate_and_insert(false)
	end, { desc = "AI: Generate Code & Insert Below Cursor" })

	vim.keymap.set("v", "<leader>aii", function()
		ai_generate_and_insert(true)
	end, { desc = "AI: Generate Code from Context & Insert Below Selection" })
	-- =================================================================

end

return M
