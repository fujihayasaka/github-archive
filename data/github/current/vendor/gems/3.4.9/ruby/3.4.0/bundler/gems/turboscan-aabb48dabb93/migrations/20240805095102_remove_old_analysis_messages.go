package migrations

var _ = Transitions.Batched("ts_analysis_messages", `DELETE FROM ts_analysis_messages
	WHERE `+"`key`"+` IN ("not-enabled-third-party-tools", "not-enabled-advanced-setup")
	AND id BETWEEN ? AND ?`)
