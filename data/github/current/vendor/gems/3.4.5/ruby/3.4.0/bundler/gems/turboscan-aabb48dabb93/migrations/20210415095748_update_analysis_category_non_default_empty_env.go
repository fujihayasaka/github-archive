package migrations

var _ = Transitions.Batched("ts_analyses", `
UPDATE ts_analyses FORCE INDEX(PRIMARY)
SET analysis_category = analysis_key
WHERE id BETWEEN ? AND ? AND analysis_category IS NULL AND analysis_key != '(default)' AND JSON_LENGTH(environment) = 0
`)
