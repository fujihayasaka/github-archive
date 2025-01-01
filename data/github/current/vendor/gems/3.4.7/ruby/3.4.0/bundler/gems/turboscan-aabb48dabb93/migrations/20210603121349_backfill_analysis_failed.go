package migrations

var _ = Transitions.Batched("ts_analyses", `UPDATE ts_analyses FORCE INDEX(PRIMARY) SET failed = NOT analysis_complete WHERE id BETWEEN ? AND ?`)
