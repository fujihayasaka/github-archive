package migrations

var _ = Transitions.Simple(`DELETE FROM ts_tools WHERE repository_id <> 0 LIMIT ?`)
