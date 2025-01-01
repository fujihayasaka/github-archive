package migrations

var _ = Transitions.Simple(`UPDATE ts_logical_alerts SET guid = UUID() WHERE guid is NULL LIMIT ?`)
