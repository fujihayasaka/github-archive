package migrations

import "github.com/github/turboscan/ts/mysql/upgrades"

var _ = Transitions.Function("ts_physical_alerts", upgrades.Statements(
	// language=SQL
	`INSERT IGNORE INTO ts_code_flows_documents (repository_id, created_at, updated_at, document)
SELECT repository_id, MIN(created_at), MAX(updated_at), JSON_EXTRACT(JSON_OBJECTAGG(k, v), '$.*')
FROM (
	SELECT
		physical_alert_id,
		repository_id,
		created_at,
		updated_at,
		CONCAT_WS('', LPAD(code_flow_index, 10, '0'),  LPAD(thread_flow_index, 10, '0'), LPAD(step_index, 10, '0')) AS 'k',
		JSON_ARRAY(
			code_flow_index,
			file_path,
			message,
			end_column,
			end_line,
			start_column,
			start_line,
			step_index,
			thread_flow_index
		) AS 'v'
	FROM ts_thread_flow_locations
	WHERE ts_thread_flow_locations.physical_alert_id BETWEEN ? AND ?
) AS code_flows
GROUP BY physical_alert_id, repository_id`,
	// language=SQL
	`UPDATE ts_physical_alerts
INNER JOIN
(
	SELECT physical_alert_id, repository_id, UNHEX(SHA2(JSON_EXTRACT(JSON_OBJECTAGG(k, v), '$.*'), 256)) AS hash
	FROM (
		SELECT
			physical_alert_id,
			repository_id,
			created_at,
			updated_at,
			CONCAT_WS('', LPAD(code_flow_index, 10, '0'),  LPAD(thread_flow_index, 10, '0'), LPAD(step_index, 10, '0')) AS 'k',
			JSON_ARRAY(
				code_flow_index,
				file_path,
				message,
				end_column,
				end_line,
				start_column,
				start_line,
				step_index,
				thread_flow_index
			) AS 'v'
		FROM ts_thread_flow_locations
		WHERE ts_thread_flow_locations.physical_alert_id BETWEEN ? AND ?
	) AS code_flows_inner
	GROUP BY physical_alert_id, repository_id
) AS code_flows
ON ts_physical_alerts.id = code_flows.physical_alert_id
AND ts_physical_alerts.repository_id = code_flows.repository_id
INNER JOIN ts_code_flows_documents
ON ts_physical_alerts.repository_id = ts_code_flows_documents.repository_id
AND ts_code_flows_documents.hash = code_flows.hash
AND ts_physical_alerts.code_flows_document_id IS NULL
SET code_flows_document_id = ts_code_flows_documents.id`,
))
