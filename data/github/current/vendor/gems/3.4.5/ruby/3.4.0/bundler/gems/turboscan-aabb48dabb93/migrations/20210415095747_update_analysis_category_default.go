package migrations

var _ = Transitions.Batched("ts_analyses", `
UPDATE ts_analyses FORCE INDEX(PRIMARY)
SET analysis_category = ''
WHERE id BETWEEN ? AND ? AND analysis_category IS NULL AND analysis_key = '(default)'
`)
