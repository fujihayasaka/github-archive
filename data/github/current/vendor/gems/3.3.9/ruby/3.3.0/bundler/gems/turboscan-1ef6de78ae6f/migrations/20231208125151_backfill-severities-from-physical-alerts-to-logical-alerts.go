package migrations

var _ = Transitions.Step(10).Batched("ts_logical_alerts", `UPDATE ts_logical_alerts FORCE INDEX(PRIMARY)
SET severity_level = ( select severity_level from ts_physical_alerts where logical_alert_id = ts_logical_alerts.id and repository_id = ts_logical_alerts.repository_id order by created_at desc limit 1 ), 
security_severity = ( select security_severity from ts_physical_alerts where logical_alert_id = ts_logical_alerts.id and repository_id = ts_logical_alerts.repository_id order by created_at desc limit 1 ) 
WHERE ts_logical_alerts.id BETWEEN ? AND ?`)
