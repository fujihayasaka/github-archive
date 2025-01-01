package migrations

import "github.com/github/turboscan/ts/mysql/upgrades"

var _ = Transitions.Step(1000).Function("ts_tools", upgrades.Statements(
	// language=SQL
	`INSERT INTO ts_tools (created_at, updated_at, repository_id, guid, canonical_name, is_internal_guid)
SELECT min(tX.created_at), min(tX.updated_at), 0, min(tX.guid), tX.canonical_name, tX.is_internal_guid
FROM ts_tools AS tX FORCE INDEX(PRIMARY)
WHERE NOT EXISTS (SELECT 1 FROM ts_tools t0 WHERE t0.repository_id = 0 AND t0.canonical_name = tX.canonical_name)
AND tX.is_internal_guid = false
AND tX.repository_id <> 0
AND tX.id BETWEEN ? AND ?
GROUP BY tX.canonical_name`,
	// language=SQL
	`INSERT INTO ts_tools (created_at, updated_at, repository_id, guid, canonical_name, is_internal_guid)
SELECT created_at, updated_at, repository_id, CONCAT(LEFT(sha, 8), '-', MID(sha, 9, 4), '-', MID(sha, 13, 4), '-', MID(sha, 17, 4), '-', MID(sha, 21, 12)), canonical_name, is_internal_guid FROM (
	SELECT min(tX.created_at) AS created_at, min(tX.updated_at) AS updated_at, 0 AS repository_id, LOWER(SHA1(tX.canonical_name)) AS sha, tX.canonical_name, tX.is_internal_guid
	FROM ts_tools AS tX FORCE INDEX(PRIMARY)
	WHERE NOT EXISTS (SELECT 1 FROM ts_tools t0 WHERE t0.repository_id = 0 AND t0.canonical_name = tX.canonical_name)
	AND tX.is_internal_guid = true
	AND tX.repository_id <> 0
	AND tX.id BETWEEN ? AND ?
	GROUP BY tX.canonical_name
) AS found`,
	// language=SQL
	`INSERT INTO ts_tool_versions (created_at, updated_at, repository_id, tool_id, name, full_name, version, semantic_version)
SELECT min(tvX.created_at), min(tvX.updated_at), 0, t0.id, tvX.name, tvX.full_name, tvX.version, tvX.semantic_version
FROM ts_tool_versions AS tvX
INNER JOIN ts_tools AS tX FORCE INDEX(PRIMARY) ON tX.id = tvX.tool_id
INNER JOIN ts_tools AS t0 ON t0.repository_id = 0 AND tX.canonical_name = t0.canonical_name
WHERE NOT EXISTS (
	SELECT 1
	FROM ts_tool_versions tv0
	WHERE tv0.repository_id = 0
	AND tv0.tool_id = t0.id
	AND tv0.name <=> tvX.name
	AND tv0.full_name <=> tvX.full_name
	AND tv0.version <=> tvX.version
	AND tv0.semantic_version <=> tvX.semantic_version
)
AND tvX.repository_id != 0
AND tX.id BETWEEN ? AND ?
GROUP BY t0.id, tvX.name, tvX.full_name, tvX.version, tvX.semantic_version`,
))
