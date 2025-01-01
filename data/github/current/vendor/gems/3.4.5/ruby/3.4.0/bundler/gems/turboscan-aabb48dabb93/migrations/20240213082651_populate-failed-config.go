package migrations

var _ = Transitions.Batched("ts_codeql_repos",
	`UPDATE
	ts_codeql_repos FORCE INDEX(PRIMARY)
LEFT JOIN ts_codeql_configs AS current
ON ts_codeql_repos.current_config_id = current.id
LEFT JOIN ts_codeql_configs AS deprecated
ON ts_codeql_repos.deprecated_latest_config_id = deprecated.id
LEFT JOIN ts_codeql_configs AS deprecated_stable
ON ts_codeql_repos.deprecated_stable_config_id = deprecated_stable.id
 SET
    ts_codeql_repos.failed_config_id = deprecated.id
WHERE
	ts_codeql_repos.id BETWEEN ? AND ?
	AND failed_config_id IS NULL
	AND (deprecated.validation_run_status = 3 OR deprecated.validation_run_status = 4) -- Deprecated latest validation failed or cancelled
	AND (ts_codeql_repos.current_config_id IS NULL OR deprecated.created_at > current.created_at) -- There is no current config, or is older
	AND (ts_codeql_repos.deprecated_stable_config_id IS NULL OR deprecated.deprecated_at > deprecated_stable.deprecated_at) -- There is no deprecated_stable config, or is older`,
)
