package migrations

var _ = Transitions.Batched("ts_analyses", `
UPDATE ts_analyses FORCE INDEX(PRIMARY)
SET analysis_run_id = ''
WHERE id BETWEEN ? AND ? AND analysis_run_id IS NULL`)
