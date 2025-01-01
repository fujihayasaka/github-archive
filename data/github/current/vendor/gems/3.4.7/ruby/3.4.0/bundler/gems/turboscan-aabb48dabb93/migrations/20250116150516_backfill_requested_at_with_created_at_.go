package migrations

var _ = Transitions.Batched("ts_suggested_fix_alerts", `
UPDATE ts_suggested_fix_alerts FORCE INDEX(PRIMARY)
SET requested_at = created_at
WHERE requested_at is NULL
AND id BETWEEN ? AND ?`)
