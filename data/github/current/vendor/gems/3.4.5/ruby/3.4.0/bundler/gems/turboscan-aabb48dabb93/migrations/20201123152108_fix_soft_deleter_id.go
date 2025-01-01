package migrations

var _ = Transitions.Simple(`UPDATE ts_logical_alerts SET soft_deleter_id = NULL WHERE soft_deleted_at IS NULL AND soft_deleter_id IS NOT NULL LIMIT ?`)
