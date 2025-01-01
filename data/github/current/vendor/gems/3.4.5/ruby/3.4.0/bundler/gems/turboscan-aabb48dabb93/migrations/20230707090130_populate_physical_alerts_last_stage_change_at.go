package migrations

var _ = Transitions.Batched("ts_physical_alerts", `UPDATE ts_physical_alerts FORCE INDEX(PRIMARY)
SET last_state_change_at = updated_at
WHERE last_state_change_at IS NULL AND ts_physical_alerts.id BETWEEN ? AND ?`)
