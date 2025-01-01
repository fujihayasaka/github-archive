package migrations

var _ = Transitions.Simple(`DELETE FROM ts_rules WHERE repository_id <> 0 LIMIT ?`)
