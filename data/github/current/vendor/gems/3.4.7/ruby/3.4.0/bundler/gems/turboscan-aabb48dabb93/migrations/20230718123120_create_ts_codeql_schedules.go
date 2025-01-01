package migrations

import "github.com/github/turboscan/ts/mysql/upgrades"

// Create a placeholder schedule for every repository with a CodeqlConfig
// We use a Function transition because we are iterating on one table while modifying another.
var _ = Transitions.Function("ts_codeql_configs", upgrades.Statements(
	// language=SQL
	`INSERT IGNORE INTO ts_codeql_schedules (repository_id, next_run_at, created_at, updated_at)
	SELECT
	repos.repository_id
	, DATE_ADD(NOW(), INTERVAL FLOOR(RAND() * 7) DAY) + INTERVAL FLOOR(RAND() * 24) HOUR + INTERVAL FLOOR(RAND() * 60) MINUTE
	, NOW()
	, NOW()
	FROM (
		SELECT DISTINCT repository_id
		FROM ts_codeql_configs
		WHERE id BETWEEN ? AND ?
	) AS repos`,
))
