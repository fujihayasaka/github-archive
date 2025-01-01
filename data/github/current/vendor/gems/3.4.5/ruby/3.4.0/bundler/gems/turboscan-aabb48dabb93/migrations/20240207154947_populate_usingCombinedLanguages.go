package migrations

var _ = Transitions.Batched("ts_codeql_repos",
	`UPDATE
	ts_codeql_repos FORCE INDEX(PRIMARY)
LEFT JOIN ts_codeql_configs AS current
ON ts_codeql_repos.current_config_id = current.id
LEFT JOIN ts_codeql_configs AS staged
ON ts_codeql_repos.staged_config_id = staged.id
LEFT JOIN ts_codeql_configs AS deprecated
ON ts_codeql_repos.deprecated_latest_config_id = deprecated.id
 SET
    ts_codeql_repos.using_combined_languages = COALESCE(
		current.using_combined_languages,
		staged.using_combined_languages,
		deprecated.using_combined_languages, 1)
WHERE
	ts_codeql_repos.id BETWEEN ? AND ?`,
)
