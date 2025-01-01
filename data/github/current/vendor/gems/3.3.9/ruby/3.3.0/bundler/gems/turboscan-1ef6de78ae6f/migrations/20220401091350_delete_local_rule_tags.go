package migrations

var _ = Transitions.Simple(`DELETE FROM ts_rule_tags WHERE repository_id <> 0 LIMIT ?`)
