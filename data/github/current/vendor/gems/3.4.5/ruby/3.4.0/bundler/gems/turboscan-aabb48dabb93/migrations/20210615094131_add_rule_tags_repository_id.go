package migrations

var _ = Transitions.Batched("ts_rule_tags", `UPDATE ts_rule_tags FORCE INDEX(PRIMARY) INNER JOIN ts_rules ON (ts_rule_tags.rule_id = ts_rules.id) SET ts_rule_tags.repository_id = ts_rules.repository_id WHERE ts_rule_tags.repository_id IS NULL AND ts_rule_tags.id BETWEEN ? AND ?`)
