package migrations

// Backfill the field CreatedByActorLogin copying the OnboardedByActorLogin
var _ = Transitions.Batched("ts_codeql_configs", `UPDATE ts_codeql_configs FORCE INDEX(PRIMARY)
	SET created_by_actor_login = onboarded_by_actor_login
	WHERE (created_by_actor_login is NULL or created_by_actor_login = "")
	AND id BETWEEN ? AND ?`)
