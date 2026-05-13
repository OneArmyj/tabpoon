local M = {}

local function assert_eq(actual, expected, message)
	if actual ~= expected then
		error((message or "assert_eq failed") .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
	end
end

local function assert_match(value, pattern, message)
	if not tostring(value):match(pattern) then
		error((message or "assert_match failed") .. ": " .. vim.inspect(value) .. " does not match " .. pattern)
	end
end

local function names_in_windows()
	local names = {}
	for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
			if name ~= "" then
				table.insert(names, vim.fn.fnamemodify(name, ":t"))
			end
		end
	end
	return table.concat(names, ",")
end

local function live_pending_count(state)
	local count = 0
	for win in pairs(state.pending_wins) do
		if vim.api.nvim_win_is_valid(win) then
			count = count + 1
		end
	end
	return count
end

M.cases = {
	{
		name = "setup is idempotent and resets omitted options to defaults",
		run = function(ctx)
			ctx.tabpoon.setup({
				storage_dir = ctx.storage_dir,
				appearance = { active = "TabpoonCustomActive" },
			})
			assert_eq(require("tabpoon.config").values.appearance.active, "TabpoonCustomActive")
			ctx.tabpoon.setup({ storage_dir = ctx.storage_dir })
			assert_eq(require("tabpoon.config").values.appearance.active, "TabpoonActive")
		end,
	},
	{
		name = "max tabs defaults to nine and validates configured values",
		run = function(ctx)
			ctx.tabpoon.setup({ storage_dir = ctx.storage_dir })
			assert_eq(ctx.tabpoon.max_tabs(), 9)
			assert_eq(require("tabpoon.config").values.max_tabs, 9)

			ctx.tabpoon.setup({ storage_dir = ctx.storage_dir, max_tabs = 2 })
			assert_eq(ctx.tabpoon.max_tabs(), 2)

			local ok_too_high = pcall(function()
				ctx.tabpoon.setup({ storage_dir = ctx.storage_dir, max_tabs = 10 })
			end)
			assert_eq(ok_too_high, false)

			local ok_fraction = pcall(function()
				ctx.tabpoon.setup({ storage_dir = ctx.storage_dir, max_tabs = 1.5 })
			end)
			assert_eq(ok_fraction, false)

			ctx.tabpoon.setup({ storage_dir = ctx.storage_dir })
		end,
	},
	{
		name = "open path reuses duplicates and falls back to vertical split when full",
		run = function(ctx)
			ctx.tabpoon.setup({ storage_dir = ctx.storage_dir, max_tabs = 2 })
			local ok_one, mode_one = ctx.tabpoon.open_path(ctx.files.one)
			assert_eq(ok_one, true)
			assert_eq(mode_one, "tabpoon")
			assert_eq(#ctx.state.items, 1)

			local ok_existing, mode_existing = ctx.tabpoon.open_path(ctx.files.one, { row = 1, col = 0 })
			assert_eq(ok_existing, true)
			assert_eq(mode_existing, "existing")
			assert_eq(#ctx.state.items, 1)

			local ok_two, mode_two = ctx.tabpoon.open_path(ctx.files.two)
			assert_eq(ok_two, true)
			assert_eq(mode_two, "tabpoon")
			assert_eq(#ctx.state.items, 2)
			assert_eq(ctx.tabpoon.has_capacity(), false)

			ctx.tabpoon.select(1)
			local tabpage = vim.api.nvim_get_current_tabpage()
			local before = #vim.api.nvim_tabpage_list_wins(tabpage)
			local ok_split, mode_split = ctx.tabpoon.open_path(ctx.files.three)
			assert_eq(ok_split, true)
			assert_eq(mode_split, "split")
			assert_eq(#ctx.state.items, 2)
			assert_eq(vim.api.nvim_get_current_tabpage(), tabpage)
			assert_eq(#vim.api.nvim_tabpage_list_wins(tabpage), before + 1)
			assert_match(vim.api.nvim_buf_get_name(0), "three%.lua$")

			ctx.tabpoon.setup({ storage_dir = ctx.storage_dir })
		end,
	},
	{
		name = "lsp definition helpers resolve first location target",
		run = function(ctx)
			local lsp = require("tabpoon.lsp")
			local target = lsp.definition_target_from_results({
				client_a = { result = {} },
				client_b = {
					result = {
						{
							uri = vim.uri_from_fname(ctx.files.two),
							range = { start = { line = 4, character = 2 } },
						},
					},
				},
			})
			local location = lsp.target_location(target)
			assert_eq(location.path, ctx.files.two)
			assert_eq(location.row, 5)
			assert_eq(location.col, 2)
		end,
	},
	{
		name = "first valid file creates item one and hides tabline",
		run = function(ctx)
			assert_eq(ctx.state.root, vim.fs.normalize(vim.fn.getcwd()))
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			assert_eq(#ctx.state.items, 1)
			assert_match(ctx.state.items[1].path, "one%.lua$")
			assert_eq(tostring(vim.o.showtabline), "0")
		end,
	},
	{
		name = "pending tab closes when selecting saved tab before valid file",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			assert_eq(#ctx.state.items, 1)
			assert_eq(live_pending_count(ctx.state), 1)
			assert_eq(tostring(vim.o.showtabline), "2")
			local line = ctx.tabpoon.tabline()
			assert(line:find("󰲠 one.lua", 1, true), line)
			assert(line:find("%#TabpoonActive#󰲢%#TabpoonInactive# [new]", 1, true), line)
			ctx.tabpoon.select(1)
			assert_eq(#ctx.state.items, 1)
			assert_eq(live_pending_count(ctx.state), 0)
			assert_eq(#vim.api.nvim_list_tabpages(), 1)
			assert_eq(tostring(vim.o.showtabline), "0")
		end,
	},
	{
		name = "create tab focuses existing pending tab",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			local pending_win = vim.api.nvim_get_current_win()
			vim.cmd("1tabnext")
			assert(vim.api.nvim_get_current_win() ~= pending_win)
			ctx.tabpoon.create_tab()
			assert_eq(vim.api.nvim_get_current_win(), pending_win)
			assert_eq(live_pending_count(ctx.state), 1)
			assert_eq(#vim.api.nvim_list_tabpages(), 2)
		end,
	},
	{
		name = "pending tab persists after opening valid file",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			assert_eq(#ctx.state.items, 2)
			assert_match(ctx.state.items[2].path, "two%.lua$")
		end,
	},
	{
		name = "pending tab selecting existing file jumps to saved tab",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			assert_eq(#ctx.state.items, 1)
			assert_eq(live_pending_count(ctx.state), 0)
			assert_eq(ctx.tabpoon._test_bound_index(), 1)
			assert_eq(#vim.api.nvim_list_tabpages(), 1)
		end,
	},
	{
		name = "delete protects last saved item",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.delete_current()
			assert_eq(#ctx.state.items, 1)
			assert_match(ctx.state.items[1].path, "one%.lua$")
		end,
	},
	{
		name = "selecting current slot is a no-op",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			ctx.tabpoon.select(1)
			local win = vim.api.nvim_get_current_win()
			ctx.tabpoon.select(1)
			assert_eq(vim.api.nvim_get_current_win(), win)
		end,
	},
	{
		name = "oil buffers render short label",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			ctx.tabpoon.select(1)
			vim.bo.filetype = "oil"
			local line = ctx.tabpoon.tabline()
			assert(line:find("%#TabpoonActive#󰲠%#TabpoonInactive# oil", 1, true), line)
			assert(not line:find("oil://", 1, true), line)
		end,
	},
	{
		name = "tab switch commits current file",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			ctx.tabpoon.select(1)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.three))
			ctx.tabpoon.select(2)
			assert_match(ctx.state.items[1].path, "three%.lua$")
		end,
	},
	{
		name = "opening file owned by another tab jumps to that tab",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			ctx.tabpoon.select(1)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			assert_eq(ctx.tabpoon._test_bound_index(), 2)
			assert_match(ctx.state.items[1].path, "one%.lua$")
			ctx.tabpoon.select(1)
			assert_match(vim.api.nvim_buf_get_name(0), "one%.lua$")
		end,
	},
	{
		name = "clear closes live tabpoon tabs",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.three))

			assert_eq(ctx.tabpoon.clear(), true)
			assert_eq(#ctx.state.items, 0)
			local names = names_in_windows()
			assert(not names:find("one.lua", 1, true), names)
			assert(not names:find("two.lua", 1, true), names)
			assert(not names:find("three.lua", 1, true), names)
			assert_eq(ctx.tabpoon.tabline(), "")
		end,
	},
	{
		name = "clear preserves non-tabpoon tabs and splits",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			vim.cmd("tabnew " .. vim.fn.fnameescape(ctx.files.three))
			vim.cmd("vsplit " .. vim.fn.fnameescape(ctx.files.split))
			ctx.tabpoon.select(1)

			assert_eq(ctx.tabpoon.clear(), true)
			assert_eq(#ctx.state.items, 0)
			local names = names_in_windows()
			assert(names:find("three.lua", 1, true), names)
			assert(names:find("split.lua", 1, true), names)
			assert(not names:find("one.lua", 1, true), names)
			assert(not names:find("two.lua", 1, true), names)
		end,
	},
	{
		name = "clear aborts when modified buffer handling is cancelled",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { "-- changed" })
			vim.bo.modified = true

			local original_confirm = vim.fn.confirm
			vim.fn.confirm = function()
				return 3
			end
			local ok, result = pcall(ctx.tabpoon.clear)
			vim.fn.confirm = original_confirm

			assert_eq(ok, true)
			assert_eq(result, false)
			assert_eq(#ctx.state.items, 1)
			local names = names_in_windows()
			assert(names:find("one.lua", 1, true), names)
			vim.bo.modified = false
		end,
	},
	{
		name = "group quit preserves non-tabpoon tab",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			vim.cmd("tabnew " .. vim.fn.fnameescape(ctx.files.three))
			ctx.tabpoon.select(1)
			vim.cmd("TabpoonQuit")
			local names = names_in_windows()
			assert(names:find("three.lua", 1, true), names)
			assert(not names:find("one.lua", 1, true), names)
			assert(not names:find("two.lua", 1, true), names)
		end,
	},
	{
		name = "group quit ignores floating windows on tabpoon tabs",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			vim.cmd("tabnew " .. vim.fn.fnameescape(ctx.files.three))
			ctx.tabpoon.select(1)

			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_open_win(buf, false, {
				relative = "editor",
				row = 1,
				col = 1,
				width = 12,
				height = 1,
				style = "minimal",
			})

			vim.cmd("TabpoonQuit")
			local names = names_in_windows()
			assert(names:find("three.lua", 1, true), names)
			assert(not names:find("one.lua", 1, true), names)
			assert(not names:find("two.lua", 1, true), names)
		end,
	},
	{
		name = "menu uses compact styled layout and command header",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			ctx.tabpoon.select(1)

			ctx.tabpoon.toggle_menu()
			local lines = vim.api.nvim_buf_get_lines(ctx.state.menu.buf, 0, 2, false)
			assert_eq(lines[1], " <CR> open   dd delete   K/J move   q close")

			local win_config = vim.api.nvim_win_get_config(ctx.state.menu.win)
			assert_eq(win_config.width, math.min(math.max(math.floor(vim.o.columns * 0.5), 20), math.max(vim.o.columns - 4, 20)))
			assert_eq(vim.fn.hlexists("TabpoonMenuTitle"), 1)
			assert_eq(vim.fn.hlexists("TabpoonMenuActive"), 1)

			vim.api.nvim_win_set_cursor(ctx.state.menu.win, { 4, 0 })
			vim.api.nvim_set_current_win(ctx.state.menu.win)
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("dd", true, false, true), "x", false)
			assert_eq(#ctx.state.items, 1)
			assert_match(ctx.state.items[1].path, "one%.lua$")
			ctx.tabpoon.toggle_menu()
		end,
	},
	{
		name = "menu close preserves smart quit source tab",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			vim.cmd("tabnew " .. vim.fn.fnameescape(ctx.files.three))
			ctx.tabpoon.select(1)
			local source_win = vim.api.nvim_get_current_win()
			ctx.tabpoon.toggle_menu()
			ctx.tabpoon.toggle_menu()
			assert_eq(vim.api.nvim_get_current_win(), source_win)
			ctx.tabpoon.smart_quit()
			local names = names_in_windows()
			assert(names:find("three.lua", 1, true), names)
			assert(not names:find("one.lua", 1, true), names)
			assert(not names:find("two.lua", 1, true), names)
		end,
	},
	{
		name = "menu delete closes live tab before pending tab commit",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			vim.bo.filetype = ""
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.three))
			ctx.tabpoon.select(1)

			ctx.tabpoon.toggle_menu()
			vim.api.nvim_win_set_cursor(ctx.state.menu.win, { 4, 0 })
			vim.api.nvim_set_current_win(ctx.state.menu.win)
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("dd", true, false, true), "x", false)

			assert_eq(#ctx.state.items, 2)
			assert_match(ctx.state.items[1].path, "one%.lua$")
			assert_match(ctx.state.items[2].path, "three%.lua$")
			local names = names_in_windows()
			assert(not names:find("two.lua", 1, true), names)

			ctx.tabpoon.toggle_menu()
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.four))
			assert_eq(#ctx.state.items, 3)
			assert_match(ctx.state.items[3].path, "four%.lua$")

			local line = ctx.tabpoon.tabline()
			assert(line:find("one.lua", 1, true), line)
			assert(line:find("three.lua", 1, true), line)
			assert(line:find("four.lua", 1, true), line)
			assert(not line:find("two.lua", 1, true), line)
		end,
	},
	{
		name = "smart quit from open menu closes tabpoon group",
		run = function(ctx)
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.one))
			ctx.tabpoon.create_tab()
			vim.cmd("edit " .. vim.fn.fnameescape(ctx.files.two))
			vim.cmd("tabnew " .. vim.fn.fnameescape(ctx.files.three))
			ctx.tabpoon.select(1)
			ctx.tabpoon.toggle_menu()
			ctx.tabpoon.smart_quit()
			local names = names_in_windows()
			assert(names:find("three.lua", 1, true), names)
			assert(not names:find("one.lua", 1, true), names)
			assert(not names:find("two.lua", 1, true), names)
		end,
	},
}

return M
