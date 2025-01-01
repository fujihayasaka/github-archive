package migrations

var _ = Transitions.Batched("ts_physical_alerts", `UPDATE ts_physical_alerts FORCE INDEX(PRIMARY) SET end_line = start_line WHERE id BETWEEN ? AND ? AND start_line > end_line`)
