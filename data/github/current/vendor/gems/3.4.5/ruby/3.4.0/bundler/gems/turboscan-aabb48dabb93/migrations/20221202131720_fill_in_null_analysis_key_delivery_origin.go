package migrations

var _ = Transitions.Step(100000).Batched("ts_analyses", `UPDATE ts_analyses FORCE INDEX(PRIMARY)
SET analysis_key = '[migration: null]',
	delivery_origin = 3 -- API
	WHERE analysis_key IS NULL
	AND delivery_origin IS NULL
	AND id BETWEEN ? AND ?`)
