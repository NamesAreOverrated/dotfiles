local config = require("custom.ai.config")
local ui = require("custom.ai.ui")
local util = require("custom.ai.util")

local OLLAMA_HOST = config.OLLAMA_HOST
local OLLAMA_MODEL = config.OLLAMA_MODEL
local SEARXNG_HOST = config.SEARXNG_HOST

local strip_think = util.strip_think
local create_vertical_scratch = ui.create_vertical_scratch
local open_prompt_floating_buffer = ui.open_prompt_floating_buffer

local function fetch_searxng_single(query, maybe_cat, maybe_cb)
		local stdout_chunks = {}
		local category = "general"
		local callback = nil

		-- 🔴 核心防呆：自适应识别 category 和 callback
		if type(maybe_cat) == "function" then
			callback = maybe_cat
			category = "general"
		else
			category = maybe_cat or "general"
			callback = maybe_cb
		end

		-- 如果完全没传 callback，直接返回避免崩溃
		if type(callback) ~= "function" then
			return
		end

		-- 内部执行器，支持一次截断重试（应对过长 query 触发上游 429/空结果）
		local function do_fetch(q, is_retry)
			stdout_chunks = {}
			local cmd = {
				"curl",
				"-s",
				"-m",
				"10",
				"--retry",
				"1",
				"--retry-delay",
				"1",
				"-H",
				"User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
				"-H",
				"Accept: application/json",
				"--compressed",
				"-G",
				SEARXNG_HOST .. "/search",
				"--data-urlencode",
				"q=" .. q,
				"-d",
				"format=json",
				"-d",
				"categories=" .. category,
			}

			local SEO_DOMAINS_BLACKLIST = {
				"geeksforgeeks.org",
				"techradar.com",
				"tutorialspoint.com",
				"javatpoint.com",
				"w3schools.com",
				"wikihow.com",
				"hackage.haskell.org",
				"reddit.com",
				"quora.com",
				"medium.com",
				"zhihu.com",
			}

			vim.fn.jobstart(cmd, {
				stdout_buffered = true,
				on_stdout = function(_, data)
					if data then
						vim.list_extend(stdout_chunks, data)
					end
				end,
				on_exit = function(_, exit_code)
					if exit_code == 0 then
						local raw = table.concat(stdout_chunks, "")
						local ok, res = pcall(vim.fn.json_decode, raw)
						if ok and res and res.results then
							local filtered = {}
							local unfiltered = {}
							for _, item in ipairs(res.results) do
								local url = item.url or ""
								if url ~= "" then
									table.insert(unfiltered, {
										title = item.title or "Untitled",
										url = url,
										snippet = item.content or "",
									})
								end
								local is_trash = false
								for _, bad in ipairs(SEO_DOMAINS_BLACKLIST) do
									if url:find(bad, 1, true) then
										is_trash = true
										break
									end
								end
								if not is_trash and url ~= "" and #filtered < 10 then
									table.insert(filtered, {
										title = item.title or "Untitled",
										url = url,
										snippet = item.content or "",
									})
								end
							end
							if #filtered > 0 then
								callback(filtered)
								return
							elseif #unfiltered > 0 then
								-- 软降级：全被黑名单过滤时返回前 5 个未过滤结果，避免直接空
								local fallback = {}
								for i = 1, math.min(5, #unfiltered) do
									fallback[i] = unfiltered[i]
								end
								callback(fallback)
								return
							end
						else
							-- JSON 解析失败，可能是 SearXNG 返回 429 HTML，尝试截断重试
							if not is_retry and #q > 60 then
								vim.defer_fn(function()
									do_fetch(q:sub(1, 60), true)
								end, 800)
								return
							end
						end
					end
					-- 网络错误或空结果，截断重试一次
					if not is_retry and #q > 60 then
						vim.defer_fn(function()
							do_fetch(q:sub(1, 60), true)
						end, 800)
						return
					end
					callback({})
				end,
			})
		end
		do_fetch(query, false)
	end
	-- -----------------------------------------------------------------
	local function fetch_page_content(target_url, callback)
		if not target_url or not target_url:match("^http") then
			callback("No readable URL.")
			return
		end

		local function fetch_via_jina(cb)
			local stdout_chunks = {}
			local reader_url = "https://r.jina.ai/" .. target_url
			-- jina 需要走代理（若 cm-network 开启则 env 已有 http_proxy），SearXNG 本地不走代理已通过 no_proxy 排除
			vim.fn.jobstart({
				"curl",
				"-s",
				"-m",
				"7",
				"--retry",
				"1",
				"--retry-delay",
				"1",
				"-H",
				"User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
				reader_url,
			}, {
				stdout_buffered = true,
				on_stdout = function(_, data)
					if data then
						vim.list_extend(stdout_chunks, data)
					end
				end,
				on_exit = function(_, exit_code)
					if exit_code == 0 then
						local page_text = table.concat(stdout_chunks, "")
						-- jina 失败时会返回错误提示而非空，简单判定长度
						if page_text ~= "" and not page_text:match("Failed to fetch") and #vim.trim(page_text) > 80 then
							cb(page_text:sub(1, 12000))
							return
						end
					end
					cb(nil)
				end,
			})
		end

		local function fetch_direct(cb)
			local stdout_chunks = {}
			vim.fn.jobstart({
				"curl",
				"-sL",
				"-m",
				"7",
				"--retry",
				"1",
				"-H",
				"User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
				target_url,
			}, {
				stdout_buffered = true,
				on_stdout = function(_, data)
					if data then
						vim.list_extend(stdout_chunks, data)
					end
				end,
				on_exit = function(_, exit_code)
					if exit_code == 0 then
						local raw = table.concat(stdout_chunks, "")
						-- 粗略去 HTML 标签，避免直接返回整页 HTML 污染 LLM 上下文
						local stripped = raw:gsub("<[^>]+>", " "):gsub("%s+", " ")
						stripped = vim.trim(stripped)
						if stripped ~= "" then
							cb(stripped:sub(1, 8000))
							return
						end
					end
					cb("Failed to fetch page.")
				end,
			})
		end

		fetch_via_jina(function(jina_text)
			if jina_text then
				callback(jina_text)
			else
				fetch_direct(callback)
			end
		end)
	end

  -- =================================================================
	-- 核心功能：【通用 AI 联网搜索 (自适应双模路由：全景融合 vs 精准单篇)】
	-- =================================================================
	local function ai_search_action(is_visual)
		local ft = vim.bo.filetype
		local filename = vim.fn.expand("%:t")
		local snippet = ""

		if is_visual then
			vim.cmd('noau normal! "yy')
			snippet = vim.fn.getreg('"')
		end

		open_prompt_floating_buffer(" 🔍 AI Adaptive Search (<C-s> Search | q to Cancel) ", function(prompt)
			if prompt == "" then
				return
			end

			local target_buf = create_vertical_scratch(
				"markdown",
				"# 🔍 AI Web Search Running...\n\n[1/5] Classifying intent and generating queries..."
			)

			local user_query = prompt
			if snippet ~= "" then
				user_query = string.format("%s\n\nContext code:\n```%s\n%s\n```", prompt, ft, snippet)
			end

			-- 🔴 阶段 1：自适应模式判定 + 通用三维 Query 生成
			local query_gen_payload = vim.fn.json_encode({
				model = OLLAMA_MODEL,
				messages = {
					{
						role = "system",
						content = [[You are a search query engineer and intent router.
Task:
1. Classify the user's intent into ONE strategy mode:
   - "precision": For specific API usage, syntax, exact errors, or implementation details (requires ONE authoritative source to avoid version mixing).
   - "synthesis": For broad overviews, learning paths, roadmaps, comparisons, or conceptual questions (requires fusing MULTIPLE sources).

2. Convert the user's natural language question into exactly 3 dense, distinct keyword queries for search engines.
   - Strip conversational filler.
   - Use high-signal domain terms, exact identifiers, and substantive keywords.
   - Vary the 3 queries across complementary angles (e.g. Core Entity, Practical Application, Broader Context).

OUTPUT FORMAT:
MODE: <precision|synthesis>
<query 1>
<query 2>
<query 3>]],
					},
					{
						role = "user",
						content = user_query,
					},
				},
				options = { num_predict = 1024, temperature = 0.1 },
				think = true,
				stream = false,
			})
			local q_chunks = {}
			vim.fn.jobstart({ "curl", "-s", "-X", "POST", OLLAMA_HOST .. "/api/chat", "-d", query_gen_payload }, {
				stdout_buffered = true,
				on_stdout = function(_, data)
					if data then vim.list_extend(q_chunks, data) end
				end,
				on_exit = function()
					local q_raw = table.concat(q_chunks, "")
					local ok_q, res_q = pcall(vim.fn.json_decode, q_raw)
					local generated_queries = {}
					local search_mode = "synthesis" -- 默认安全模式

					if ok_q and res_q.message and res_q.message.content then
						local text = strip_think(res_q.message.content)

						for line in text:gmatch("[^\r\n]+") do
							local clean = vim.trim(line)
							local mode_match = clean:match("^MODE:%s*(%w+)")
							if mode_match then
								search_mode = mode_match:lower()
							else
								clean = clean
									:gsub("^%d+[%.:%s%-]*", "")
									:gsub("^[%*%-•]%s*", "")
									:gsub("^[\"']", "")
									:gsub("[\"']$", "")
								clean = vim.trim(clean)
								local low = clean:lower()
								if
									#clean > 3
									and not low:match("^here are")
									and not low:match("^output")
									and not low:match("^query")
									and not low:match("^let me")
									and not low:match("^the user")
								then
									table.insert(generated_queries, clean)
								end
							end
						end
					end

					if search_mode ~= "precision" and search_mode ~= "synthesis" then
						search_mode = "synthesis"
					end
					if #generated_queries == 0 then
						table.insert(generated_queries, prompt)
					end
					while #generated_queries > 3 do
						table.remove(generated_queries)
					end

					vim.schedule(function()
						local q_preview = {
							"# 🔍 AI Web Search Running...",
							"",
							string.format("> 🧭 **Strategy Mode:** `%s` (%s)", search_mode, search_mode == "precision" and "Single-Source Precision" or "Multi-Source Fusion"),
							"",
							"[2/5] AI generated 3 orthogonal queries:",
						}
						for i, q in ipairs(generated_queries) do
							table.insert(q_preview, string.format("  %d. `%s`", i, q))
						end
						table.insert(q_preview, "")
						table.insert(q_preview, "⏳ Fetching and merging candidate results from SearXNG...")
						vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, q_preview)
					end)

					-- 🔴 阶段 2：并行发起 3 路 SearXNG 搜索并交错去重填满 15 个
					local all_results = {}
					local completed = 0
					local total_searches = #generated_queries

					for q_idx, q_text in ipairs(generated_queries) do
						fetch_searxng_single(q_text, function(items)
							all_results[q_idx] = items
							completed = completed + 1

							if completed == total_searches then
								local merged_candidates = {}
								local seen_urls = {}

								for rank = 1, 8 do
									for s_idx = 1, total_searches do
										local bucket = all_results[s_idx] or {}
										local item = bucket[rank]
										if item and item.url ~= "" and not seen_urls[item.url] then
											seen_urls[item.url] = true
											item.id = #merged_candidates + 1
											table.insert(merged_candidates, item)
											if #merged_candidates >= 15 then break end
										end
									end
									if #merged_candidates >= 15 then break end
								end

								if #merged_candidates == 0 then
									vim.schedule(function()
										local debug_info = { "❌ No search results found across all queries.", "", "Searched Queries:" }
										for idx, q in ipairs(generated_queries) do
											table.insert(debug_info, string.format("- Query %d: `%s` (Returned: %d results)", idx, q, #(all_results[idx] or {})))
										end
										vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, debug_info)
									end)
									return
								end

								local sources_header = { string.format("### 🎯 Optimized Search Queries (Mode: %s):", search_mode:upper()) }
								for i, q in ipairs(generated_queries) do
									table.insert(sources_header, string.format("  %d. `%s`", i, q))
								end
								table.insert(sources_header, "")
								table.insert(sources_header, "### 🌐 Candidate Sources (Top 15 Interleaved):")
								table.insert(sources_header, "")
								for _, item in ipairs(merged_candidates) do
									table.insert(sources_header, string.format("- [%d] [%s](%s)", item.id, item.title, item.url))
								end
								table.insert(sources_header, "")
								table.insert(sources_header, "---")
								table.insert(sources_header, "")

								local candidate_prompts = {}
								for _, item in ipairs(merged_candidates) do
									table.insert(candidate_prompts, string.format("[%d] %s (URL: %s)\nSnippet: %s", item.id, item.title, item.url, item.snippet))
								end

								vim.schedule(function()
									vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, {
										"# 🔍 Web Search: `" .. prompt .. "`",
										"",
										"[3/5] Evaluating candidates to shortlist the Top 3 most relevant sources...",
									})
								end)

								-- 🔴 阶段 3：初筛 3 强
								local shortlist_payload = vim.fn.json_encode({
									model = OLLAMA_MODEL,
									messages = {
										{
											role = "system",
											content = "You are an information retrieval evaluator. Given the user query and candidate search results, identify the 3 most promising candidate numbers that best address the query from diverse, authoritative angles. Output ONLY the 3 selected numbers separated by commas (e.g. '1, 2, 3'). No explanations.",
										},
										{
											role = "user",
											content = string.format("User Query: %s\n\nCandidates:\n%s\n\nSelected 3 Numbers:", user_query, table.concat(candidate_prompts, "\n\n")),
										},
									},
									options = { num_predict = 1024, temperature = 0.1 },
									think = true,
									stream = false,
								})

								local sl_chunks = {}
								vim.fn.jobstart({ "curl", "-s", "-X", "POST", OLLAMA_HOST .. "/api/chat", "-d", shortlist_payload }, {
									stdout_buffered = true,
									on_stdout = function(_, data) if data then vim.list_extend(sl_chunks, data) end end,
									on_exit = function()
										local sl_raw = table.concat(sl_chunks, "")
										local ok_sl, res_sl = pcall(vim.fn.json_decode, sl_raw)
										local raw_content = (ok_sl and res_sl.message and res_sl.message.content) or ""
										local sl_text = strip_think(raw_content)

										local shortlisted_ids = {}
										for num in sl_text:gmatch("%d+") do
											local id = tonumber(num)
											if id and id >= 1 and id <= #merged_candidates then
												table.insert(shortlisted_ids, id)
											end
										end
										if #shortlisted_ids == 0 then shortlisted_ids = { 1, 2 } end
										while #shortlisted_ids > 3 do table.remove(shortlisted_ids) end

										vim.schedule(function()
											vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, {
												"# 🔍 Web Search: `" .. prompt .. "`",
												"",
												string.format("[4/5] Concurrently downloading shortlisted sources: `[%s]`...", table.concat(shortlisted_ids, ", ")),
											})
										end)

										-- 🔴 阶段 4：并发拉取这 3 个网页的真实全文
										local fetched_pages = {}
										local pages_done = 0
										local total_to_fetch = #shortlisted_ids

										for _, sid in ipairs(shortlisted_ids) do
											local s_item = merged_candidates[sid]
											fetch_page_content(s_item.url, function(p_content)
												fetched_pages[sid] = {
													item = s_item,
													full_text = p_content,
													preview = string.format("<candidate id=\"%d\" title=\"%s\" url=\"%s\">\n%s\n</candidate>", sid, s_item.title, s_item.url, p_content:sub(1, 2800)),
												}

												pages_done = pages_done + 1
												if pages_done == total_to_fetch then

													-- ==============================================================
													-- 🌟 路由分支 A：【Precision 精准模式】 (决赛圈PK选1篇 -> 单信源生成)
													-- ==============================================================
													if search_mode == "precision" then
														local tournament_previews = {}
														for _, pid in ipairs(shortlisted_ids) do
															if fetched_pages[pid] then table.insert(tournament_previews, fetched_pages[pid].preview) end
														end

														vim.schedule(function()
															vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, {
																"# 🔍 Web Search: `" .. prompt .. "`",
																"",
																"[5/5] [Precision Mode] Evaluating document substance to select the single primary reference...",
															})
														end)

														local finals_payload = vim.fn.json_encode({
															model = OLLAMA_MODEL,
															messages = {
																{
																	role = "system",
																	content = [[You are an objective document reranker. Evaluate candidate documents against the user query.
Evaluation Criteria:
1. Relevance: Directly addresses the core intent and specific context of the query.
2. Authority & Depth: Prioritize primary documentation, comprehensive guides, or in-depth technical analysis over shallow summaries or forum chatter.
3. Information Completeness: Contains substantive details to fully satisfy the request.
Output ONLY the single integer ID of the best candidate. No other text.]],
																},
																{
																	role = "user",
																	content = string.format("User Query: %s\n\nCandidate Previews:\n%s\n\nBest Source Number:", user_query, table.concat(tournament_previews, "\n\n")),
																},
															},
															options = { num_predict = 1024, temperature = 0.0 },
															think = true,
															stream = false,
														})

														local fin_chunks = {}
														vim.fn.jobstart({ "curl", "-s", "-X", "POST", OLLAMA_HOST .. "/api/chat", "-d", finals_payload }, {
															stdout_buffered = true,
															on_stdout = function(_, data) if data then vim.list_extend(fin_chunks, data) end end,
															on_exit = function()
																local fin_raw = table.concat(fin_chunks, "")
																local ok_fin, res_fin = pcall(vim.fn.json_decode, fin_raw)
																local raw_content = (ok_fin and res_fin.message and res_fin.message.content) or ""
																local fin_text = strip_think(raw_content)

																local champ_id = tonumber(fin_text:match("%d+")) or shortlisted_ids[1]
																if not fetched_pages[champ_id] then champ_id = shortlisted_ids[1] end
																local champion_page = fetched_pages[champ_id]

																vim.schedule(function()
																	local progress_view = { "# 🔍 Web Search: `" .. prompt .. "`", "" }
																	for _, l in ipairs(sources_header) do table.insert(progress_view, l) end
																	table.insert(progress_view, string.format("> 🎯 **[Precision] Selected Reference [%d]:** [%s](%s)", champ_id, champion_page.item.title, champion_page.item.url))
																	table.insert(progress_view, "")
																	table.insert(progress_view, "### 💡 Answer:")
																	table.insert(progress_view, "⏳ Synthesizing accurate answer from champion source...")
																	vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, progress_view)
																end)

																local answer_payload = vim.fn.json_encode({
																	model = OLLAMA_MODEL,
																	messages = {
																		{
																			role = "system",
																			content = [[You are an expert technical research assistant.
Guidelines:
1. Intent Alignment: Address the user's specific request directly. Adapt the style and depth accordingly.
2. Grounding & Accuracy: Base your findings strictly on the verified reference provided. Do not invent non-existent APIs, books, authors, or facts.
3. Information Density: Deliver structured, high-density explanations using clear headings and bullet points.
4. Citation & Anti-Hallucination:
   - Cite source facts using bracketed numbers (e.g. [1]).
   - ABSOLUTELY NEVER write your own markdown links or invent URLs (e.g. NEVER write [Text](http://...)).]],
																		},
																		{
																			role = "user",
																			content = string.format('User Request: %s\n\n<verified_reference source="%s">\n%s\n</verified_reference>', user_query, champion_page.item.url, champion_page.full_text:sub(1, 8000)),
																		},
																	},
																	options = { num_thread = 8, num_ctx = 16384 },
																	think = false,
																	stream = false,
																})
																local ans_chunks = {}
																vim.fn.jobstart({ "curl", "-s", "-X", "POST", OLLAMA_HOST .. "/api/chat", "-d", answer_payload }, {
																	stdout_buffered = true,
																	on_stdout = function(_, data) if data then vim.list_extend(ans_chunks, data) end end,
																	on_exit = function()
																		local ans_raw = table.concat(ans_chunks, "")
																		local ok_ans, res_ans = pcall(vim.fn.json_decode, ans_raw)
																		vim.schedule(function()
																			if ok_ans and res_ans.message and res_ans.message.content then
																				local answer = strip_think(res_ans.message.content)
																				local shortlisted_text = {}
																				for _, sid in ipairs(shortlisted_ids) do
																					local item = merged_candidates[sid]
																					if item then table.insert(shortlisted_text, string.format("`[%d]` %s", sid, item.title)) end
																				end
																				local full_view = { "# 🔍 Web Search: `" .. prompt .. "`", "" }
																				for _, l in ipairs(sources_header) do table.insert(full_view, l) end
																				table.insert(full_view, string.format("> 📋 **AI 3-Finalist Shortlist:** %s", table.concat(shortlisted_text, " | ")))
																				table.insert(full_view, string.format("> 🏆 **[Precision] Tournament Champion:** `[%d]` [%s](%s)", champ_id, champion_page.item.title, champion_page.item.url))
																				table.insert(full_view, "")
																				table.insert(full_view, "### 💡 Answer:")
																				for _, l in ipairs(vim.split(answer, "\n")) do table.insert(full_view, l) end
																				vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, full_view)
																				print("✓ Precision Search & Synthesis completed!")
																			else
																				vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, { "❌ Synthesis error:", ans_raw })
																			end
																		end)
																	end,
																})
															end,
														})

													-- ==============================================================
													-- 🌟 路由分支 B：【Synthesis 融合模式】 (跳过擂台赛 -> 3 篇文档混合生成)
													-- ==============================================================
													else
														vim.schedule(function()
															vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, {
																"# 🔍 Web Search: `" .. prompt .. "`",
																"",
																"[5/5] [Synthesis Mode] Fusing all 3 sources into a comprehensive landscape report...",
															})
														end)

														local combined_docs = {}
														local reading_list_text = {}
														for _, pid in ipairs(shortlisted_ids) do
															local doc_data = fetched_pages[pid]
															if doc_data then
																-- 融合模式每篇截取 3500 字，3 篇共 ~10000 字
																table.insert(combined_docs, string.format('<document id="%d" title="%s" url="%s">\n%s\n</document>', pid, doc_data.item.title, doc_data.item.url, doc_data.full_text:sub(1, 3500)))
																table.insert(reading_list_text, string.format("`[%d]` [%s](%s)", pid, doc_data.item.title, doc_data.item.url))
															end
														end

														local answer_payload = vim.fn.json_encode({
															model = OLLAMA_MODEL,
															messages = {
																{
																	role = "system",
																	content = [[You are an expert research analyst and software architect.
Guidelines:
1. Intent Alignment: Address the user's specific request directly. Adapt the style and depth accordingly (e.g. structured overviews, roadmaps, trade-off comparisons).
2. Multi-Document Synthesis: Integrate findings across ALL provided <document> references. Do not rely on just one if multiple provide valuable perspectives.
3. Grounding & Accuracy: Base your findings strictly on the verified documents provided. Do not extrapolate unsupported claims.
4. Information Density: Deliver structured, high-density explanations (headings, bullet points) with zero fluff.
5. Citation: Cite specific facts using their document IDs (e.g. [1], [2], [3]). Do not append a trailing URL reference section.]]
																},
																{
																	role = "user",
																	content = string.format("User Request: %s\n\n<verified_reference_documents>\n%s\n</verified_reference_documents>", user_query, table.concat(combined_docs, "\n\n"))
																}
															},
															options = { num_thread = 8, num_ctx = 16384 },
															think = false,
															stream = false
														})

														local ans_chunks = {}
														vim.fn.jobstart({ "curl", "-s", "-X", "POST", OLLAMA_HOST .. "/api/chat", "-d", answer_payload }, {
															stdout_buffered = true,
															on_stdout = function(_, data) if data then vim.list_extend(ans_chunks, data) end end,
															on_exit = function()
																local ans_raw = table.concat(ans_chunks, "")
																local ok_ans, res_ans = pcall(vim.fn.json_decode, ans_raw)
																vim.schedule(function()
																	if ok_ans and res_ans.message and res_ans.message.content then
																		local answer = strip_think(res_ans.message.content)
																		local full_view = { "# 🔍 Web Search: `" .. prompt .. "`", "" }
																		for _, l in ipairs(sources_header) do table.insert(full_view, l) end
																		table.insert(full_view, string.format("> 🌐 **[Synthesis] Multi-Document Fusion:**\n> %s", table.concat(reading_list_text, "\n> ")))
																		table.insert(full_view, "")
																		table.insert(full_view, "### 💡 Answer:")
																		for _, l in ipairs(vim.split(answer, "\n")) do table.insert(full_view, l) end
																		vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, full_view)
																		print("✓ Multi-source synthesis completed!")
																	else
																		vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, { "❌ Synthesis error:", ans_raw })
																	end
																end)
															end
														})
													end
												end
											end)
										end
									end,
								})
							end
						end)
					end
				end,
			})
		end)
	end


local M = {}
M.ai_search_action = ai_search_action
M.fetch_searxng_single = fetch_searxng_single
M.fetch_page_content = fetch_page_content

function M.setup()
	vim.keymap.set("n", "<leader>ais", function()
		ai_search_action(false)
	end, { desc = "AI: Web Search (Reranked)" })
	vim.keymap.set("v", "<leader>ais", function()
		ai_search_action(true)
	end, { desc = "AI: Web Search with Context" })
end

return M
