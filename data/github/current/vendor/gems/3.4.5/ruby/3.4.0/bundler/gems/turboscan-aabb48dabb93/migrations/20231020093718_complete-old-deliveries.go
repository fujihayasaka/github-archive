package migrations

var _ = Transitions.Batched("ts_deliveries", `UPDATE ts_deliveries FORCE INDEX(PRIMARY) SET
	complete = 1, 
	failed = 1,
	processing_completed_at = NOW()
	WHERE created_at < (NOW() - INTERVAL 2 WEEK)
	AND complete = 0
	AND id BETWEEN ? AND ?`)
