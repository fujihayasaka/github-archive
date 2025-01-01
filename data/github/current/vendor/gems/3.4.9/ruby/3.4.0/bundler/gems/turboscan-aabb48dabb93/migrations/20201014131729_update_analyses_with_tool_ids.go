package migrations

var _ = Transitions.Step(1000).Simple(`
UPDATE ts_analyses AS a
SET a.tool_id = (
	SELECT t.id
	FROM ts_tools as t
	WHERE a.repository_id = t.repository_id
	AND a.tool = t.canonical_name)
WHERE a.tool_id is NULL
ORDER BY repository_id DESC
LIMIT ?
`)
