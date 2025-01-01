package migrations

var _ = Transitions.Step(100).Simple(`
UPDATE ts_timeline_events as te
SET te.tool_version_id = (
 SELECT a.tool_version_id
 FROM ts_analyses a
 WHERE a.id = te.analysis_id
)
WHERE te.tool_version_id is NULL
AND te.analysis_id != 0
AND te.analysis_id is NOT NULL
AND te.tool_version is NOT NULL
AND te.tool_version != ""
AND te.id >= 20000000
LIMIT ?
`)
