package migrations

var _ = Transitions.Step(10000).Batched("ts_logical_alerts", `
	DELETE FROM ts_logical_alerts 
	WHERE id BETWEEN ? AND ? AND soft_deleted_at IS NOT NULL
`)
