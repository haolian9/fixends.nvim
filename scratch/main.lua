--supported cases
--* [x] 'hello           -> 'hello|'
--* [x] local x = 'hello -> 'hello|'
--* [ ] 'hello'          -> local _ = 'hello|'
--* [x] s .. '           -> s..'|'
--* [x] local x = s .. ' -> local x = s..'|'
--* [x] do               -> do | end
--* [ ] for...do         -> for...do | end
--* [ ] print(           -> print(|)
--* [ ] local x ={       -> ={|}
--* [ ] t[               -> t[|]
local jelly = require("infra.jellyfish")("fixends", "debug")
local prefer = require("infra.prefer")

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

---get the first char from the first line of a node
---@param bufnr integer
---@param node TSNode
---@return string
local function get_node_first_char(bufnr, node)
  local start_line, start_col = node:range()
  local text = api.nvim_buf_get_text(bufnr, start_line, start_col, start_line, start_col + 1, {})
  assert(#text == 1)
  local char = text[1]
  assert(#char == 1)
  return char
end

---get <=n chars from the first line of a node
---@param bufnr integer
---@param node TSNode
---@param n integer
---@return string
local function get_node_start_chars(bufnr, node, n)
  local start_line, start_col, stop_line, stop_col = node:range()
  local corrected_stop_col
  if start_line == stop_line then
    corrected_stop_col = math.min(start_col + n, stop_col)
  else
    corrected_stop_col = start_col + n
  end
  local text = api.nvim_buf_get_text(bufnr, start_line, start_col, start_line, corrected_stop_col, {})
  assert(#text == 1)
  return text[1]
end

---get <=n chars from the last line of a node
---@param bufnr integer
---@param node TSNode
---@param n integer
---@return string
local function get_node_end_chars(bufnr, node, n)
  local start_line, start_col, stop_line, stop_col = node:range()
  local corrected_start_col
  if start_line == stop_line then
    corrected_start_col = math.max(stop_col - n, start_col)
  else
    corrected_start_col = math.max(stop_col - n, 0)
  end
  local text = api.nvim_buf_get_text(bufnr, stop_line, corrected_start_col, stop_line, stop_col, {})
  assert(#text == 1)
  return text[1]
end

local try_erred_str, try_str
do
  local str_pairs = {
    ['"'] = '"',
    ["'"] = "'",
    ["[["] = "]]",
  }

  ---@param bufnr integer
  ---@param start_node TSNode
  ---@param err_node TSNode
  ---@return true|nil
  function try_erred_str(bufnr, start_node, err_node)
    -- if start_node:type() ~= "identifier" then return jelly.debug("not a broken str node: feature unmatch") end

    local end_chars
    do
      local first_char = get_node_first_char(bufnr, err_node)
      end_chars = str_pairs[first_char]
      --todo: ensure not endswith ]]
      if end_chars == nil then return jelly.debug("not a broken str node: quote=%s", first_char) end
    end

    local _, _, stop_line, stop_col = err_node:range()
    api.nvim_buf_set_text(bufnr, stop_line, stop_col, stop_line, stop_col, { end_chars })

    return true
  end

  ---@param bufnr integer
  ---@param start_node TSNode
  ---@return true?
  function try_str(bufnr, start_node)
    if start_node:type() ~= "string" then return jelly.debug("not a str node") end

    local start_line, start_col, stop_line, stop_col = start_node:range()

    local end_chars
    do
      local first_char = get_node_first_char(bufnr, start_node)
      local expected = str_pairs[first_char]
      if not (start_line == stop_line and start_col + #expected == stop_col) then
        local held = get_node_end_chars(bufnr, start_node, #expected)
        if held == expected then return jelly.debug("already a complete str node") end
      end
      end_chars = expected
    end

    api.nvim_buf_set_text(bufnr, stop_line, stop_col, stop_line, stop_col, { end_chars })
    return true
  end
end

---@param bufnr integer
---@param start_node TSNode
---@return true?
local function try_erred_block(bufnr, start_node, err_node)
  -- if start_node:type() ~= "ERROR" then return jelly.debug("not a block node: feature unmatch") end
  if get_node_start_chars(bufnr, err_node, 2) ~= "do" then return jelly.debug("not a block node: keyword missing") end

  local _, _, stop_line, stop_col = err_node:range()
  --todo: keep cursor no moving
  --todo: respect indent
  api.nvim_buf_set_text(bufnr, stop_line, stop_col, stop_line, stop_col, { " end" })

  return true
end

local function main()
  local winid = api.nvim_get_current_win()
  local bufnr = api.nvim_win_get_buf(winid)
  if prefer.bo(bufnr, "filetype") ~= "lua" then return jelly.warn("only support lua buffer right now") end

  local start_node = nuts.get_node_at_cursor(winid)

  do -- fix error
    local err_node = find_nearest_error(start_node)
    if err_node ~= nil then
      local done = try_erred_str(bufnr, start_node, err_node) or try_erred_block(bufnr, start_node, err_node)
      if done then return end
    else
      jelly.debug("no ERROR node around")
    end
  end

  do -- no error
    local done = try_str(bufnr, start_node) ~= nil
    if done then return end
  end
end

main()
