local state = require("tabpoon.state")
local config = require("tabpoon.config")
local path = require("tabpoon.path")
local storage = require("tabpoon.storage")

local M = {}

local function redraw_tabline()
  require("tabpoon.tabline").redraw()
end

local restore_cursor
local restore_view

local function item_index(item)
  for index, candidate in ipairs(state.items) do
    if candidate == item then
      return index
    end
  end

  return nil
end

local function cleanup_bindings()
	for win, item in pairs(state.item_by_win) do
		if not vim.api.nvim_win_is_valid(win) or not item_index(item) then
			state.item_by_win[win] = nil
		end
	end

	for win in pairs(state.pending_wins) do
		if not vim.api.nvim_win_is_valid(win) then
			state.pending_wins[win] = nil
		end
	end
end

local function win_tabpage(win)
  local ok, tabpage = pcall(vim.api.nvim_win_get_tabpage, win)
  return ok and tabpage or nil
end

local function is_normal_window(win)
	local ok, config = pcall(vim.api.nvim_win_get_config, win)
	return ok and config.relative == ""
end

function M.tabnr_for_win(win)
  local target = win_tabpage(win)
  if not target then
    return nil
  end

  for tabnr, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    if tabpage == target then
      return tabnr
    end
  end

  return nil
end

function M.bound_item_for_win(win)
  cleanup_bindings()
  return state.item_by_win[win or vim.api.nvim_get_current_win()]
end

function M.bound_index_for_win(win)
  return item_index(M.bound_item_for_win(win))
end

local function window_for_item(item)
  for win, bound_item in pairs(state.item_by_win) do
    if bound_item == item then
      return win
    end
  end

  return nil
end

function M.window_for_item(item)
  cleanup_bindings()
  return window_for_item(item)
end

function M.has_live_tabpoon_window()
	cleanup_bindings()
	for win in pairs(state.item_by_win) do
		if vim.api.nvim_win_is_valid(win) then
			return true
		end
	end

	return false
end

function M.live_tabpoon_count()
	cleanup_bindings()
	local count = 0
	for win in pairs(state.item_by_win) do
		if vim.api.nvim_win_is_valid(win) then
			count = count + 1
		end
	end

	return count
end

function M.live_pending_count()
	cleanup_bindings()
	local count = 0
	for win in pairs(state.pending_wins) do
		if vim.api.nvim_win_is_valid(win) then
			count = count + 1
		end
	end

	return count
end

function M.visible_tabpoon_count()
	cleanup_bindings()
	local count = 0
	for win in pairs(state.item_by_win) do
		if vim.api.nvim_win_is_valid(win) then
			count = count + 1
		end
	end
	for win in pairs(state.pending_wins) do
		if vim.api.nvim_win_is_valid(win) then
			count = count + 1
		end
	end

	return count
end

function M.max_tabs()
	return config.values.max_tabs
end

function M.has_capacity()
	return #state.items < config.values.max_tabs
end

function M.is_full()
	return not M.has_capacity()
end

function M.pending_windows()
	cleanup_bindings()
	local wins = {}
	for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			if state.pending_wins[win] then
				table.insert(wins, win)
			end
		end
	end

	return wins
end

function M.bind_window_to_item(win, index)
  local item = state.items[index]
  if not item or not vim.api.nvim_win_is_valid(win) then
    return
  end

  -- Each saved item owns at most one live window. Rebinding avoids stale owners.
  for bound_win, bound_item in pairs(state.item_by_win) do
    if bound_item == item and bound_win ~= win then
      state.item_by_win[bound_win] = nil
    end
  end

  state.item_by_win[win] = item
end

local function unbind_item(item)
  for win, bound_item in pairs(state.item_by_win) do
    if bound_item == item then
      state.item_by_win[win] = nil
    end
  end
end

local function normal_windows_in_tabpage(tabpage)
	local wins = {}
	if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then
		return wins
	end

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		if is_normal_window(win) then
			table.insert(wins, win)
		end
	end

	return wins
end

local function normal_window_count()
	local count = 0
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if is_normal_window(win) then
			count = count + 1
		end
	end

	return count
end

