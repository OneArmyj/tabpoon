local config = require("tabpoon.config")
local state = require("tabpoon.state")
local path = require("tabpoon.path")

local M = {}

local slot_icons = {
	"󰲠",
	"󰲢",
	"󰲤",
	"󰲦",
	"󰲨",
	"󰲪",
	"󰲬",
	"󰲮",
	"󰲰",
}

local function slot_icon(index)
	return slot_icons[index] or tostring(index)
end

function M.setup_highlights()
	local appearance = config.values.appearance
	vim.cmd("highlight default link " .. appearance.active .. " " .. appearance.active_link)
	vim.cmd("highlight default link " .. appearance.inactive .. " " .. appearance.inactive_link)
	vim.cmd("highlight default link " .. appearance.fill .. " " .. appearance.fill_link)

	local title_link = vim.fn.hlexists("TelescopePromptTitle") == 1 and "TelescopePromptTitle" or "Title"
	vim.cmd("highlight default link TabpoonMenuTitle " .. title_link)
	vim.cmd("highlight default link TabpoonMenuActive CursorLine")
end

function M.sync_visibility()
	local tabs = require("tabpoon.tabs")
	vim.o.showtabline = tabs.visible_tabpoon_count() > 1 and 2 or 0
end

function M.redraw()
	M.sync_visibility()
	vim.cmd("redrawtabline")
end

function M.render()
	local tabs = require("tabpoon.tabs")
	if tabs.visible_tabpoon_count() <= 1 then
		return ""
	end

	local appearance = config.values.appearance
	local parts = {}
	local current = vim.api.nvim_get_current_tabpage()
	local current_win = vim.api.nvim_get_current_win()

	local function add_tab(tabnr, label, active)
		label = label:gsub("%%", "%%%%")
		local group = active and appearance.active or appearance.inactive
		table.insert(parts, "%#" .. group .. "#%" .. tabnr .. "T " .. label)
	end

	local function add_tabpoon_tab(tabnr, icon, suffix, active)
		icon = icon:gsub("%%", "%%%%")
		suffix = suffix:gsub("%%", "%%%%")
		if active then
			table.insert(parts, "%#" .. appearance.inactive .. "#%" .. tabnr .. "T " .. "%#" .. appearance.active .. "#" .. icon .. "%#" .. appearance.inactive .. "#" .. suffix)
		else
			table.insert(parts, "%#" .. appearance.inactive .. "#%" .. tabnr .. "T " .. icon .. suffix)
		end
	end

	local function label_for_win(win, fallback)
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].filetype == "oil" then
			return "oil"
		end

		local name = vim.api.nvim_buf_get_name(buf)
		if name:match("^oil://") then
			return "oil"
		end

		return path.filename(name ~= "" and name or fallback)
	end

	-- Render bound Tabpoon windows from saved state first so menu reordering is
	-- reflected immediately and stale path matches cannot duplicate entries.
	for index, item in ipairs(state.items) do
		local win = tabs.window_for_item(item)
		if win and vim.api.nvim_win_is_valid(win) then
			add_tabpoon_tab(tabs.tabnr_for_win(win) or 1, slot_icon(index), " " .. label_for_win(win, path.item_abs_path(item)), win == current_win)
		end
	end

	local pending_index = #state.items
	for _, win in ipairs(tabs.pending_windows()) do
		pending_index = pending_index + 1
		add_tabpoon_tab(tabs.tabnr_for_win(win) or 1, slot_icon(pending_index), " [new]", win == current_win)
	end

	-- Non-Tabpoon tabpages are shown after the saved group and only by filename.
	for tabnr, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
		local has_tabpoon_window = false
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			if tabs.bound_item_for_win(win) or state.pending_wins[win] then
				has_tabpoon_window = true
				break
			end
		end

		if not has_tabpoon_window then
			local ok_win, win = pcall(vim.api.nvim_tabpage_get_win, tabpage)
			local label = ok_win and label_for_win(win, tabs.tab_file(tabpage)) or path.filename(tabs.tab_file(tabpage))
			add_tab(tabnr, label, tabpage == current)
		end
	end

	table.insert(parts, "%#" .. appearance.fill .. "#%T")
	return table.concat(parts)
end

return M
