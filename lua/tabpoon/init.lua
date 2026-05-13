local config = require("tabpoon.config")
local state = require("tabpoon.state")
local path = require("tabpoon.path")
local storage = require("tabpoon.storage")
local tabs = require("tabpoon.tabs")
local menu = require("tabpoon.menu")
local tabline = require("tabpoon.tabline")
local commands = require("tabpoon.commands")
local lsp = require("tabpoon.lsp")

local M = {}

function M.setup(opts)
	config.setup(opts)
	state.root = path.resolve_root()
	state.store_path = path.join(config.values.storage_dir, vim.fn.sha256(state.root) .. ".json")

	vim.fn.mkdir(config.values.storage_dir, "p")
	storage.load()

	tabline.setup_highlights()
	tabline.sync_visibility()
	vim.o.tabline = "%!v:lua.require'tabpoon'.tabline()"

	commands.setup()
end

function M.remove()
	tabs.remove_current()
	menu.refresh()
end

function M.clear()
	local ok = tabs.clear()
	if ok ~= false then
		menu.refresh(1)
	end
	return ok
end

function M.create_tab(opts)
	tabs.create_pending_tab(opts)
end

function M.has_capacity()
	return tabs.has_capacity()
end

function M.max_tabs()
	return tabs.max_tabs()
end

function M.open_path(file_path, opts)
	return tabs.open_path(file_path, opts)
end

function M.lsp_definition(opts)
	return lsp.definition(opts)
end

function M.delete_current()
	tabs.delete_current()
	menu.refresh()
end

function M.select(index)
	tabs.select(index)
end

function M.toggle_menu()
	menu.toggle()
end

function M.tabline()
	return tabline.render()
end

function M.smart_quit()
	tabs.smart_quit()
end

function M._test_bound_index()
	return tabs.bound_index_for_win(vim.api.nvim_get_current_win())
end

return M
