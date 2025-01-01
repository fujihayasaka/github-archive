package migrations

var _ = Transitions.Batched("ts_codeql_configs",
	`INSERT IGNORE INTO ts_codeql_repos (repository_id, created_at, updated_at, soft_deleted_at, supported_languages, enabled_by_actor_login, repository_grid)
	SELECT
		repository_id,
		NOW() AS created_at, -- We will reset the creation time in a follow-up transition
		NOW() AS updated_at,
		NOW() AS soft_deleted_at, -- Mark these as soft-deleted, so we can distinguish them. The follow-up transition will undelete them.
		IF(json_length(initial_languages) > json_length(languages), initial_languages, languages) AS supported_languages, -- This might not be correct at creation time.
		onboarded_by_actor_login as enabled_by_actor_login, -- We consider the actor of the latest config change. We cannot really know the first one.
		repository_grid
	FROM ts_codeql_configs FORCE INDEX(PRIMARY)
	WHERE tag IS NOT NULL AND id BETWEEN ? AND ?`,
)
