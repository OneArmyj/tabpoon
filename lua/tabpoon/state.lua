-- Shared runtime state. This is intentionally not persisted directly because
-- tab numbers and window handles are session-local and change after restart.
return {
	root = nil,
	store_path = nil,
	items = {},
	item_by_win = {},
	pending_wins = {},
	suppress_buf_enter = false,
	menu = nil,
	restoring = false,
}
