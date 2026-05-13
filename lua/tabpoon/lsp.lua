local M = {}

function M.definition_target_from_results(results)
	for _, response in pairs(results or {}) do
		local result = response.result
		if result then
			if vim.islist(result) then
				if result[1] then
					return result[1]
				end
			else
				return result
			end
		end
	end

	return nil
end

function M.target_location(target)
	if not target then
		return nil
	end

	local uri = target.targetUri or target.uri
	local range = target.targetSelectionRange or target.targetRange or target.range
	if not uri or not range or not range.start then
		return nil
	end

	return {
		path = vim.uri_to_fname(uri),
		row = range.start.line + 1,
		col = range.start.character,
	}
end

function M.definition(opts)
	opts = opts or {}
	local bufnr = opts.bufnr or 0
	local encoding = opts.position_encoding or "utf-16"
	local params = vim.lsp.util.make_position_params(bufnr, encoding)

	vim.lsp.buf_request_all(bufnr, "textDocument/definition", params, function(results)
		local target = M.definition_target_from_results(results)
		if not target then
			vim.notify("LSP: definition not found", vim.log.levels.INFO)
			return
		end

		local location = M.target_location(target)
		if not location then
			vim.notify("LSP: definition target could not be resolved", vim.log.levels.WARN)
			return
		end

		require("tabpoon.tabs").open_path(location.path, {
			row = location.row,
			col = location.col,
		})
	end)
end

return M
