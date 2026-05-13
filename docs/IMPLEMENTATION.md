# Tabpoon Implementation

This document records the current Tabpoon specification and how the local plugin implements it.

## Specification

- Saved files are represented as persistent Neovim tabs.
- Saved Tabpoon slots are limited by `max_tabs`, which defaults to `9` and is capped at `9`.
- State is stored per workspace.
- A workspace is the current working directory where Neovim was started.
- Saved paths are relative to the workspace root when possible.
- Files outside the workspace are stored as absolute paths.
- Cursor `row` and `col` are saved for each item.
- Restored Tabpoon views are centered vertically around the saved cursor.
- On startup, saved tabs are recreated and Tabpoon item `1` is selected.
- If no saved state exists, the first valid file buffer becomes Tabpoon item `1`.
- Tabpoon tabs appear before non-Tabpoon tabs in the tabline.
- Tabpoon tab labels render as `<slot-icon> <filename>`.
- The active Tabpoon label highlights only the slot icon.
- Non-Tabpoon tabs render after Tabpoon tabs and show filename only.
- Oil buffers render as `oil` in the tabline.
- The tabline is hidden when there are fewer than two live Tabpoon tabs.
- The floating menu supports opening, deleting/closing, and reordering items.
- Reordering in the menu immediately updates saved state, actual tab order, and tabline order.
- `clear()` removes saved items and closes their live Tabpoon tabs/windows while preserving non-Tabpoon tabs and splits.
- Open Tabpoon items are bound to Neovim windows at runtime.
- Changing the buffer in a Tabpoon-owned window is committed on Tabpoon tab switch, Vim leave, or Tabpoon quit.
- One empty pending tab can be created or focused while under `max_tabs`, optionally opens Telescope Find Files, and becomes a saved Tabpoon item once it opens a valid file or closes when abandoned.
- `open_path()` opens existing saved paths in their slot, creates a new saved slot while under capacity, and opens a vertical split when full.
- `lsp_definition()` requests the first LSP definition target and delegates to `open_path()` so `gd` integration stays inside Tabpoon.
- Opening a file already owned by another Tabpoon slot jumps to that existing slot instead of duplicating the path.
- `:q`, `:quit`, `:q!`, and `:quit!` from a Tabpoon-owned window close the Tabpoon group, not unrelated windows.
- `<leader>q` calls `tabpoon.smart_quit()`, which uses Tabpoon group quit from owned windows and `SmartQuit` elsewhere.
- Modified Tabpoon buffers require save/discard/cancel handling before group quit proceeds.
- Floating windows are ignored when deciding whether group quit must preserve non-Tabpoon windows.

## Module Layout

```text
lua/tabpoon/init.lua
lua/tabpoon/config.lua
lua/tabpoon/state.lua
lua/tabpoon/path.lua
lua/tabpoon/storage.lua
lua/tabpoon/tabs.lua
lua/tabpoon/menu.lua
lua/tabpoon/tabline.lua
lua/tabpoon/commands.lua
lua/tabpoon/health.lua
```

`init.lua` exposes the public API and wires setup together.

`config.lua` owns defaults and user options, including storage directory, fallback quit behavior, max saved slots, and highlight group names. Setup validates option types and rebuilds configuration from immutable defaults each time so repeated setup calls are predictable.

`state.lua` owns runtime state. Runtime-only data such as tab numbers, windows, and ownership bindings is not persisted because Neovim assigns those per session.

`path.lua` owns path normalization, cwd workspace resolution, filename formatting, relative-path conversion, and item lookup.

`storage.lua` loads and writes JSON workspace state. It de-duplicates saved paths on load to recover from stale duplicate entries. Writes go through a temporary file and rename so interrupted writes are less likely to corrupt the active state file.

`tabs.lua` owns tab operations, cursor persistence, startup restoration, selection, reordering, and logical group quit.

`menu.lua` owns the floating menu and its local keymaps.

`tabline.lua` owns highlight setup, tabline visibility, and tabline rendering.

