package migrations

var _ = Transitions.Step(100).Simple(`UPDATE ts_analyses
SET source_repository_id = repository_id
WHERE source_repository_id = 0
LIMIT ?`)
