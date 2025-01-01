package migrations

var _ = Transitions.Batched("ts_physical_alerts", "DELETE FROM ts_physical_alerts WHERE id BETWEEN ? AND ? AND logical_alert_id = 0")
