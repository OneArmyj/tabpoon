local tabs = require("tabpoon.tabs")
local storage = require("tabpoon.storage")

local M = {}

function M.expand_quit_abbrev(command)
	if vim.fn.getcmdtype() == ":" and vim.fn.getcmdline() == command then
		return "TabpoonQuit"
	end

	return command
end

function M.setup()
	local group = vim.api.nvim_create_augroup("Tabpoon", { clear = true })
	vim.api.nvim_create_autocmd("BufLeave", {
		group = group,
		callback = function()
			tabs.update_current_position(true)
		end,
	})

	vim.api.nvim_create_autocmd("TabLeave", {
		group = group,
		callback = function()
			tabs.update_current_bound_item(true)
		end,
	})

	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function()
			tabs.handle_buf_enter()
		end,
	})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			tabs.commit_all_live_windows(false)
			storage.write()
		end,
	})

	vim.api.nvim_create_user_command("TabpoonQuit", function(opts)
		tabs.quit_group_or_current(opts.bang)
	end, { bang = true, force = true, desc = "Quit the Tabpoon tab group or current window" })

	for _, command in ipairs({ "q", "quit", "q!", "quit!" }) do
		vim.cmd("silent! cunabbrev " .. command)
	end

	-- Built-in lowercase commands cannot be replaced directly. Exact command-line
	-- abbreviations route :q/:quit, and their bang forms, through TabpoonQuit.
	vim.cmd("cnoreabbrev <expr> q v:lua.require'tabpoon.commands'.expand_quit_abbrev('q')")
	vim.cmd("cnoreabbrev <expr> quit v:lua.require'tabpoon.commands'.expand_quit_abbrev('quit')")

	local restore = function()
		tabs.restore_tabs()
		tabs.ensure_first_slot()
		require("tabpoon.tabline").redraw()
	end

	if vim.v.vim_did_enter == 1 then
		vim.schedule(restore)
	else
		vim.api.nvim_create_autocmd("VimEnter", {
			group = group,
			once = true,
			callback = function()
				vim.schedule(restore)
			end,
		})
	end
end

return M
