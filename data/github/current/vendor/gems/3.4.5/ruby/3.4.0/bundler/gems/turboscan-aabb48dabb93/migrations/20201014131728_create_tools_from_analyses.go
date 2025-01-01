package migrations

var _ = Transitions.Step(100).Simple(`
INSERT INTO ts_tools (created_at, updated_at, repository_id, guid, canonical_name, is_internal_guid)
SELECT DISTINCT NOW(), NOW(), a.repository_id, UUID(), a.tool, 1
FROM ts_analyses AS a
WHERE a.tool_id is NULL
AND NOT EXISTS (
	SELECT * FROM ts_tools as t
	WHERE t.repository_id = a.repository_id
	AND t.canonical_name = a.tool
)
ORDER BY repository_id DESC
LIMIT ?
`)
