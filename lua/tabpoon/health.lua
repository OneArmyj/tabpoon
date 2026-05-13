local M = {}

local function health()
	local ok = vim.health.ok or vim.health.report_ok
	local warn = vim.health.warn or vim.health.report_warn
	local error = vim.health.error or vim.health.report_error
	local info = vim.health.info or vim.health.report_info
	local start = vim.health.start or vim.health.report_start

	return {
		ok = ok,
		warn = warn,
		error = error,
		info = info,
		start = start,
	}
end

function M.check()
	local h = health()
	local config = require("tabpoon.config")

	h.start("tabpoon.nvim")

	if vim.fn.has("nvim-0.10") == 1 then
		h.ok("Neovim >= 0.10")
	else
		h.error("Neovim 0.10 or newer is required")
	end

	local storage_dir = config.values.storage_dir
	local ok_mkdir, mkdir_err = pcall(vim.fn.mkdir, storage_dir, "p")
	if ok_mkdir and vim.fn.isdirectory(storage_dir) == 1 then
		local probe = storage_dir .. "/.tabpoon-health"
		local ok_write = pcall(vim.fn.writefile, { "ok" }, probe)
		if ok_write then
			pcall(vim.fn.delete, probe)
			h.ok("Storage directory is writable: " .. storage_dir)
		else
			h.error("Storage directory is not writable: " .. storage_dir)
		end
	else
		h.error("Could not create storage directory: " .. storage_dir .. " (" .. tostring(mkdir_err) .. ")")
	end

	if pcall(require, "telescope.builtin") then
		h.ok("telescope.nvim found for create_tab({ find_files = true })")
	else
		h.warn("telescope.nvim not found; create_tab({ find_files = true }) will be unavailable")
	end

	h.info("Workspace root: " .. require("tabpoon.path").resolve_root())
end

return M
