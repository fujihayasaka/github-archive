package migrations

var _ = Transitions.Step(100).Simple(`UPDATE ts_analyses SET build_started_at = started_at WHERE build_started_at IS NULL AND started_at IS NOT NULL LIMIT ?`)
