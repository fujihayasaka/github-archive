package migrations

var _ = Transitions.Step(100).Batched("ts_logical_alerts", `
    UPDATE ts_logical_alerts FORCE INDEX(PRIMARY)
    JOIN LATERAL (SELECT
        ts_physical_alerts.logical_alert_id,
        ts_physical_alerts.repository_id,
        ts_physical_alerts.file_path,
        ts_physical_alerts.start_line,
        ts_physical_alerts.end_line,
        ts_physical_alerts.start_column,
        ts_physical_alerts.end_column,
        ts_physical_alerts.message,
        ts_physical_alerts.message_markdown,
        ts_physical_alerts.file_classification,
        ts_physical_alerts.severity_level,
        ts_physical_alerts.security_severity,
        ts_analyses.configuration_id
    FROM ts_physical_alerts FORCE INDEX (idx_physical_alerts_on_repo_id_logical_alert_id)
    INNER JOIN ts_repositories ON ts_repositories.repository_id = ts_physical_alerts.repository_id 
    INNER JOIN ts_analyses ON ts_analyses.id = ts_physical_alerts.analysis_id AND ts_analyses.repository_id = ts_physical_alerts.repository_id AND ts_repositories.default_ref = ts_analyses.ref_bytes AND ts_analyses.most_recent=1
    WHERE ts_physical_alerts.logical_alert_id = ts_logical_alerts.id AND ts_physical_alerts.repository_id = ts_logical_alerts.repository_id
    ORDER BY ts_physical_alerts.id DESC
    LIMIT 1) pa
    SET ts_logical_alerts.file_path = pa.file_path,
        ts_logical_alerts.start_line = pa.start_line,
        ts_logical_alerts.end_line = pa.end_line,
        ts_logical_alerts.start_column = pa.start_column,
        ts_logical_alerts.end_column = pa.end_column,
        ts_logical_alerts.message = pa.message,
        ts_logical_alerts.message_markdown = pa.message_markdown,
        ts_logical_alerts.file_classification = pa.file_classification,
        ts_logical_alerts.severity_level = pa.severity_level,
        ts_logical_alerts.security_severity = pa.security_severity,
        ts_logical_alerts.default_configuration_id = pa.configuration_id
    WHERE ts_logical_alerts.id BETWEEN ? AND ?
`)
