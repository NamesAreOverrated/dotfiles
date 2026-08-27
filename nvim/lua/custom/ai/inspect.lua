local context = require("custom.ai.context")
local ui = require("custom.ai.ui")

local get_treesitter_related_context = context.get_treesitter_related_context
local create_vertical_scratch = ui.create_vertical_scratch

local M = {}

function M.setup()
	-- 调试工具：【一键查看 Tree-sitter 到底抓到了什么】(Visual 模式按 <leader>ait)
	-- =================================================================
	vim.keymap.set("v", "<leader>ait", function()
		local current_buf = vim.api.nvim_get_current_buf()
		local ft = vim.bo[current_buf].filetype
		local start_row = math.min(vim.fn.line("v"), vim.fn.line(".")) - 1
		local end_row = math.max(vim.fn.line("v"), vim.fn.line(".")) - 1

		-- 调用提取函数
		local defs = get_treesitter_related_context(current_buf, start_row, end_row)

		if defs == "" then
			print("ℹ️ Tree-sitter 没有在外部发现该函数用到的顶层 struct / 全局变量。")
		else
			-- 直接在右侧开一个分屏把提取出来的代码原原本本打印出来
			create_vertical_scratch(ft, "# 🌲 Tree-sitter 自动提取到的关联定义:\n\n" .. defs)
			print("✓ 成功提取！已在右侧窗口展示。")
		end
	end, { desc = "AI: Inspect Tree-sitter Context" })

	-- -----------------------------------------------------------------

end

return M
