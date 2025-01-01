package migrations

import "github.com/github/turboscan/ts/mysql/upgrades"

var _ = Transitions.Function("ts_rules", upgrades.Statements(
	// language=SQL
	`INSERT IGNORE INTO ts_rules (created_at, updated_at, repository_id, tool_id, sarif_identifier, name, short_description, full_description, help_uri, help, severity_level, security_severity, precision_level, query_uri, hash)
SELECT rX.created_at, rX.updated_at, 0, (
	SELECT MIN(t0.id)
	FROM ts_tools tX
	INNER JOIN ts_tools t0 ON t0.repository_id = 0 AND tX.canonical_name = t0.canonical_name
	WHERE rX.tool_id = tX.id
), rX.sarif_identifier, rX.name, rX.short_description, rX.full_description, rX.help_uri, rX.help, rX.severity_level, rX.security_severity, rX.precision_level, rX.query_uri, rX.hash
FROM ts_rules AS rX FORCE INDEX(PRIMARY)
WHERE rX.repository_id <> 0 AND rX.id BETWEEN ? AND ?`,

	// language=SQL
	`INSERT IGNORE INTO ts_rule_tags (created_at, updated_at, rule_id, repository_id, tag)
	SELECT rtX.created_at, rtX.updated_at, (
		SELECT r0.id
		FROM ts_rules AS rX
		INNER JOIN ts_tools AS tX ON tX.id = rX.tool_id
		INNER JOIN ts_tools AS t0 ON t0.repository_id = 0 AND t0.canonical_name = tX.canonical_name
		INNER JOIN ts_rules AS r0 ON r0.repository_id = 0 AND r0.tool_id = t0.id AND r0.hash = rX.hash AND r0.sarif_identifier = rX.sarif_identifier
		WHERE rtX.rule_id = rX.id
		ORDER BY r0.tool_id ASC
		LIMIT 1
	), 0, rtX.tag
	FROM ts_rule_tags AS rtX
	INNER JOIN ts_rules rX FORCE INDEX(PRIMARY) ON rtX.rule_id = rX.id
	WHERE rtX.repository_id <> 0 AND rX.id BETWEEN ? AND ?`,
))
