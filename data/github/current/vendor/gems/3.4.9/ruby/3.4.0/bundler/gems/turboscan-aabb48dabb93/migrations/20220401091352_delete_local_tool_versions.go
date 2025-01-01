package migrations

var _ = Transitions.Simple(`DELETE FROM ts_tool_versions WHERE repository_id <> 0 LIMIT ?`)
