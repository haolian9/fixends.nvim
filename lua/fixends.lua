--supported cases
--* -- multiline blocks
--* [x] do           -> do | end
--* [x] for..        -> for..do | end
--* [x] for..in..    -> for..do | end
--* [x] if..         -> if..then | end
--* [x] if..then     -> if..then | end
--* [x] for..do      -> for..do | end
--* [ ] function().. -> function()..|end
--* --inline pairs
--* [x] '
--* [x] "
--* [x] (
--* [x] [
--* [x] {
--* [x] [[

local jelly = require("infra.jellyfish")("squirrel.fixends", "info")
local prefer = require("infra.prefer")
local strlib = require("infra.strlib")

local nuts = require("squirrel.nuts")

local api = vim.api

---by search ascendingly
---@param start TSNode
local function find_nearest_error(start)
  ---@type TSNode?
  local node = start
  while true do
    if node == nil then return end
    local ntype = node:type()
    if ntype == "chunk" then return end
    if ntype == "ERROR" then return node end
    node = node:parent()
  end
end

---todo: duplicate code in squirrel.veil too
---@param bufnr number
---@param lnum number 0-based line number
---@return string,string,number
local function resolve_line_indent(bufnr, lnum)
  local nsp = api.nvim_buf_call(bufnr, function() return vim.fn.indent(lnum + 1) end)

  local bo = prefer.buf(bufnr)
  if bo.expandtab then
    local ts = bo.tabstop
    return string.rep(" ", nsp), " ", ts
  else
    local ts = bo.tabstop
    return string.rep("\t", nsp / ts), "\t", 1
  end
end

local try_erred_block
do
  ---@param winid integer
  ---@param bufnr integer
  ---@param start_node TSNode
  ---@param err_node TSNode
  ---@return boolean? @nil=false=failed
  function try_erred_block(winid, bufnr, start_node, err_node)
    local _ = start_node

    local start_chars = nuts.get_node_start_chars(bufnr, err_node, 3)
    local start_line, _, stop_line, stop_col = err_node:range()
    local indents, ichar, iunit = resolve_line_indent(bufnr, start_line)

    local fixes, cursor
    if strlib.startswith(start_chars, "if") then
      fixes = { " then", indents .. string.rep(ichar, iunit), indents .. "end" }
      if nuts.get_node_end_chars(bufnr, err_node, #fixes[1]) == fixes[1] then fixes[1] = "" end
      cursor = { start_line + 1 + 1, #fixes[2] }
    elseif strlib.startswith(start_chars, "do") then
      fixes = { "", indents .. string.rep(ichar, iunit), indents .. "end" }
      cursor = { start_line + 1 + 1, #fixes[2] }
    elseif strlib.startswith(start_chars, "for") then
      assert(err_node:child():type() == "for")
      fixes = { " do", indents .. string.rep(ichar, iunit), indents .. "end" }
      if nuts.get_node_end_chars(bufnr, err_node, #fixes[1]) == fixes[1] then fixes[1] = "" end
      cursor = { start_line + 1 + 1, #fixes[2] }
    end

    if fixes == nil then return jelly.debug("no available block found") end
    api.nvim_buf_set_text(bufnr, stop_line, stop_col, stop_line, stop_col, fixes)
    api.nvim_win_set_cursor(winid, cursor)
    return true
  end
end

local try_inline_pair, try_multiline_pair
do
  local inline_pairs = {
    { 1, { ['"'] = '"', ["'"] = "'", ["("] = ")", ["{"] = "}", ["["] = "]" } },
    { 2, { ["[["] = "]]" } },
  }

  local multiline_pairs = {
    { 2, { ["do"] = "end" } },
    { 4, { ["then"] = "end" } },
  }

  local function get_prompt(bufnr, cursor_line, cursor_col)
    if cursor_col == 0 then return jelly.debug("blank line") end
    local start_col = math.max(cursor_col - multiline_pairs[#multiline_pairs][1], 0)
    local text = api.nvim_buf_get_text(bufnr, cursor_line, start_col, cursor_line, cursor_col, {})
    return text[1]
  end

  ---@param store table
  ---@param prompt string
  ---@return string?
  local function find_fix(store, prompt)
    for i = #inline_pairs, 1, -1 do
      local len = store[i][1]
      local end_chars = string.sub(prompt, -len)
      if #end_chars == len then
        for a, b in pairs(store[i][2]) do
          if end_chars == a then return b end
        end
      end
    end
  end

  ---@param winid integer
  ---@param bufnr integer
  ---@return boolean? @nil=false=failed
  function try_inline_pair(winid, bufnr)
    local cursor_line, cursor_col = unpack(api.nvim_win_get_cursor(winid))
    cursor_line = cursor_line - 1

    local fix
    do
      local prompt = get_prompt(bufnr, cursor_line, cursor_col)

      fix = find_fix(inline_pairs, prompt)
      if fix == nil then return jelly.debug("no available pair found") end

      local follows = api.nvim_buf_get_text(bufnr, cursor_line, cursor_col, cursor_line, cursor_col + #fix, {})[1]
      if follows == fix then return jelly.debug("no need to add right side") end
    end

    api.nvim_buf_set_text(bufnr, cursor_line, cursor_col, cursor_line, cursor_col, { fix })
  end

  ---@param winid integer
  ---@param bufnr integer
  ---@return boolean? @nil=false=failed
  function try_multiline_pair(winid, bufnr)
    local cursor_line, cursor_col = unpack(api.nvim_win_get_cursor(winid))
    cursor_line = cursor_line - 1

    local fix
    do
      local prompt = get_prompt(bufnr, cursor_line, cursor_col)
      fix = find_fix(multiline_pairs, prompt)
      if fix == nil then return jelly.debug("no available pair found") end
    end

    local fixes
    do
      local indents, ichar, iunit = resolve_line_indent(bufnr, cursor_line)
      fixes = { "", indents .. string.rep(ichar, iunit), indents .. fix }
    end

    api.nvim_buf_set_text(bufnr, cursor_line, cursor_col, cursor_line, cursor_col, fixes)
    api.nvim_win_set_cursor(winid, { cursor_line + 1 + 1, #fixes[2] })
  end
end

return function()
  local winid = api.nvim_get_current_win()
  local bufnr = api.nvim_win_get_buf(winid)
  if prefer.bo(bufnr, "filetype") ~= "lua" then return jelly.warn("only support lua buffer right now") end

  local start_node = nuts.get_node_at_cursor(winid)
  local err_node = find_nearest_error(start_node)

  --try to fix ERROR node first
  if err_node ~= nil then
    if try_erred_block(winid, bufnr, start_node, err_node) then return end
  end

  if try_inline_pair(winid, bufnr) then return end
  if try_multiline_pair(winid, bufnr) then return end
end
