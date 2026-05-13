# Tabpoon Tests

These are plain Lua headless regression tests for Tabpoon. They do not require a test framework.

Run from the plugin repository root (`~/coding/tabpoon`):

```sh
nvim --headless --clean \
  --cmd "set rtp+=." \
  +"luafile tests/run.lua" \
  +"qa!"
```

Or run with an absolute runtime path:

```sh
nvim --headless --clean \
  --cmd "set rtp+=/home/yjchen/coding/tabpoon" \
  +"luafile /home/yjchen/coding/tabpoon/tests/run.lua" \
  +"qa!"
```

The test runner creates temporary fixtures under `/tmp/opencode/tabpoon-tests` and isolated Tabpoon state under `/tmp/opencode/tabpoon-tests-state`.

The suite covers startup restore, pending tabs, menu deletion/reordering, max-tab behavior, LSP target helpers, clear/close behavior, group quit with non-Tabpoon tabs, open Tabpoon menus, and floating windows on Tabpoon tabs.