`commands.lua` owns autocmd registration, the `:TabpoonQuit` command, and exact command-line abbreviations for quit commands.

`health.lua` implements `:checkhealth tabpoon` checks for Neovim version compatibility, storage writability, and optional Telescope integration.

## Persistent State

State is stored under:

```text
~/.local/share/nvim/tabpoon/workspaces/<workspace-hash>.json
```

The hash is `sha256(cwd)`, where `cwd` is the current working directory where Neovim was started.

Example:

```json
{
  "version": 1,
  "root": "/home/yjchen/.dotfiles",
  "items": [
    {
      "path": "roles/neovim/files/lua/tickingcode/keymaps.lua",
      "row": 42,
      "col": 7
    }
  ]
}
```

Tab numbers are not stored. They are runtime details and are reconstructed by opening saved files in saved-list order.

## Window Ownership

Tabpoon does not treat a path alone as proof that a tab is managed. Instead, each open Tabpoon item is bound to a specific Neovim window in `state.item_by_win`.

This fixes stale ownership cases while keeping normal browsing safe. If a Tabpoon-owned window changes from `a.lua` to `b.lua`, the saved item is not replaced immediately. It is committed on Tabpoon tab switch, `VimLeavePre`, or Tabpoon quit. If an unrelated split changes buffers, Tabpoon ignores it.

If `b.lua` already belongs to another Tabpoon item, `BufEnter` restores the current window to its saved file and jumps to the existing owner. Non-interactive commit paths skip duplicate-path commits.

`state.pending_wins` tracks empty tabs created by the Tabpoon create-tab command. A pending window is not persisted, but it appears in the Tabpoon tabline as `<slot-icon> [new]` while live. `create_pending_tab()` focuses the first live pending window instead of creating another empty pending tab. With `{ find_files = true }`, it opens Telescope Find Files in that pending tab. Once a pending tab opens a new valid file buffer, it is appended to `state.items` and bound as the next compact slot. If the selected or opened file is already saved in another Tabpoon slot, Tabpoon closes the pending tab and jumps to the existing slot instead of duplicating the path. If Telescope closes without selecting a file, or selection leaves a pending tab before it opens a valid file, Tabpoon closes the abandoned pending tab and removes it from `state.pending_wins`.

Bindings are cleared by `clear()` and are never written to disk. Existing tabs/windows remain open after `clear()`, but they become normal Neovim windows.

## Startup Flow

`setup()` resolves the workspace root from the current working directory, computes the workspace state path, loads JSON, installs highlights, configures the tabline, and registers commands/autocmds.

On `VimEnter`, `tabs.restore_tabs()` recreates saved tabs. Missing files are skipped and pruned from state. After all tabs are restored and reordered, Tabpoon explicitly selects item `1` so reopening a workspace always starts at the first saved tab. If no saved items exist, `tabs.ensure_first_slot()` saves the first valid current file as item `1`.

## Tabline Flow

The tabline is state-driven and ownership-aware. It renders bound Tabpoon windows in `state.items` order instead of trusting Neovim's current physical tab order or matching by path alone. This makes menu reordering visible immediately and avoids duplicate displayed entries after clearing and re-adding.

Rendered saved and pending Tabpoon labels use circled slot glyphs with one space before the text, such as `󰲠 init.lua` and `󰲢 [new]`. Numeric selection APIs and keymaps still use normal indexes; the glyphs are display-only. Highlighted padding is placed on the left side of each label. Active Tabpoon entries apply the active highlight only to the slot glyph; the left padding and suffix stay inactive.

After Tabpoon entries are rendered, non-Tabpoon tabs are appended by walking actual Neovim tabpages and skipping files already represented by Tabpoon.

Visibility is synced from live Tabpoon windows plus pending windows: zero or one visible Tabpoon tab means `showtabline = 0`; two or more visible Tabpoon tabs means `showtabline = 2`.

## Cursor Persistence

Cursor position and the current valid file path are committed on `TabLeave`, `VimLeavePre`, Tabpoon selection, and Tabpoon quit. Positions are written to the workspace JSON so crashes or restarts do not lose the latest known location.

