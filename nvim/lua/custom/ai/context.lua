local M = {}

-- 全语言 LSP + Tree-sitter 智能依赖提取器
-- Extracted from nvim/init.lua
local function get_treesitter_related_context(buf, start_row, end_row)
		local ft = vim.bo[buf].filetype
		local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
		local clients = get_clients({ bufnr = buf })
		if #clients == 0 then
			return ""
		end
		local client = clients[1]

		-- 全语言通用的高频干扰词 (基础类型、常用变量名、控制流)
		local IGNORED_SYMBOLS = {
			["int"] = true,
			["char"] = true,
			["void"] = true,
			["bool"] = true,
			["float"] = true,
			["double"] = true,
			["string"] = true,
			["String"] = true,
			["str"] = true,
			["err"] = true,
			["error"] = true,
			["Error"] = true,
			["true"] = true,
			["false"] = true,
			["null"] = true,
			["None"] = true,
			["nil"] = true,
			["self"] = true,
			["this"] = true,
			["super"] = true,
			["print"] = true,
			["println"] = true,
			["fmt"] = true,
			["log"] = true,
			["len"] = true,
			["append"] = true,
			["push"] = true,
			["pop"] = true,
			["var"] = true,
			["Console"] = true,
			["Task"] = true,
			["await"] = true,
			["async"] = true,
		}

		-- 全语言标准库及包管理器路径黑名单 (如果 LSP 指向这些路径，则直接丢弃，不传给大模型)
		local SYS_PATH_PATTERNS = {
			"^/usr/",
			"^/opt/", -- C/C++ 系统库
			"/.cargo/registry/",
			"/.rustup/", -- Rust 标准库与第三方包
			"/go/pkg/mod/",
			"/usr/local/go/", -- Go 标准库与第三方包
			"/site%-packages/",
			"/usr/lib/python", -- Python 第三方包与标准库
			"/node_modules/", -- JS/TS 依赖包
			"/.nuget/packages/", -- NuGet 全局缓存
			"/dotnet/packs/",
			"/usr/share/dotnet/", -- .NET SDK 系统目录
			"^omnisharp://",
			"^csharp_ls://",
			"^%$metadata%$", -- C# LSP 虚拟元数据路径 (System 库)
		}

		local function extract_full_ast_node(file_path, row, col)
			local content = ""
			local bufnr = vim.fn.bufnr(file_path)
			if vim.api.nvim_buf_is_loaded(bufnr) then
				content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
			elseif vim.fn.filereadable(file_path) == 1 then
				content = table.concat(vim.fn.readfile(file_path), "\n")
			else
				return nil
			end

			local target_ft = ft
			local ext = vim.fn.fnamemodify(file_path, ":e")
			if ext == "h" or ext == "c" then
				target_ft = "c"
			elseif ext == "hpp" or ext == "cpp" then
				target_ft = "cpp"
			elseif ext == "rs" then
				target_ft = "rust"
			elseif ext == "go" then
				target_ft = "go"
			elseif ext == "py" then
				target_ft = "python"
			elseif ext == "ts" or ext == "js" then
				target_ft = "typescript"
			elseif ext == "cs" then
				target_ft = "c_sharp"
			end

			local ok, parser = pcall(vim.treesitter.get_string_parser, content, target_ft)
			if ok and parser then
				local tree = parser:parse()[1]
				if tree then
					local root = tree:root()
					local node = root:named_descendant_for_range(row, col, row, col)
					while node do
						local parent = node:parent()
						local nt = node:type()
						-- 泛用型顶层定义匹配 (覆盖 C/Rust/Go/Python/TS)
						if
							parent
							and (
								parent:type() == root:type()
								or nt:match("declaration")
								or nt:match("specifier")
								or nt:match("item")
								or nt:match("function")
								or nt:match("class")
							)
						then
							local text = vim.treesitter.get_node_text(node, content)
							if
								nt:match("function_definition")
								or nt:match("function_item")
								or nt:match("func_decl")
							then
								-- 函数体过长时，只取头部签名
								text = text:match("^(.-)%s*{") or text
							end
							return text
						end
						node = parent
					end
				end
			end

			local lines = vim.split(content, "\n")
			return lines[row + 1] or nil
		end

		local high_priority_symbols = {}
		local normal_symbols = {}
		local seen_names = {}

		local ok, parser = pcall(vim.treesitter.get_parser, buf)
		if ok and parser then
			local root = parser:parse()[1]:root()

			local sel_node = root:named_descendant_for_range(start_row, 0, end_row, 0)
			if sel_node then
				for n in sel_node:iter_children() do
					if n:type():match("declarator") or n:type():match("identifier") then
						local fn_name = vim.treesitter.get_node_text(n, buf):match("([%a_][%w_]*)")
						if fn_name then
							IGNORED_SYMBOLS[fn_name] = true
						end
					end
				end
			end

			local function scan_node(n)
				local s_row, s_col, e_row, _ = n:range()
				if s_row >= start_row and e_row <= end_row then
					local n_type = n:type()
					local parent = n:parent()
					local p_type = parent and parent:type() or ""

					if n_type:match("identifier") or n_type:match("type") then
						local name = vim.treesitter.get_node_text(n, buf)
						if #name > 1 and not IGNORED_SYMBOLS[name] and not seen_names[name] then
							seen_names[name] = true
							local item = { row = s_row, col = s_col, name = name }

							if p_type:match("call") or n_type:match("type") or p_type:match("type") then
								table.insert(high_priority_symbols, item)
							else
								table.insert(normal_symbols, item)
							end
						end
					end
				end
				for child in n:iter_children() do
					scan_node(child)
				end
			end
			scan_node(root)
		end

		local query_symbols = {}
		for _, item in ipairs(high_priority_symbols) do
			table.insert(query_symbols, item)
		end
		for _, item in ipairs(normal_symbols) do
			table.insert(query_symbols, item)
		end

		if #query_symbols == 0 then
			return ""
		end

		local matched_defs = {}
		local seen_defs = {}

		for i = 1, math.min(#query_symbols, 15) do
			local sym = query_symbols[i]
			local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
			params.position.line = sym.row
			params.position.character = sym.col

			local res = client.request_sync("textDocument/definition", params, 150, buf)
			if res and res.result then
				local locations = res.result
				if not vim.islist(locations) then
					locations = { locations }
				end

				for _, loc in ipairs(locations) do
					local uri = loc.uri or loc.targetUri
					local range = loc.range or loc.targetRange

					if uri and range then
						local file_path = vim.uri_to_fname(uri)
						local def_row = range.start.line
						local def_col = range.start.character

						local is_self = (file_path == vim.api.nvim_buf_get_name(buf))
							and (def_row >= start_row and def_row <= end_row)

						-- 🔴 核心过滤：检查是否属于全语言标准库/系统路径
						local is_sys = false
						for _, pat in ipairs(SYS_PATH_PATTERNS) do
							if file_path:match(pat) then
								is_sys = true
								break
							end
						end

						if not is_self and not is_sys then
							local full_def = extract_full_ast_node(file_path, def_row, def_col)
							if full_def and full_def ~= "" and not seen_defs[full_def] then
								seen_defs[full_def] = true
								local fname = vim.fs.basename(file_path)
								table.insert(matched_defs, string.format("// [%s]\n%s", fname, vim.trim(full_def)))
							end
						end
					end
				end
			end
		end

		if #matched_defs > 0 then
			return table.concat(matched_defs, "\n\n")
		end
		return ""
	end -- -----------------------------------------------------------------
	
M.get_treesitter_related_context = get_treesitter_related_context

return M
