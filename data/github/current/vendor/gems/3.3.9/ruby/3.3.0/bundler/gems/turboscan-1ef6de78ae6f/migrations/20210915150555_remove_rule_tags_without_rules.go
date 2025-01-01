package migrations

var _ = Transitions.Batched("ts_rule_tags", `DELETE ts_rule_tags FROM ts_rule_tags FORCE INDEX(PRIMARY)
LEFT OUTER JOIN ts_rules ON (ts_rule_tags.rule_id = ts_rules.id)
WHERE ts_rule_tags.repository_id IS NULL AND ts_rules.id IS NULL
  AND ts_rule_tags.id BETWEEN ? AND ?`)
