package migrations

var _ = Transitions.Step(1000).Simple(`
UPDATE ts_rules AS r
SET r.tool_id = (
	SELECT t.id
	FROM ts_tools as t
	WHERE r.repository_id = t.repository_id
	AND r.tool = t.canonical_name)
WHERE r.tool_id is NULL
ORDER BY repository_id DESC
LIMIT ?
`)
