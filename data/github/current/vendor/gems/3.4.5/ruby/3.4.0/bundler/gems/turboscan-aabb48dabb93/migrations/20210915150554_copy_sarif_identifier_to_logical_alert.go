package migrations

var _ = Transitions.Batched("ts_logical_alerts", `UPDATE ts_logical_alerts FORCE INDEX(PRIMARY)
INNER JOIN ts_rules ON ts_logical_alerts.rule_id = ts_rules.id
SET ts_logical_alerts.sarif_identifier = ts_rules.sarif_identifier
WHERE ts_logical_alerts.id BETWEEN ? AND ?`)
