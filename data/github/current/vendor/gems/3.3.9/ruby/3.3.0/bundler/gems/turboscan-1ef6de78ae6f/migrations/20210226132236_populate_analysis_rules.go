package migrations

var _ = Transitions.Step(1000).Batched("ts_analyses", `INSERT INTO ts_analysis_rules (repository_id, analysis_id, rule_id)
SELECT DISTINCT p.repository_id, p.analysis_id, p.rule_id
FROM ts_physical_alerts as p
JOIN ts_analyses as a FORCE INDEX(PRIMARY) ON p.analysis_id = a.id
WHERE a.repository_id = p.repository_id
AND a.analysis_complete
AND a.soft_deleted_at is NULL
AND p.last_seen_analysis_id is NULL
AND NOT EXISTS (
	SELECT 1
	FROM ts_analysis_rules
	WHERE repository_id=p.repository_id
	AND analysis_id=p.analysis_id
	AND rule_id=p.rule_id
) AND a.id BETWEEN ? AND ?`)
