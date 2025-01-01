package migrations

var _ = Transitions.Simple(`UPDATE ts_analyses
SET sarif_id = SUBSTR(sarif_url, -36-LENGTH('.sarif'), 36)
WHERE sarif_id is NULL
AND sarif_url LIKE '%.sarif'
LIMIT ?`)
