# tabpoon

A tab-oriented, Harpoon-style Neovim plugin for project-local file slots.

Tabpoon saves important files per workspace, opens them as Neovim tabs, keeps
managed tabs grouped in the tabline, and restores them the next time you open the
same project. It also provides a compact floating menu, Tabpoon-aware quit
behavior, and an LSP definition helper that opens definitions in the next
available Tabpoon slot.

## Features

- Workspace-local saved file slots.
- Automatic restore of saved tabs on startup.
- Compact custom tabline with numbered slot icons.
- Floating menu for selecting, deleting/closing, and reordering slots.
- One pending “new” tab that can be filled manually or with Telescope.
- Configurable maximum saved slots, capped at 9.
- `open_path()` helper: reuse existing slot, create next slot, or vertical split
  when full.
- `lsp_definition()` helper for `gd` mappings.
- Tabpoon-aware `:q`, `:quit`, `:q!`, and `:quit!` routing.
- Clear command that removes saved slots and closes live Tabpoon tabs/windows.
- Health check via `:checkhealth tabpoon`.

## Requirements

- Neovim 0.10 or newer.
- No required dependencies.

Optional:

- [`nvim-telescope/telescope.nvim`](https://github.com/nvim-telescope/telescope.nvim)
  for `create_tab({ find_files = true })`.
- A Nerd Font for the default slot icons.

## Installation

### lazy.nvim

```lua
{
  "OneArmyj/tabpoon",
  config = function()
    require("tabpoon").setup()
  end,
}
```

### Local development checkout

```lua
{
  "OneArmyj/tabpoon",
  dir = vim.fn.expand("~/coding/tabpoon"),
  config = function()
    require("tabpoon").setup()
  end,
}
```

## Configuration

Defaults:

```lua
require("tabpoon").setup({
  storage_dir = vim.fn.stdpath("data") .. "/tabpoon/workspaces",
  fallback_quit = nil,
  max_tabs = 9,
  appearance = {
    active = "TabpoonActive",
    inactive = "TabpoonInactive",
    fill = "TabpoonFill",
    active_link = "Special",
    inactive_link = "TabLine",
    fill_link = "TabLineFill",
  },
})
```

Options:

- `storage_dir`: directory for workspace JSON files.
- `fallback_quit`: command string or function used when Tabpoon delegates to
  normal quit behavior.
- `max_tabs`: maximum saved slots. Defaults to `9`; values must be integers from
  `1` to `9`.
- `appearance`: tabline highlight group names and default links.

Example:

```lua
require("tabpoon").setup({
  fallback_quit = "SmartQuit",
  max_tabs = 5,
})
```

## API

```lua
local tabpoon = require("tabpoon")

tabpoon.setup(opts)                  -- configure and start Tabpoon
tabpoon.remove()                     -- remove current file from saved slots
tabpoon.clear()                      -- clear saved slots and close live tabs
tabpoon.create_tab(opts)             -- create/focus one pending tab
tabpoon.has_capacity()               -- true when another saved slot is available
tabpoon.max_tabs()                   -- configured slot limit
tabpoon.open_path(path, opts)        -- open path in slot, or vsplit when full
tabpoon.lsp_definition(opts)         -- first LSP definition via open_path()
tabpoon.delete_current()             -- delete current Tabpoon tab/slot
tabpoon.select(index)                -- jump to saved slot
tabpoon.toggle_menu()                -- toggle floating menu
tabpoon.smart_quit()                 -- Tabpoon-aware quit helper
tabpoon.tabline()                    -- tabline renderer
```

`open_path(path, opts)` accepts optional `opts.row` and `opts.col` to restore the
cursor at a target location. It returns `(ok, mode)`, where `mode` is one of
`"existing"`, `"tabpoon"`, `"split"`, `"missing"`, or `"open_failed"`.

## Suggested keymaps

```lua
local tabpoon = require("tabpoon")

vim.keymap.set("n", "<leader>hr", tabpoon.remove, { desc = "Tabpoon: Remove current file" })
vim.keymap.set("n", "<leader>hc", function()
  tabpoon.create_tab({ find_files = true })
end, { desc = "Tabpoon: Create/find new tab" })
vim.keymap.set("n", "<leader>hC", tabpoon.clear, { desc = "Tabpoon: Clear/close saved tabs" })
vim.keymap.set("n", "<leader>hx", tabpoon.delete_current, { desc = "Tabpoon: Delete current tab" })
vim.keymap.set("n", "<leader>hh", tabpoon.toggle_menu, { desc = "Tabpoon: Toggle menu" })
vim.keymap.set("n", "<leader>q", tabpoon.smart_quit, { desc = "Tabpoon: Smart quit" })

for i = 1, 5 do
  vim.keymap.set("n", "<leader>" .. i, function()
    tabpoon.select(i)
  end, { desc = "Tabpoon: Select " .. i })
end
```

LSP definition integration:

```lua
vim.keymap.set("n", "gd", function()
  require("tabpoon").lsp_definition()
end, { desc = "LSP definition in Tabpoon" })
```

## Menu controls

Inside `tabpoon.toggle_menu()`:

- `<CR>`: open selected slot.
- `dd`: delete selected slot and close its live tab/window.
- `K`: move selected slot up.
- `J`: move selected slot down.
- `q` / `<Esc>`: close the menu.

## Commands

- `:TabpoonQuit[!]`: close the Tabpoon group from a Tabpoon-owned window;
  outside Tabpoon, fall back to normal quit behavior.

Tabpoon also installs exact command-line abbreviations so `:q`, `:quit`, `:q!`,
and `:quit!` route through `:TabpoonQuit`.

## Storage

Tabpoon stores one JSON file per workspace under:

```text
stdpath("data")/tabpoon/workspaces/<workspace-hash>.json
```

The workspace hash is `sha256(cwd)`, where `cwd` is the current working directory
when Neovim starts. Paths inside the workspace are saved relative to the
workspace root; external paths are saved as absolute paths.

## Tests

Run from the repository root:

```sh
nvim --headless --clean \
  --cmd "set rtp+=." \
  +"luafile tests/run.lua" \
  +"qa!"
```

## Health

```vim
:checkhealth tabpoon
```

The health check validates the Neovim version, storage writability, and optional
Telescope availability.

## License

MIT. See [`LICENSE`](LICENSE).
