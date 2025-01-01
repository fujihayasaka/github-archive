package migrations

// Set new ts_codeql_schedules ensuring that we do not hit the 00-03 AM window
var _ = Transitions.Step(1000).Simple(
	// language=SQL
	`UPDATE ts_codeql_schedules AS schedules
	SET next_run_at = DATE_ADD(NOW(), INTERVAL FLOOR(RAND() * 7) DAY) + INTERVAL FLOOR(RAND() * 24) HOUR + INTERVAL FLOOR(RAND() * 60) MINUTE
	WHERE HOUR(next_run_at) BETWEEN 0 AND 2
	LIMIT ?`)