Opening or selecting a Tabpoon item restores the saved cursor and runs `zz` so restored views are vertically centered.

Normal Tabpoon selection does not reorder physical tabpages. Reordering temporarily focuses each Tabpoon tab, which causes visible active-icon flicker during navigation. Physical reordering is reserved for startup restoration, deletion, and explicit menu reordering.

## Menu Reordering

The menu is a controlled floating buffer. Users do not edit text directly. Instead:

- `<CR>` opens the selected item.
- `dd` deletes the selected item and closes its live tab/window when present.
- `J` moves the selected item down.
- `K` moves the selected item up.

Every mutation updates `state.items`, writes JSON, reorders actual tabs, and redraws the tabline.

The menu records the source window before opening its floating window. Closing the menu through `q`, `<Esc>`, toggle, or external window close restores focus to that source window when it is still valid. This keeps follow-up commands such as `<leader>q` running from the original Tabpoon-owned window instead of the transient menu window.

## Quit Flow

Neovim built-in lowercase commands such as `:quit` cannot be safely replaced with user commands. Tabpoon uses exact command-line abbreviations for quit commands:

```vim
:q
:quit
:q!
:quit!
```

The abbreviations replace `:q` and `:quit` with `:TabpoonQuit`. Bang forms expand to `:TabpoonQuit!`, and the command accepts `!` so non-Tabpoon fallback preserves normal `:q!` behavior. `TabpoonQuit` repairs runtime ownership if possible and decides whether to run Tabpoon group quit or fall back to normal `:quit`.

Before collecting windows, `TabpoonQuit` repairs bindings by matching visible windows back to saved Tabpoon item paths when those items have no live owner. This prevents stale runtime ownership from causing `:q` to close one tab at a time.

`TabpoonQuit` treats multiple Tabpoon-owned windows/tabs as one logical group. If there is only one live Tabpoon tab, it commits that tab's latest valid file and delegates to `SmartQuit`. For multiple live Tabpoon tabs, it collects every normal window in `state.item_by_win` before closing anything. If a Tabpoon tabpage also contains non-Tabpoon splits, only the Tabpoon-owned windows are closed and the non-Tabpoon splits remain.

Floating windows are skipped while collecting the quit plan. They are transient UI, not tab ownership, so a popup on a Tabpoon tab must not make Tabpoon preserve that tab as if it contained a real non-Tabpoon split.

Before closing, modified Tabpoon buffers are handled one by one. Tabpoon jumps to the modified window first, then asks Save / Discard / Cancel. Save writes the buffer, Discard clears the `modified` flag, and Cancel aborts the entire quit operation.

If no non-Tabpoon windows exist, Tabpoon asks for final quit confirmation and then runs `:quitall` after modified Tabpoon buffers are handled. If non-Tabpoon windows exist, only the Tabpoon group is closed in one command invocation.

`tabpoon.smart_quit()` is the keymap-friendly entry point. It closes any open Tabpoon menu first, restoring source focus, then dispatches to Tabpoon group quit when the current window belongs to Tabpoon. Otherwise it calls the existing `SmartQuit` command.

## Appearance

Appearance is configured through highlight groups:

```lua
require("tabpoon").setup({
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

By default, these custom groups link to existing Neovim groups. `TabpoonActive` links to `Special` so the active icon uses a foreground accent. Users can override them with `vim.api.nvim_set_hl`.

## Plugin Layout

Tabpoon is laid out as a standalone Neovim plugin. `lua/tabpoon/init.lua` is the plugin entry point expected by plugin managers such as `lazy.nvim`, `doc/tabpoon.txt` is the Vim help file, and tests live outside the runtime Lua package.

## Tests

Reusable plain Lua headless tests live under:

```text
tests/
```

Run them from the plugin root:

```sh
nvim --headless --clean \
  --cmd "set rtp+=." \
  +"luafile tests/run.lua" \
  +"qa!"
```
