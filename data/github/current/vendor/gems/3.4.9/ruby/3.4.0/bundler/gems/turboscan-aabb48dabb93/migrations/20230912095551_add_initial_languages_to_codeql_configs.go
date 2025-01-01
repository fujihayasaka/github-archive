package migrations

// Backfill the field InitialLanguages copying the Languages field
var _ = Transitions.Batched("ts_codeql_configs", `UPDATE ts_codeql_configs FORCE INDEX(PRIMARY)
	SET initial_languages = languages 
	WHERE initial_languages is NULL
	AND id BETWEEN ? AND ?`)