local function clear_bindings()
	state.item_by_win = {}
	state.pending_wins = {}
end

local function win_abs_path(win)
	local ok_buf, buf = pcall(vim.api.nvim_win_get_buf, win)
	if not ok_buf then
		return nil
	end

	local name = vim.api.nvim_buf_get_name(buf)
	return name ~= "" and path.normalize(name) or nil
end

local function file_item_for_win(win, notify)
	local ok_buf, buf = pcall(vim.api.nvim_win_get_buf, win)
	if not ok_buf then
		return nil
	end

	if vim.bo[buf].buftype ~= "" then
		if notify then
			vim.notify("Tabpoon: current buffer is not a file", vim.log.levels.WARN)
		end
		return nil
	end

	local name = vim.api.nvim_buf_get_name(buf)
	local abs_path = name ~= "" and path.normalize(name) or nil
	if not abs_path then
		if notify then
			vim.notify("Tabpoon: current buffer has no file", vim.log.levels.WARN)
		end
		return nil
	end

	local item = path.item_from_abs_path(abs_path)
	local cursor = vim.api.nvim_win_get_cursor(win)
	item.row = cursor[1]
	item.col = cursor[2]
	return item
end

local function current_file_item(notify)
	return file_item_for_win(vim.api.nvim_get_current_win(), notify)
end

