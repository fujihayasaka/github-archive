package migrations

var _ = Transitions.Batched("ts_codeql_repos",
	`UPDATE
	ts_codeql_repos FORCE INDEX(PRIMARY)
LEFT JOIN ts_codeql_configs AS current
ON ts_codeql_repos.current_config_id = current.id
LEFT JOIN ts_codeql_configs AS staged
ON ts_codeql_repos.staged_config_id = staged.id
 SET
    ts_codeql_repos.java_extraction_options = GREATEST(
		COALESCE(current.java_extraction_options, 0),
		COALESCE(staged.java_extraction_options, 0))
WHERE
	ts_codeql_repos.id BETWEEN ? AND ?`,
)
