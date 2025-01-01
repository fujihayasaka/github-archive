package migrations

var _ = Transitions.Batched("ts_analyses", `UPDATE ts_analyses FORCE INDEX(PRIMARY)
SET analysis_category = '[migration: null]', soft_deleted_at = NOW(), most_recent = FALSE
WHERE analysis_category IS NULL
  AND analysis_key IS NULL
  AND id BETWEEN ? AND ?`)