local function append_current_file(win, notify)
	local item = current_file_item(notify)
	if not item then
		return nil
	end

	if not M.has_capacity() then
		if notify then
			vim.notify("Tabpoon: maximum saved tabs reached", vim.log.levels.WARN)
		end
		return nil
	end

	table.insert(state.items, item)
	M.bind_window_to_item(win or vim.api.nvim_get_current_win(), #state.items)
	state.pending_wins[win or vim.api.nvim_get_current_win()] = nil
	storage.write()
	redraw_tabline()
	return #state.items
end

local function close_pending_win(win)
	cleanup_bindings()
	if not state.pending_wins[win] then
		return false, false
	end

	state.pending_wins[win] = nil

	local tabpage = win_tabpage(win)
	local close_tab = tabpage and vim.api.nvim_tabpage_is_valid(tabpage) and #vim.api.nvim_tabpage_list_wins(tabpage) == 1 and #vim.api.nvim_list_tabpages() > 1
	local ok = true

	if close_tab then
		vim.api.nvim_set_current_tabpage(tabpage)
		ok = pcall(vim.cmd, "silent tabclose")
	elseif vim.api.nvim_win_is_valid(win) and #vim.api.nvim_list_wins() > 1 then
		ok = pcall(vim.api.nvim_win_close, win, false)
	elseif vim.api.nvim_win_is_valid(win) then
		ok = pcall(vim.cmd, "enew")
	end

	if not ok then
		state.pending_wins[win] = true
		vim.notify("Tabpoon: pending tab has unsaved changes", vim.log.levels.WARN)
		redraw_tabline()
		return false, true
	end

	redraw_tabline()
	return true, false
end

local function close_abandoned_pending_win(win)
	if file_item_for_win(win, false) then
		return false, false
	end

	return close_pending_win(win)
end

local function all_windows()
	local wins = {}
	for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			table.insert(wins, win)
		end
	end

	return wins
end

local function repair_bindings()
	cleanup_bindings()

	local current_win = vim.api.nvim_get_current_win()
	local current_path = win_abs_path(current_win)
	local current_index = current_path and path.find_item_index(current_path) or nil
	if current_index then
		M.bind_window_to_item(current_win, current_index)
	end

	local windows = all_windows()
	for index, item in ipairs(state.items) do
		if not window_for_item(item) then
			local item_path = path.item_abs_path(item)
			for _, win in ipairs(windows) do
				if not state.item_by_win[win] and win_abs_path(win) == item_path then
					M.bind_window_to_item(win, index)
					break
				end
			end
		end
	end
end

local function find_other_item_index(abs_path, current_item)
	for index, item in ipairs(state.items) do
		if item ~= current_item and path.item_abs_path(item) == abs_path then
			return index
		end
	end

	return nil
end

local function restore_window_to_item(win, item)
	local abs_path = path.item_abs_path(item)
	if vim.fn.filereadable(abs_path) ~= 1 then
		return
	end

	state.suppress_buf_enter = true
	local ok = pcall(function()
		local tabpage = win_tabpage(win)
		if tabpage and vim.api.nvim_tabpage_is_valid(tabpage) then
			vim.api.nvim_set_current_tabpage(tabpage)
			vim.api.nvim_set_current_win(win)
		end
		vim.cmd("edit " .. vim.fn.fnameescape(abs_path))
		restore_view(item)
	end)
	state.suppress_buf_enter = false

	if not ok then
		vim.notify("Tabpoon: could not restore previous tab file", vim.log.levels.WARN)
	end
end

local function tabpoon_item_for_win(win)
	local item = state.item_by_win[win]
	if item and item_index(item) then
		return item
	end

	local abs_path = win_abs_path(win)
	local index = abs_path and path.find_item_index(abs_path) or nil
	if index then
		M.bind_window_to_item(win, index)
		return state.items[index]
	end

	return nil
end

local function visible_tabpoon_item_for_win(win)
	local abs_path = win_abs_path(win)
	local index = abs_path and path.find_item_index(abs_path) or nil
	if index then
		M.bind_window_to_item(win, index)
		return state.items[index]
	end

	return tabpoon_item_for_win(win)
end

function M.tab_file(tabpage)
  local ok_win, win = pcall(vim.api.nvim_tabpage_get_win, tabpage)
  if not ok_win then
    return nil
  end

  local ok_buf, buf = pcall(vim.api.nvim_win_get_buf, win)
  if not ok_buf then
    return nil
  end

  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and path.normalize(name) or nil
end

function M.find_tab(abs_path)
  abs_path = path.normalize(abs_path)
  for tabnr, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    if M.tab_file(tabpage) == abs_path then
      return tabpage, tabnr
    end
  end

  return nil, nil
end

restore_cursor = function(item)
  local row = math.max(tonumber(item.row) or 1, 1)
  local col = math.max(tonumber(item.col) or 0, 0)
  local last_line = vim.api.nvim_buf_line_count(0)

  row = math.min(row, last_line)
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  col = math.min(col, #line)

  pcall(vim.api.nvim_win_set_cursor, 0, { row, col })
end

restore_view = function(item)
	restore_cursor(item)
	pcall(vim.cmd, "normal! zz")
end

function M.update_current_position(should_write)
  if state.restoring then
    return
  end

  local bound_item = M.bound_item_for_win(vim.api.nvim_get_current_win())
  if bound_item then
    local cursor = vim.api.nvim_win_get_cursor(0)
    bound_item.row = cursor[1]
    bound_item.col = cursor[2]

    if should_write then
      storage.write()
    end

    return
  end

  local abs_path = path.current_abs_path()
  if not abs_path then
    return
  end

  local index = path.find_item_index(abs_path)
  if not index then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  state.items[index].row = cursor[1]
  state.items[index].col = cursor[2]

  if should_write then
    storage.write()
  end
end

function M.update_current_bound_item(should_write)
  if state.restoring then
    return
  end

  local win = vim.api.nvim_get_current_win()
  local item = M.bound_item_for_win(win)
  if not item then
    return
  end

	local next_item = current_file_item(false)
	if not next_item then
		return
	end

	local other_index = find_other_item_index(path.item_abs_path(next_item), item)
	if other_index then
		return
	end

	item.path = next_item.path
	item.absolute = next_item.absolute
	item.row = next_item.row
	item.col = next_item.col

  if should_write then
    storage.write()
  end

  redraw_tabline()
end

function M.reorder_tabs()
  local original_tab = vim.api.nvim_get_current_tabpage()

  for target_position, item in ipairs(state.items) do
    local win = M.window_for_item(item)
    local tabpage = win and win_tabpage(win) or nil
    if tabpage and vim.api.nvim_tabpage_is_valid(tabpage) then
      vim.api.nvim_set_current_tabpage(tabpage)
      vim.cmd("silent! tabmove " .. (target_position - 1))
    end
  end

  if vim.api.nvim_tabpage_is_valid(original_tab) then
    vim.api.nvim_set_current_tabpage(original_tab)
  end

  redraw_tabline()
end

function M.open_item(index)
  local item = state.items[index]
  if not item then
    return false
  end

  local abs_path = path.item_abs_path(item)
  if vim.fn.filereadable(abs_path) ~= 1 then
    vim.notify("Tabpoon: file does not exist: " .. abs_path, vim.log.levels.WARN)
    return false
  end

  local win = M.window_for_item(item)
  if win and vim.api.nvim_win_is_valid(win) then
    local tabpage = win_tabpage(win)
    if tabpage and vim.api.nvim_tabpage_is_valid(tabpage) then
      vim.api.nvim_set_current_tabpage(tabpage)
      vim.api.nvim_set_current_win(win)
    end
  else
    local _, tabnr = M.find_tab(abs_path)
    if tabnr then
      vim.cmd(tabnr .. "tabnext")
    else
      vim.cmd("tabedit " .. vim.fn.fnameescape(abs_path))
    end

    M.bind_window_to_item(vim.api.nvim_get_current_win(), index)
  end

  restore_view(item)
  return true
end

local function item_with_position(abs_path, opts)
	local item = path.item_from_abs_path(abs_path)
	item.row = math.max(tonumber(opts and opts.row) or 1, 1)
	item.col = math.max(tonumber(opts and opts.col) or 0, 0)
	return item
end

local function open_path_in_vertical_split(abs_path, opts)
	vim.cmd("vsplit " .. vim.fn.fnameescape(abs_path))
	restore_view(item_with_position(abs_path, opts))
	return true, "split"
end

function M.open_path(abs_path, opts)
	opts = opts or {}
	abs_path = path.normalize(abs_path)
	if abs_path == "" or vim.fn.filereadable(abs_path) ~= 1 then
		vim.notify("Tabpoon: file does not exist: " .. tostring(abs_path), vim.log.levels.WARN)
		return false, "missing"
	end

	local existing_index = path.find_item_index(abs_path)
	if existing_index then
		local item = state.items[existing_index]
		if opts.row then
			item.row = math.max(tonumber(opts.row) or 1, 1)
			item.col = math.max(tonumber(opts.col) or 0, 0)
			storage.write()
		end
		return M.open_item(existing_index), "existing"
	end

	if not M.has_capacity() then
		return open_path_in_vertical_split(abs_path, opts)
	end

	local item = item_with_position(abs_path, opts)
	state.suppress_buf_enter = true
	local ok = pcall(vim.cmd, "tabedit " .. vim.fn.fnameescape(abs_path))
	state.suppress_buf_enter = false
	if not ok then
		vim.notify("Tabpoon: could not open file: " .. abs_path, vim.log.levels.WARN)
		return false, "open_failed"
	end
	table.insert(state.items, item)
	M.bind_window_to_item(vim.api.nvim_get_current_win(), #state.items)
	storage.write()
	restore_view(item)
	redraw_tabline()
	return true, "tabpoon"
end

function M.remove_index(index)
  if not state.items[index] then
    return
  end

  unbind_item(state.items[index])
  table.remove(state.items, index)
  storage.write()
  M.reorder_tabs()
end

function M.delete_index(index)
	local item = state.items[index]
	if not item then
		return false
	end

	local win = M.window_for_item(item)
	local tabpage = win and win_tabpage(win) or nil
	local close_tab = false
	local close_win = false

	if win and vim.api.nvim_win_is_valid(win) and is_normal_window(win) then
		local tab_wins = normal_windows_in_tabpage(tabpage)
		close_tab = tabpage and #tab_wins == 1 and #vim.api.nvim_list_tabpages() > 1
		close_win = not close_tab and normal_window_count() > 1
	end

	M.remove_index(index)

	if close_tab and tabpage and vim.api.nvim_tabpage_is_valid(tabpage) then
		vim.api.nvim_set_current_tabpage(tabpage)
		vim.cmd("silent! tabclose!")
	elseif close_win and win and vim.api.nvim_win_is_valid(win) then
		pcall(vim.api.nvim_win_close, win, true)
	elseif win and vim.api.nvim_win_is_valid(win) then
		local ok_tabpage = tabpage and vim.api.nvim_tabpage_is_valid(tabpage)
		if ok_tabpage then
			vim.api.nvim_set_current_tabpage(tabpage)
			pcall(vim.api.nvim_set_current_win, win)
		end
		vim.cmd("enew")
	end

	redraw_tabline()
	return true
end

function M.remove_current()
  local bound_index = M.bound_index_for_win(vim.api.nvim_get_current_win())
  if bound_index then
    M.remove_index(bound_index)
    return
  end

  local abs_path = path.current_abs_path()
  if not abs_path then
    vim.notify("Tabpoon: current buffer has no file", vim.log.levels.WARN)
    return
  end

  local index = path.find_item_index(abs_path)
  if not index then
    vim.notify("Tabpoon: current file is not saved", vim.log.levels.INFO)
    return
  end

  M.remove_index(index)
end

local function telescope_entry_path(entry, seen)
	if not entry then
		return nil
	end

	if type(entry) == "string" and entry ~= "" then
		return path.normalize(entry)
	end

	if type(entry) ~= "table" then
		return nil
	end

	seen = seen or {}
	if seen[entry] then
		return nil
	end
	seen[entry] = true

	local function normalize_candidate(candidate)
		if type(candidate) == "string" and candidate ~= "" then
			return path.normalize(candidate)
		end
	end

	local selected_path = normalize_candidate(entry.path)
		or normalize_candidate(entry.filename)
		or normalize_candidate(entry.value)
		or normalize_candidate(entry[1])

	if selected_path then
		return selected_path
	end

	if type(entry.value) == "table" then
		return telescope_entry_path(entry.value, seen)
	end

	return nil
end

local function open_path_in_pending_win(win, abs_path)
	vim.schedule(function()
		local existing_index = path.find_item_index(abs_path)
		if existing_index then
			local _, blocked = close_pending_win(win)
			if blocked then
				return
			end

			M.open_item(existing_index)
			redraw_tabline()
			return
		end

		if not vim.api.nvim_win_is_valid(win) then
			return
		end

		local tabpage = win_tabpage(win)
		if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then
			return
		end

		vim.api.nvim_set_current_tabpage(tabpage)
		vim.api.nvim_set_current_win(win)
		local ok = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(abs_path))
		if not ok then
			vim.notify("Tabpoon: could not open selected file", vim.log.levels.WARN)
			close_abandoned_pending_win(win)
		end
	end)
end

local function open_find_files_for_pending(pending_win)
	local ok_builtin, builtin = pcall(require, "telescope.builtin")
	local ok_actions, actions = pcall(require, "telescope.actions")
	local ok_action_state, action_state = pcall(require, "telescope.actions.state")
	if not ok_builtin or not ok_actions or not ok_action_state then
		vim.notify("Tabpoon: telescope.nvim is required for find_files", vim.log.levels.WARN)
		close_abandoned_pending_win(pending_win)
		return
	end

	local selected = false
	builtin.find_files({
		hidden = true,
		no_ignore = true,
		no_ignore_parent = true,
		attach_mappings = function(prompt_bufnr)
			vim.api.nvim_create_autocmd("BufWipeout", {
				buffer = prompt_bufnr,
				once = true,
				callback = function()
					vim.schedule(function()
						if not selected then
							close_abandoned_pending_win(pending_win)
						end
					end)
				end,
			})

			actions.select_default:replace(function()
				local selected_path = telescope_entry_path(action_state.get_selected_entry())
				if not selected_path or vim.fn.filereadable(selected_path) ~= 1 then
					vim.notify("Tabpoon: could not resolve selected file", vim.log.levels.WARN)
					actions.close(prompt_bufnr)
					return
				end

				selected = true
				actions.close(prompt_bufnr)
				open_path_in_pending_win(pending_win, selected_path)
			end)
			return true
		end,
	})
end

function M.create_pending_tab(opts)
	opts = opts or {}
	local pending_win = M.pending_windows()[1]
	if pending_win and vim.api.nvim_win_is_valid(pending_win) then
		local tabpage = win_tabpage(pending_win)
		if tabpage and vim.api.nvim_tabpage_is_valid(tabpage) then
			vim.api.nvim_set_current_tabpage(tabpage)
			vim.api.nvim_set_current_win(pending_win)
			redraw_tabline()
			if opts.find_files then
				open_find_files_for_pending(pending_win)
			end
			return
		end
	end

	if not M.has_capacity() then
		vim.notify("Tabpoon: maximum saved tabs reached", vim.log.levels.WARN)
		return
	end

	vim.cmd("tabnew")
	state.pending_wins[vim.api.nvim_get_current_win()] = true
	redraw_tabline()
	if opts.find_files then
		open_find_files_for_pending(vim.api.nvim_get_current_win())
	end
end

function M.commit_window(win, should_write)
	if state.restoring then
		return false
	end

	local item = M.bound_item_for_win(win)
	if not item then
		return false
	end

	local next_item = file_item_for_win(win, false)
	if not next_item then
		return false
	end

	if find_other_item_index(path.item_abs_path(next_item), item) then
		return false
	end

	item.path = next_item.path
	item.absolute = next_item.absolute
	item.row = next_item.row
	item.col = next_item.col

	if should_write then
		storage.write()
	end

	return true
end

function M.commit_all_live_windows(should_write)
	local changed = false
	cleanup_bindings()
	for win in pairs(state.item_by_win) do
		if vim.api.nvim_win_is_valid(win) and M.commit_window(win, false) then
			changed = true
		end
	end

	if changed and should_write then
		storage.write()
	end

	if changed then
		redraw_tabline()
	end

	return changed
end

function M.ensure_first_slot()
	cleanup_bindings()
	if #state.items > 0 then
		return false
	end

	return append_current_file(vim.api.nvim_get_current_win(), false) ~= nil
end

function M.handle_buf_enter()
	if state.suppress_buf_enter then
		return
	end

	local win = vim.api.nvim_get_current_win()
	cleanup_bindings()

	local current_item = M.bound_item_for_win(win)
	local current_abs_path = win_abs_path(win)
	if current_item and current_abs_path then
		local other_index = find_other_item_index(current_abs_path, current_item)
		if other_index then
			restore_window_to_item(win, current_item)
			M.open_item(other_index)
			return
		end
	end

	if #state.items == 0 then
		append_current_file(win, false)
		return
	end

	if not state.pending_wins[win] then
		return
	end

	local pending_abs_path = win_abs_path(win)
	local existing_index = pending_abs_path and path.find_item_index(pending_abs_path) or nil
	if existing_index then
		local _, blocked = close_pending_win(win)
		if blocked then
			return
		end

		M.open_item(existing_index)
		redraw_tabline()
		return
	end

	append_current_file(win, false)
end

function M.delete_current()
	if #state.items <= 1 then
		vim.notify("Tabpoon: cannot delete the last tab", vim.log.levels.INFO)
		return
	end

	local win = vim.api.nvim_get_current_win()
	local index = M.bound_index_for_win(win)
	if not index then
		vim.notify("Tabpoon: current window is not a Tabpoon tab", vim.log.levels.INFO)
		return
	end

	M.delete_index(index)
end

function M.move_index(index, offset)
  local target = index + offset
  if not state.items[index] or target < 1 or target > #state.items then
    return nil
  end

  state.items[index], state.items[target] = state.items[target], state.items[index]
  storage.write()
  M.reorder_tabs()
  return target
end

function M.select(index)
  index = tonumber(index)
  if not index or not state.items[index] then
    vim.notify("Tabpoon: no saved tab at index " .. tostring(index), vim.log.levels.WARN)
    return
  end

	local closed_pending, blocked = close_abandoned_pending_win(vim.api.nvim_get_current_win())
	if blocked then
		return
	end

	if closed_pending then
		cleanup_bindings()
	end

	if M.bound_index_for_win(vim.api.nvim_get_current_win()) == index then
		return
	end

	M.update_current_bound_item(true)
  if M.open_item(index) then
		redraw_tabline()
  end
end

local function is_empty_start_tab()
  if #vim.api.nvim_list_tabpages() ~= 1 then
    return false
  end

  return vim.api.nvim_buf_get_name(0) == "" and not vim.bo.modified
end

function M.restore_tabs()
  if #state.items == 0 then
    return
  end

  state.restoring = true
  local kept = {}
  local pruned = false

  for _, item in ipairs(state.items) do
    local abs_path = path.item_abs_path(item)
    if vim.fn.filereadable(abs_path) == 1 then
      table.insert(kept, item)
    else
      pruned = true
    end
  end

  state.items = kept

  for index, item in ipairs(state.items) do
    local abs_path = path.item_abs_path(item)
    if index == 1 and is_empty_start_tab() then
      vim.cmd("edit " .. vim.fn.fnameescape(abs_path))
      M.bind_window_to_item(vim.api.nvim_get_current_win(), index)
      restore_view(item)
    else
      M.open_item(index)
    end
  end

  M.reorder_tabs()

  -- Startup always lands on the first saved item so the workspace opens predictably.
  if state.items[1] then
    M.open_item(1)
  end

  state.restoring = false
  redraw_tabline()

  if pruned then
    storage.write()
  end
end

local function collect_quit_plan()
	local plan = {
		tabpoon_tabs = {},
		modified_entries = {},
		has_non_tabpoon_windows = false,
		first_non_tabpoon_tab = nil,
	}
	local modified_seen = {}

	cleanup_bindings()

  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    local tabpoon_wins = {}
		local non_tabpoon_wins = {}

		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			if not is_normal_window(win) then
				goto continue
			end

			local is_tabpoon = visible_tabpoon_item_for_win(win) ~= nil

			if is_tabpoon then
				table.insert(tabpoon_wins, win)

				local buf = vim.api.nvim_win_get_buf(win)
				if vim.bo[buf].modified and not modified_seen[buf] then
					modified_seen[buf] = true
					table.insert(plan.modified_entries, { buf = buf, win = win })
				end
      else
        table.insert(non_tabpoon_wins, win)
        plan.has_non_tabpoon_windows = true
        plan.first_non_tabpoon_tab = plan.first_non_tabpoon_tab or tabpage
      end

			::continue::
    end

		if #tabpoon_wins > 0 then
			table.insert(plan.tabpoon_tabs, {
				tabpage = tabpage,
				tabnr = M.tabnr_for_win(tabpoon_wins[1]) or 1,
				tabpoon_wins = tabpoon_wins,
				non_tabpoon_wins = non_tabpoon_wins,
			})
    end
  end

	return plan
end

local function focus_win(win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end

	local tabpage = win_tabpage(win)
	if tabpage and vim.api.nvim_tabpage_is_valid(tabpage) then
		vim.api.nvim_set_current_tabpage(tabpage)
		vim.api.nvim_set_current_win(win)
	end
end

local function focus_tabpoon_window(preferred_win)
	if preferred_win and vim.api.nvim_win_is_valid(preferred_win) and visible_tabpoon_item_for_win(preferred_win) then
		focus_win(preferred_win)
		return true
	end

	for _, win in ipairs(all_windows()) do
		if vim.api.nvim_win_is_valid(win) and visible_tabpoon_item_for_win(win) then
			focus_win(win)
			return true
		end
	end

	return false
end

local function handle_modified_entries(entries)
	for _, entry in ipairs(entries) do
		local buf = entry.buf
		focus_win(entry.win)

		local name = path.filename(vim.api.nvim_buf_get_name(buf))
		local choice = vim.fn.confirm("Save changes in " .. name .. " before closing Tabpoon?", "&Yes\n&No\n&Cancel", 3)
    if choice == 1 then
      local ok = pcall(vim.api.nvim_buf_call, buf, function()
        vim.cmd("write")
      end)
      if not ok then
        return false
      end
    elseif choice == 2 then
      vim.bo[buf].modified = false
    else
      return false
    end
  end

	return true
end

local function replace_tabpoon_tab_with_empty(entry)
	if not vim.api.nvim_tabpage_is_valid(entry.tabpage) then
		return
	end

	vim.api.nvim_set_current_tabpage(entry.tabpage)
	local keep_win = nil
	for _, win in ipairs(entry.tabpoon_wins) do
		if vim.api.nvim_win_is_valid(win) then
			state.item_by_win[win] = nil
			if keep_win then
				pcall(vim.api.nvim_win_close, win, true)
			else
				keep_win = win
			end
		end
	end

	if keep_win and vim.api.nvim_win_is_valid(keep_win) then
		pcall(vim.api.nvim_set_current_win, keep_win)
		vim.cmd("enew")
	end
end

local function close_tabpoon_group(plan, opts)
	opts = opts or {}
	table.sort(plan.tabpoon_tabs, function(left, right)
		return left.tabnr > right.tabnr
	end)

	for _, entry in ipairs(plan.tabpoon_tabs) do
		if vim.api.nvim_tabpage_is_valid(entry.tabpage) then
			if #entry.non_tabpoon_wins == 0 then
				for _, win in ipairs(entry.tabpoon_wins) do
					state.item_by_win[win] = nil
				end

				if opts.keep_last_empty and #vim.api.nvim_list_tabpages() == 1 then
					replace_tabpoon_tab_with_empty(entry)
				else
					vim.api.nvim_set_current_tabpage(entry.tabpage)
					vim.cmd("silent! tabclose!")
				end
			else
				for _, win in ipairs(entry.tabpoon_wins) do
					if vim.api.nvim_win_is_valid(win) then
						state.item_by_win[win] = nil
						pcall(vim.api.nvim_win_close, win, true)
					end
				end
			end
		end
	end

	cleanup_bindings()
	if not M.has_live_tabpoon_window() then
		vim.o.showtabline = 0
	end

	redraw_tabline()
end

function M.clear()
	repair_bindings()
	local plan = collect_quit_plan()
	if not handle_modified_entries(plan.modified_entries) then
		return false
	end

	close_tabpoon_group(plan, { keep_last_empty = true })
	state.items = {}
	clear_bindings()
	storage.write()
	redraw_tabline()
	return true
end

local function run_fallback_quit()
	local fallback = config.values.fallback_quit
	if type(fallback) == "function" then
		fallback()
	elseif type(fallback) == "string" and fallback ~= "" then
		vim.cmd(fallback)
	else
		vim.cmd("quit")
	end
end

function M.quit_group_or_current(force)
	repair_bindings()

	if not visible_tabpoon_item_for_win(vim.api.nvim_get_current_win()) then
		vim.cmd(force and "quit!" or "quit")
		return
	end

	local plan = collect_quit_plan()
	if #plan.tabpoon_tabs <= 1 then
		M.update_current_bound_item(true)
		run_fallback_quit()
		return
	end

	M.commit_all_live_windows(true)
	plan = collect_quit_plan()
	if not handle_modified_entries(plan.modified_entries) then
		return
	end

	if not plan.has_non_tabpoon_windows then
		local confirm_quit = vim.fn.confirm("Quit Neovim?", "&Yes\n&No", 2)
		if confirm_quit ~= 1 then
			return
		end

		vim.cmd("quitall")
		return
	end

  if plan.first_non_tabpoon_tab and vim.api.nvim_tabpage_is_valid(plan.first_non_tabpoon_tab) then
    vim.api.nvim_set_current_tabpage(plan.first_non_tabpoon_tab)
  end

	close_tabpoon_group(plan)

	if plan.first_non_tabpoon_tab and vim.api.nvim_tabpage_is_valid(plan.first_non_tabpoon_tab) then
		vim.api.nvim_set_current_tabpage(plan.first_non_tabpoon_tab)
	end
end

function M.smart_quit()
	local menu_context = { closed = false }
	local ok_menu, menu = pcall(require, "tabpoon.menu")
	if ok_menu then
		menu_context = menu.close({ restore_focus = true }) or menu_context
	end

	repair_bindings()
	if visible_tabpoon_item_for_win(vim.api.nvim_get_current_win()) then
		M.quit_group_or_current(false)
		return
	end

	if menu_context.closed then
		local source_win = menu_context.source_win or state.last_menu_source_win
		if focus_tabpoon_window(source_win) then
			M.quit_group_or_current(false)
			return
		end
	end

	run_fallback_quit()
end

return M
