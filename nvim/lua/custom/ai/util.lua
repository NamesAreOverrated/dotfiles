local M = {}

local function extract_doc_comment_only(raw_text)
		local lines = vim.split(raw_text, "\n")
		local result = {}
		local in_block = false
		local block_end_pat = nil

		for _, line in ipairs(lines) do
			local trimmed = vim.trim(line)

			-- 跳过开头的纯空白行
			if #result == 0 and trimmed == "" then
				goto continue
			end

			if not in_block then
				-- 1. 识别 C-style 块注释: /* 或 /**
				if trimmed:match("^/%*") then
					in_block = true
					block_end_pat = "%*/"
					table.insert(result, line)
					if #trimmed > 2 and trimmed:match("%*/$") then
						break
					end -- 单行闭合

				-- 2. 识别 Python/Julia 块注释: """ 或 '''
				elseif trimmed:match('^"""') or trimmed:match("^'''") then
					in_block = true
					block_end_pat = trimmed:sub(1, 3)
					table.insert(result, line)
					if #trimmed > 3 and trimmed:sub(-3) == block_end_pat then
						break
					end

				-- 3. 识别 Lua 块注释: --[[
				elseif trimmed:match("^%-%-%[%[") then
					in_block = true
					block_end_pat = "%]%]"
					table.insert(result, line)

				-- 4. 识别行注释 (Rust: ///, Go/C++: //, Python/Shell: #, Lua: --, Lisp: ;)
				elseif trimmed:match("^//") or trimmed:match("^#") or trimmed:match("^%-%-") or trimmed:match("^;") then
					table.insert(result, line)

				-- 5. 一旦在收集了注释后遇到了非注释行（即函数实体代码开始） -> 立即结束！
				else
					if #result > 0 then
						break
					end
				end
			else
				-- 处于块注释内部
				table.insert(result, line)
				if trimmed:match(block_end_pat) then
					break -- 块注释闭合，停止继续读取后续代码！
				end
			end

			::continue::
		end

		if #result > 0 then
			return table.concat(result, "\n")
		end
		return raw_text
	end
	local DOC_SPECS = {
		c = "C (Doxygen style using /** ... */ with @brief, @param, @return)",
		cpp = "C++ (Doxygen style using /** ... */ with @brief, @param, @return)",
		rust = "Rust (Rustdoc style using /// lines with markdown sections like # Arguments, # Returns, # Errors)",
		go = "Go (Official Go doc style using // comments starting with the function name)",
		python = 'Python (Docstring style enclosed in triple quotes """ ... """)',
		javascript = "JavaScript (JSDoc style using /** ... */ with @param, @returns)",
		typescript = "TypeScript (TSDoc/JSDoc style using /** ... */ with @param, @returns)",
		lua = "Lua (EmmyLua/LDoc style using --- with ---@param, ---@return)",
		sh = "Shell (Shell comment block using #)",
		bash = "Bash (Bash comment block using #)",
		ruby = "Ruby (YARD style using # comments with @param, @return)",
		java = "Java (Javadoc style using /** ... */ with @param, @return)",
		php = "PHP (PHPDoc style using /** ... */ with @param, @return)",
		cs = "C# (XML doc comments using /// <summary>, <param>, <returns>)",
		zig = "Zig (Doc comments using /// lines)",
	}
	local function strip_think(text)
		if not text then
			return ""
		end
		-- 寻找 </think> 的物理结束位置
		local _, end_idx = text:find("</think>")
		if end_idx then
			-- 物理切片：100% 完整保留 </think> 后面的所有多行内容与换行符
			return vim.trim(text:sub(end_idx + 1))
		end

		-- 兜底防呆：如果还在 <think> 内部就被截断了（没有 </think>），返回空字符串，防止误读思考草稿中的数字
		if text:match("^%s*<think>") then
			return ""
		end

		return vim.trim(text)
	end
	
M.extract_doc_comment_only = extract_doc_comment_only
M.DOC_SPECS = DOC_SPECS
M.strip_think = strip_think

return M
