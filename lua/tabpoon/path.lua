local state = require("tabpoon.state")

local M = {}

function M.normalize(path)
	if path == nil or path == "" then
		return ""
	end

	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

function M.join(left, right)
	left = left or ""
	right = right or ""
	if left == "" then
		return right
	end
	if right == "" then
		return left
	end
	if left:sub(-1) == "/" then
		return left .. right
	end

	return left .. "/" .. right
end

function M.filename(path)
	if path == nil or path == "" then
		return "[No Name]"
	end

	local name = vim.fn.fnamemodify(path, ":t")
	return name ~= "" and name or path
end

function M.resolve_root()
	return M.normalize(vim.fn.getcwd())
end

function M.item_abs_path(item)
	if not item or type(item.path) ~= "string" then
		return ""
	end
	if item.absolute then
		return M.normalize(item.path)
	end

	return M.normalize(M.join(state.root or M.resolve_root(), item.path))
end

function M.item_from_abs_path(abs_path)
	abs_path = M.normalize(abs_path)
	local root = state.root or M.resolve_root()
	local root_prefix = root .. "/"

	if abs_path:sub(1, #root_prefix) == root_prefix then
		return {
			path = abs_path:sub(#root_prefix + 1),
			row = 1,
			col = 0,
		}
	end

	return {
		path = abs_path,
		absolute = true,
		row = 1,
		col = 0,
	}
end

function M.current_abs_path()
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" then
		return nil
	end

	return M.normalize(name)
end

function M.find_item_index(abs_path)
	abs_path = M.normalize(abs_path)
	for index, item in ipairs(state.items) do
		if M.item_abs_path(item) == abs_path then
			return index
		end
	end

	return nil
end

return M
