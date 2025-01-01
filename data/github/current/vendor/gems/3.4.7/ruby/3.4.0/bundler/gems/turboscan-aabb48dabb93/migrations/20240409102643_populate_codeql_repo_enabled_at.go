package migrations

var _ = Transitions.Batched("ts_codeql_repos", `UPDATE ts_codeql_repos FORCE INDEX(PRIMARY)
	SET enabled_at = created_at
	WHERE enabled_at is NULL
	AND id BETWEEN ? AND ?`)
