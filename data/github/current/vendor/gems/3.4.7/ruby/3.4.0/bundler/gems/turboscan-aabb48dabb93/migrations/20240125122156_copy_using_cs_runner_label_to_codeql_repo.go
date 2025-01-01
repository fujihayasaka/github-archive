package migrations

var _ = Transitions.Batched("ts_codeql_repos",
	`UPDATE
	ts_codeql_repos AS r FORCE INDEX(PRIMARY)
LEFT JOIN ts_codeql_configs AS c ON
	c.id = r.current_config_id
LEFT JOIN ts_codeql_configs AS s ON
	s.id = r.staged_config_id
SET
	r.using_cs_runner_label = COALESCE(c.using_cs_runner_label, s.using_cs_runner_label)
WHERE
	(c.id IS NOT NULL OR s.id IS NOT NULL)
AND r.id BETWEEN ? AND ?`,
)
