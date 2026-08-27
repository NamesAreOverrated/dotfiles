local M = {}

local function create_vertical_scratch(ft, initial_text)
		local orig_win = vim.api.nvim_get_current_win()

		vim.cmd("botright vnew")
		local buf = vim.api.nvim_get_current_buf()
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false
		vim.bo[buf].filetype = ft or "markdown"

		-- 🔴 核心修复：用 vim.split 把带换行的字符串切成合法的行数组
		if initial_text then
			local lines = vim.split(initial_text, "\n")
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		end

		if vim.api.nvim_win_is_valid(orig_win) then
			vim.api.nvim_set_current_win(orig_win)
		end

		return buf
	end -- -----------------------------------------------------------------
	local function open_prompt_floating_buffer(title_or_cb, maybe_cb)
		local title = " 🤖 AI Prompt Editor (<C-s> to Submit | q to Cancel) "
		local on_submit = nil

		-- 自适应处理传参：无论传 1 个参数还是 2 个参数都不会报错
		if type(title_or_cb) == "function" then
			on_submit = title_or_cb
		else
			title = title_or_cb or title
			on_submit = maybe_cb
		end

		local width = math.floor(vim.o.columns * 0.65)
		local height = math.floor(vim.o.lines * 0.40)
		local row = math.floor((vim.o.lines - height) / 2)
		local col = math.floor((vim.o.columns - width) / 2)

		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false
		vim.bo[buf].filetype = "markdown"

		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			style = "minimal",
			border = "rounded",
			title = title,
			title_pos = "center",
		})

		local function submit()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local prompt = vim.trim(table.concat(lines, "\n"))
			vim.api.nvim_win_close(win, true)
			if on_submit then
				on_submit(prompt)
			end
		end

		local function cancel()
			vim.api.nvim_win_close(win, true)
			print("⏹ Action canceled.")
		end

		vim.keymap.set("n", "q", cancel, { buffer = buf, nowait = true })
		vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf })

		vim.cmd("startinsert")
	end
	
M.create_vertical_scratch = create_vertical_scratch
M.open_prompt_floating_buffer = open_prompt_floating_buffer

return M
