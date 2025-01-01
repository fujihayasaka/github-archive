package migrations

var _ = Transitions.Step(100).Simple(`
INSERT INTO ts_tool_versions (created_at, updated_at, repository_id, tool_id, name, version)
SELECT DISTINCT NOW(), NOW(), a.repository_id, a.tool_id, a.tool, a.tool_version
FROM ts_analyses AS a
WHERE a.tool_version_id is NULL
AND NOT EXISTS (
	SELECT * FROM ts_tool_versions as t
	WHERE t.repository_id = a.repository_id
	AND t.tool_id = a.tool_id
	AND t.version = a.tool_version
)
ORDER BY repository_id DESC
LIMIT ?
`)
