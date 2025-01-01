package migrations

var _ = Transitions.Step(1000).Batched("ts_analysis_rules", `UPDATE ts_analysis_rules as ar FORCE INDEX(PRIMARY)
SET ar.count = (
	SELECT count(p.id) as count
	FROM ts_analyses as a, ts_physical_alerts as p
	WHERE a.repository_id = ar.repository_id
	AND a.id = ar.analysis_id
	AND a.repository_id = p.repository_id
	AND a.id = p.analysis_id
	AND p.last_seen_analysis_id is NULL
	AND p.rule_id = ar.rule_id
)
WHERE ar.count is NULL AND ar.id BETWEEN ? AND ?`)
