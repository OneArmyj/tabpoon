local state = require("tabpoon.state")
local path = require("tabpoon.path")

local M = {}

local function notify_io_error(action, err)
	local message = "Tabpoon: could not " .. action .. " workspace state: " .. tostring(err)
	if vim.in_fast_event() then
		vim.schedule(function()
			vim.notify(message, vim.log.levels.WARN)
		end)
	else
		vim.notify(message, vim.log.levels.WARN)
	end
end

function M.write()
	if not state.store_path then
		return false
	end

	local ok_encode, encoded = pcall(vim.json.encode, {
		version = 1,
		root = state.root,
		items = state.items,
	})
	if not ok_encode then
		notify_io_error("encode", encoded)
		return false
	end

	local dir = vim.fn.fnamemodify(state.store_path, ":h")
	local ok_write, err = pcall(function()
		vim.fn.mkdir(dir, "p")
		local tmp_path = state.store_path .. "." .. tostring(vim.uv.os_getpid()) .. ".tmp"
		local result = vim.fn.writefile({ encoded }, tmp_path)
		if result ~= 0 then
			error("writefile returned " .. result)
		end
		local ok_rename, rename_err = vim.uv.fs_rename(tmp_path, state.store_path)
		if not ok_rename then
			error(rename_err or "rename failed")
		end
	end)

	if not ok_write then
		notify_io_error("write", err)
		return false
	end

	return true
end

function M.load()
	state.items = {}
	if not state.store_path or vim.uv.fs_stat(state.store_path) == nil then
		return
	end

	local ok_read, lines = pcall(vim.fn.readfile, state.store_path)
	if not ok_read then
		notify_io_error("read", lines)
		return
	end
	if #lines == 0 then
		return
	end

	local ok, payload = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not ok or type(payload) ~= "table" or type(payload.items) ~= "table" then
		vim.notify("Tabpoon: could not read saved workspace state", vim.log.levels.WARN)
		return
	end

	local seen = {}
	for _, item in ipairs(payload.items) do
		if type(item) == "table" and type(item.path) == "string" and item.path ~= "" then
			local saved_item = {
				path = item.path,
				absolute = item.absolute == true or nil,
				row = tonumber(item.row) or 1,
				col = tonumber(item.col) or 0,
			}
			local abs_path = path.item_abs_path(saved_item)

			-- Preserve first occurrence and discard stale duplicate entries.
			if not seen[abs_path] then
				seen[abs_path] = true
				table.insert(state.items, saved_item)
			end
		end
	end
end

return M
