package migrations

var _ = Transitions.Step(1000).Simple(`
UPDATE ts_analyses AS a
SET a.tool_version_id = (
	SELECT tv.id
	FROM ts_tool_versions as tv
	WHERE a.repository_id = tv.repository_id
	AND a.tool_id = tv.tool_id
	AND a.tool_version = tv.version
)
WHERE a.tool_version_id is NULL
ORDER BY repository_id DESC
LIMIT ?
`)
