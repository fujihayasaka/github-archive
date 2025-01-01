package migrations

var _ = Transitions.Step(1000).Simple(`UPDATE ts_analyses
SET rules_count = (
	SELECT count(id)
	FROM ts_analysis_rules
	WHERE ts_analysis_rules.analysis_id = ts_analyses.id
	AND ts_analysis_rules.repository_id = ts_analyses.repository_id
)
WHERE rules_count is NULL
LIMIT ?
`)
