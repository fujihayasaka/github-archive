package migrations

var _ = Transitions.Batched("ts_analyses", `UPDATE ts_analyses FORCE INDEX(PRIMARY) SET analysis_complete = TRUE WHERE id BETWEEN ? AND ? AND failed`)
