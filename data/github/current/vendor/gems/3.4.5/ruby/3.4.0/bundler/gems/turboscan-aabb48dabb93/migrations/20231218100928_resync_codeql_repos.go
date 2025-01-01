package migrations

var _ = Transitions.Batched("ts_codeql_repos",
	`UPDATE
	ts_codeql_repos AS r FORCE INDEX(PRIMARY),
	ts_codeql_configs AS current_config
SET
	r.created_at = (
		SELECT MIN(created_at) FROM ts_codeql_configs AS c WHERE c.repository_id = r.repository_id
	),
	r.updated_at = (
		SELECT MAX(created_at) FROM ts_codeql_configs AS c WHERE c.repository_id = r.repository_id
	),
	r.soft_deleted_at = NULL, -- We only consider repos with a current config, so we can re-enable the repo
	r.query_suite = COALESCE(JSON_EXTRACT(current_config.query_suite_type, '$.root'), 0),
	r.threat_model = current_config.threat_model,
	r.using_cs_runner_label = current_config.using_cs_runner_label,
	r.current_config_id = current_config.id,
	r.staged_config_id = (
		SELECT id FROM ts_codeql_configs AS c WHERE c.repository_id = r.repository_id AND c.tag = 1
	),
	r.deprecated_latest_config_id = (
	 	SELECT id FROM ts_codeql_configs AS c WHERE c.repository_id = r.repository_id AND c.tag IS NULL
	 	ORDER BY created_at DESC
	 	LIMIT 1
	),
	r.deprecated_stable_config_id = (
		SELECT id FROM ts_codeql_configs AS c WHERE c.repository_id = r.repository_id AND c.tag IS NULL AND c.validation_run_status = 2
		ORDER BY created_at DESC
		LIMIT 1
	)
WHERE current_config.repository_id = r.repository_id
AND current_config.tag = 0
AND r.id BETWEEN ? AND ?`,
)
