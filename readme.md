try to fix/complete the end for current context/position.

## design choices
* be pragmatic, no 100% correctness guarantee
* i know nothing about treesitter query, so every pattern is hardcoded
* no smart/automatic mechanism, must be triggered by user

## status
* it is not stable

## supported cases

lua: multiline blocks
* [x] do           -> do | end
* [x] for..        -> for..do | end
* [x] for..in..    -> for..do | end
* [x] if..         -> if..then | end
* [x] if..then     -> if..then | end
* [x] for..do      -> for..do | end

lua: inline pairs
* [x] '
* [x] "
* [x] (
* [x] [
* [x] {
* [x] [[

## prerequisites
* neovim 0.9.*
* haolian9/squirrel.nvim
* haolian9/infra.nvim

## usage
my personal config:
```
-- after/ftplugin/lua.vim
inoremap <buffer> <c-;> <cmd>lua require'fixends'()<cr>
```

## todo
* python
* zig

