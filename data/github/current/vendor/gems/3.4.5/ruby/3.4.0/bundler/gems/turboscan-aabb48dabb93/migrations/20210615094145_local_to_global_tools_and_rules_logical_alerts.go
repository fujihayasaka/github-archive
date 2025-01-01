package migrations

var _ = Transitions.Batched("ts_logical_alerts", `UPDATE ts_logical_alerts AS target FORCE INDEX(PRIMARY)
INNER JOIN ts_rules AS rX ON target.rule_id = rX.id AND rX.repository_id = target.repository_id
INNER JOIN ts_tools AS tX ON tX.id = rX.tool_id
SET target.rule_id = (
	SELECT r0.id
	FROM ts_rules AS r0
	INNER JOIN ts_tools AS t0 ON t0.repository_id = 0 AND r0.tool_id = t0.id
	WHERE r0.repository_id = 0
	AND t0.canonical_name = tX.canonical_name
	AND r0.hash = rX.hash
	AND r0.sarif_identifier = rX.sarif_identifier
	ORDER BY r0.tool_id ASC
	LIMIT 1
)
WHERE target.id BETWEEN ? AND ?`)
