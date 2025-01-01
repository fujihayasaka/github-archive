package migrations

var _ = Transitions.Simple(`UPDATE ts_physical_alerts SET end_line = start_line WHERE start_line > end_line LIMIT ?`)
