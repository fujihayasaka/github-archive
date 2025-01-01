package migrations

var _ = Transitions.Step(1000).Simple(`UPDATE ts_analyses
SET results_count = (
	SELECT count(id)
	FROM ts_physical_alerts
	WHERE ts_physical_alerts.analysis_id = ts_analyses.id
	AND ts_physical_alerts.repository_id = ts_analyses.repository_id
	AND last_seen_analysis_id IS NULL
)
WHERE results_count is NULL
LIMIT ?
`)
