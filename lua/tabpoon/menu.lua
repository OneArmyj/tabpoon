local state = require("tabpoon.state")
local path = require("tabpoon.path")
local tabs = require("tabpoon.tabs")

local M = {}

local HEADER_LINES = 2
local menu_ns = vim.api.nvim_create_namespace("tabpoon_menu")

local function focus_window(win)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return false
	end

	local ok_tabpage, tabpage = pcall(vim.api.nvim_win_get_tabpage, win)
	if not ok_tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then
		return false
	end

	local ok = pcall(function()
		vim.api.nvim_set_current_tabpage(tabpage)
		vim.api.nvim_set_current_win(win)
	end)

	return ok
end

function M.close(opts)
	opts = opts or {}
	local menu = state.menu
	if not menu then
		return { closed = false }
	end

	state.menu = nil
	state.last_menu_source_win = menu.source_win

	if menu.win and vim.api.nvim_win_is_valid(menu.win) then
		pcall(vim.api.nvim_win_close, menu.win, true)
	end

	local restored = false
	if opts.restore_focus ~= false then
		restored = focus_window(menu.source_win)
	end

	return {
		closed = true,
		source_win = menu.source_win,
		restored = restored,
	}
end

local function menu_index()
	if not state.menu or not state.menu.win or not vim.api.nvim_win_is_valid(state.menu.win) then
		return nil
	end

	local row = vim.api.nvim_win_get_cursor(state.menu.win)[1]
	local index = row - HEADER_LINES
	if index < 1 or index > #state.items then
		return nil
	end

	return index
end

local function menu_lines()
	local lines = {
		" <CR> open   dd delete   K/J move   q close",
		"",
	}

	if #state.items == 0 then
		table.insert(lines, " No saved tabs")
		return lines
	end

	for index, item in ipairs(state.items) do
		local label = string.format(" %d  %-18s %s", index, path.filename(item.path), item.path)
		table.insert(lines, label)
	end

	return lines
end

local function refresh_menu(preferred_index)
	if not state.menu or not state.menu.buf or not vim.api.nvim_buf_is_valid(state.menu.buf) then
		return
	end

	vim.bo[state.menu.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.menu.buf, 0, -1, false, menu_lines())
	vim.api.nvim_buf_clear_namespace(state.menu.buf, menu_ns, 0, -1)

	local active_index = state.menu.source_win and tabs.bound_index_for_win(state.menu.source_win) or nil
	if active_index then
		vim.api.nvim_buf_add_highlight(state.menu.buf, menu_ns, "TabpoonMenuActive", active_index + HEADER_LINES - 1, 0, -1)
	end

	vim.bo[state.menu.buf].modifiable = false

	if state.menu.win and vim.api.nvim_win_is_valid(state.menu.win) then
		local index = preferred_index or menu_index() or 1
		local row = math.min(math.max(index + HEADER_LINES, HEADER_LINES + 1), math.max(#state.items + HEADER_LINES, HEADER_LINES + 1))
		pcall(vim.api.nvim_win_set_cursor, state.menu.win, { row, 0 })
	end
end

function M.refresh(preferred_index)
	refresh_menu(preferred_index)
end

function M.toggle()
	if state.menu and state.menu.win and vim.api.nvim_win_is_valid(state.menu.win) then
		M.close({ restore_focus = true })
		return
	end

	local source_win = vim.api.nvim_get_current_win()
	local max_width = math.max(vim.o.columns - 4, 20)
	local width = math.min(math.max(math.floor(vim.o.columns * 0.5), 20), max_width)
	local max_height = math.max(math.floor(vim.o.lines * 0.4), 6)
	local available_height = math.max(vim.o.lines - 6, 6)
	local height = math.min(math.max(#state.items + 3, 6), max_height, available_height)
	local row = math.floor((vim.o.lines - height) / 2) - 1
	local col = math.floor((vim.o.columns - width) / 2)
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = math.max(row, 0),
		col = math.max(col, 0),
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = { { " Tabpoon ", "TabpoonMenuTitle" } },
		title_pos = "center",
	})

	state.menu = { buf = buf, win = win, source_win = source_win }
	state.last_menu_source_win = source_win
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "tabpoon"
	refresh_menu(1)

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			local menu = state.menu
			if menu and menu.win == win then
				state.menu = nil
				vim.schedule(function()
					focus_window(menu.source_win)
				end)
			end
		end,
	})

	local function map(lhs, rhs)
		vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true })
	end

	map("q", function()
		M.close({ restore_focus = true })
	end)
	map("<Esc>", function()
		M.close({ restore_focus = true })
	end)
	map("<CR>", function()
		local index = menu_index()
		if index then
			M.close({ restore_focus = true })
			tabs.select(index)
		end
	end)
	map("dd", function()
		local index = menu_index()
		if index then
			tabs.delete_index(index)
			refresh_menu(math.min(index, #state.items))
		end
	end)
	map("J", function()
		local index = menu_index()
		if index then
			refresh_menu(tabs.move_index(index, 1) or index)
		end
	end)
	map("K", function()
		local index = menu_index()
		if index then
			refresh_menu(tabs.move_index(index, -1) or index)
		end
	end)
end

return M
