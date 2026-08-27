local config = require("custom.ai.config")
local context = require("custom.ai.context")
local ui = require("custom.ai.ui")
local util = require("custom.ai.util")

local OLLAMA_HOST = config.OLLAMA_HOST
local OLLAMA_MODEL = config.OLLAMA_MODEL
local ai_ns = config.ai_ns

local get_treesitter_related_context = context.get_treesitter_related_context
local extract_doc_comment_only = util.extract_doc_comment_only
local DOC_SPECS = util.DOC_SPECS

local M = {}

function M.setup()
	-- 功能 3：【精准单语言专属 Doc 生成】(Visual 模式按 <leader>aid)
	-- =================================================================
	vim.keymap.set("v", "<leader>aid", function()
		local current_buf = vim.api.nvim_get_current_buf()
		local ft = vim.bo[current_buf].filetype

		-- 🔴 1. 锁定选区范围并用 Tree-sitter 提取依赖
		local start_row = math.min(vim.fn.line("v"), vim.fn.line(".")) - 1
		local end_row = math.max(vim.fn.line("v"), vim.fn.line(".")) - 1
		local related_defs = get_treesitter_related_context(current_buf, start_row, end_row)

		local first_line = vim.api.nvim_buf_get_lines(current_buf, start_row, start_row + 1, false)[1] or ""
		local indent = first_line:match("^(%s*)") or ""

		vim.cmd('noau normal! "yy')
		local snippet = vim.fn.getreg('"')

		local mark_id = vim.api.nvim_buf_set_extmark(current_buf, ai_ns, start_row, 0, {
			virt_text = { { " ⏳ AI is generating " .. ft .. " documentation...", "Comment" } },
			virt_text_pos = "eol",
			invalidate = false,
		})

		print("⏳ Generating " .. ft .. " documentation...")

		local spec = DOC_SPECS[ft] or (ft .. " standard documentation comments")

		-- 🔴 2. 组装用户输入：强化 XML 隔离，警告模型不要给 Context 写注释
		local user_prompt = ""
		if related_defs ~= "" then
			user_prompt = string.format(
				[[<reference_context>
// Read-only background definitions. DO NOT document these!
```%s
%s
```
</reference_context>

Generate documentation ONLY for this %s function:
<target_function>
```%s
%s
```
</target_function>]],
				ft,
				related_defs,
				ft,
				ft,
				snippet
			)
		else
			user_prompt = string.format(
				[[Generate documentation ONLY for this %s function:
<target_function>
```%s
%s
```
</target_function>]],
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
					content = string.format(
						[[You are a strict code documentation generator.
TARGET SPEC: %s.
CRITICAL RULES:
1. Output ONLY the raw documentation comment block strictly matching the TARGET SPEC.
2. Document ONLY the code inside <target_function>. IGNORE everything in <reference_context>.
3. ABSOLUTELY DO NOT output the function signature or function body!
4. NO TAUTOLOGY: Focus on return/error values, side effects, and invariants based on the provided context.
5. NO markdown backticks (no ```). Output the comment block ONLY.]],
						spec
					),
				},
				{
					role = "user",
					content = user_prompt,
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
					local mark_pos = vim.api.nvim_buf_get_extmark_by_id(current_buf, ai_ns, mark_id, {})
					local current_row = start_row
					if mark_pos and #mark_pos >= 1 then
						current_row = mark_pos[1]
					end
					vim.api.nvim_buf_del_extmark(current_buf, ai_ns, mark_id)

					if ok and res.message and res.message.content then
						local msg = res.message.content

						-- 1. 过滤思考过程
						if msg:find("</think>") then
							msg = msg:match("</think>%s*(.*)") or msg
						end

						-- 2. 去除 Markdown 代码块反引号
						msg = msg:gsub("^```%w*%s*\n?", ""):gsub("\n?%s*```$", "")
						msg = vim.trim(msg)

						-- 3. 全语言通用兜底截断
						msg = extract_doc_comment_only(msg)

						local lines = {}
						for _, line in ipairs(vim.split(msg, "\n")) do
							table.insert(lines, indent .. line)
						end

						-- 插入到顶端行上方
						vim.api.nvim_buf_set_lines(current_buf, current_row, current_row, false, lines)
						print("✓ " .. ft .. " documentation generated & inserted!")
					else
						print("❌ Failed to generate docstring")
					end
				end)
			end,
		})
	end, { desc = "AI: Generate Docstring & Insert Above" })

	-- =================================================================

end

return M
