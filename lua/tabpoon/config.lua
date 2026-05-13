local M = {}

local defaults = {
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
}

M.values = vim.deepcopy(defaults)

local function validate(opts)
	vim.validate({
		opts = { opts, "table", true },
	})

	if not opts then
		return
	end

	vim.validate({
		storage_dir = { opts.storage_dir, "string", true },
		fallback_quit = { opts.fallback_quit, { "string", "function" }, true },
		max_tabs = { opts.max_tabs, "number", true },
		appearance = { opts.appearance, "table", true },
	})

	if opts.max_tabs ~= nil then
		if opts.max_tabs < 1 or opts.max_tabs > 9 or opts.max_tabs % 1 ~= 0 then
			error("Tabpoon: max_tabs must be an integer from 1 to 9")
		end
	end

	if opts.appearance then
		for _, key in ipairs({ "active", "inactive", "fill", "active_link", "inactive_link", "fill_link" }) do
			vim.validate({ ["appearance." .. key] = { opts.appearance[key], "string", true } })
		end
	end
end

function M.setup(opts)
	validate(opts)
	M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	M.values.storage_dir = vim.fs.normalize(vim.fn.expand(M.values.storage_dir))
end

return M
