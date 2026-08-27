local config = require("custom.ai.config")
local ui = require("custom.ai.ui")

local OLLAMA_HOST = config.OLLAMA_HOST
local OLLAMA_MODEL = config.OLLAMA_MODEL

local create_vertical_scratch = ui.create_vertical_scratch
local open_prompt_floating_buffer = ui.open_prompt_floating_buffer

local M = {}

function M.setup()
	-- 功能 2：【一键生成 Commit】(支持弹窗写提示，q 取消，光标不乱跳)
	-- =================================================================
	vim.keymap.set("n", "<leader>aic", function()
		local diff = vim.fn.system("git diff --cached")
		if diff == "" then
			diff = vim.fn.system("git diff")
		end
		if diff == "" then
			print("⚠️ No git changes detected.")
			return
		end

		-- 弹窗输入，如果按 q 会直接 cancel，什么都不会触发
		open_prompt_floating_buffer(
			" 📝 Commit Intent (<C-s> Submit | Empty for Auto | q to Cancel) ",
			function(intent)
				-- 确认提交后，才在右侧开辟分屏（并且光标依然停留在你的代码窗口）
				local target_buf = create_vertical_scratch("gitcommit", "# ⏳ Generating commit message...")

				local user_content = ""
				if intent ~= "" then
					user_content = string.format(
						[[
<developer_intent>
%s
</developer_intent>

<git_diff>
%s
</git_diff>
]],
						intent,
						diff
					)
				else
					user_content = string.format(
						[[
<git_diff>
%s
</git_diff>
]],
						diff
					)
				end

				local payload = vim.fn.json_encode({
					model = OLLAMA_MODEL,
					messages = {
						{
							role = "system",
							content = [[You are an anti-bloat senior engineer. Write clean, fluff-free conventional commit messages.

RULES:
1. Format: "<type>(<optional-scope>): <summary>" followed by 3-4 bullet points.
2. Subject line <= 50 chars, imperative mood.
3. TELEGRAPHIC BULLETS ONLY: Each bullet MUST be a single short line (< 60 chars) starting with a verb.
4. NO RUN-ON SENTENCES: Ban participial fluff like ", enabling...", ", allowing...", or ", which...".
5. Align closely with <developer_intent> if provided.
6. NO markdown backticks (no ```), NO introductory labels. Output commit directly.]],
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
							if ok and res.message and res.message.content then
								local msg = res.message.content

								if msg:find("</think>") then
									msg = msg:match("</think>%s*(.*)") or msg
								end

								-- 清洗多余的标题前缀和 markdown 格式
								msg = msg:gsub("^[Cc]ommit [Mm]essage:%s*", "")
								msg = msg:gsub("^[Hh]ere is the commit message:%s*", "")
								msg = msg:gsub("^```gitcommit%s*", ""):gsub("^```%s*", ""):gsub("%s*```$", "")
								msg = vim.trim(msg)

								local lines = vim.split(msg, "\n")
								vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, lines)
								vim.fn.setreg("+", msg)
								print("✓ Commit message generated & copied to clipboard!")
							else
								vim.api.nvim_buf_set_lines(
									target_buf,
									0,
									-1,
									false,
									{ "❌ Error generating commit:", raw }
								)
							end
						end)
					end,
				})
			end
		)
	end, { desc = "AI: Generate Git Commit Message" })
	-- -----------------------------------------------------------------

end

return M
