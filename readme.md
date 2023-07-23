
**archived: having this for weeks, i have never used it once. it's useless to me.**

an example that tries to fix/complete the end for current context/position.


## design choices
* be pragmatic, guarantee no 100% correctness
* every pattern is hardcoded, as i know nothing about queries of treesitter
* be stupid and lazy, it must be triggered by user
* treesitter parsers are good, avoid string manipulations ASAP

## status
* it is not stable
* its implementation is ugly

## supported cases

lua: multiline blocks
* [x] do           -> do | end
* [x] for..        -> for..do | end
* [x] for..in..    -> for..do | end
* [x] if..         -> if..then | end
* [x] if..then     -> if..then | end
* [x] for..do      -> for..do | end

general: inline pairs
* [x] '
* [x] "
* [x] (
* [x] [
* [x] {
* [x] [[

## prerequisites
* neovim 0.9.* with treesitter
* haolian9/squirrel.nvim
* haolian9/infra.nvim

## usage
my personal config:
```
-- after/ftplugin/lua.vim
inoremap <buffer> <c-;> <cmd>lua require'fixends'.lua()<cr>
```

## todo
* python
* zig

