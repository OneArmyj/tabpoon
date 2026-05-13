local source = debug.getinfo(1, "S").source:sub(2)
if not source:match("^/") then
	source = vim.fn.getcwd() .. "/" .. source
end
local tests_dir = vim.fn.fnamemodify(source, ":h")
local runtime_root = vim.fn.fnamemodify(tests_dir, ":h")

vim.opt.rtp:prepend(runtime_root)
package.path = runtime_root .. "/lua/?.lua;" .. runtime_root .. "/lua/?/init.lua;" .. package.path

local root = "/tmp/opencode/tabpoon-tests"
local storage_dir = "/tmp/opencode/tabpoon-tests-state"

vim.fn.delete(root, "rf")
vim.fn.delete(storage_dir, "rf")
vim.fn.mkdir(root, "p")
vim.fn.mkdir(storage_dir, "p")

local files = {
	one = root .. "/one.lua",
	two = root .. "/two.lua",
	three = root .. "/three.lua",
	four = root .. "/four.lua",
	split = root .. "/split.lua",
}

for name, file in pairs(files) do
	vim.fn.writefile({ "-- " .. name }, file)
end

vim.fn.chdir(root)

local tabpoon = require("tabpoon")
tabpoon.setup({ storage_dir = storage_dir })

local spec = dofile(tests_dir .. "/spec.lua")
local state = require("tabpoon.state")

local function reset_runtime()
	pcall(vim.cmd, "silent! tabonly!")
	pcall(vim.cmd, "silent! enew!")
	state.items = {}
	state.item_by_win = {}
	state.pending_wins = {}
	state.suppress_buf_enter = false
	state.restoring = false
	require("tabpoon.config").setup({ storage_dir = storage_dir })
	vim.fn.delete(storage_dir, "rf")
	vim.fn.mkdir(storage_dir, "p")
	vim.o.showtabline = 0
end

local failures = {}
for _, case in ipairs(spec.cases) do
	reset_runtime()
	local ok, err = pcall(case.run, {
		files = files,
		root = root,
		storage_dir = storage_dir,
		tabpoon = tabpoon,
		state = state,
	})

	if ok then
		print("PASS " .. case.name)
	else
		table.insert(failures, case.name .. ": " .. tostring(err))
		print("FAIL " .. case.name)
		print(err)
	end
end

if #failures > 0 then
	error("Tabpoon tests failed:\n" .. table.concat(failures, "\n"))
end

print("Tabpoon tests passed: " .. #spec.cases)
