package migrations

var _ = Transitions.Step(100).Simple(`
INSERT INTO ts_tools (created_at, updated_at, repository_id, guid, canonical_name, is_internal_guid)
SELECT DISTINCT NOW(), NOW(), r.repository_id, UUID(), r.tool, 1
FROM ts_rules AS r
WHERE r.tool_id is NULL
AND NOT EXISTS (
	SELECT * FROM ts_tools as t
	WHERE t.repository_id = r.repository_id
	AND t.canonical_name = r.tool
)
ORDER BY repository_id DESC
LIMIT ?
`)
