package migrations

var _ = Transitions.Simple(`UPDATE ts_analyses
SET sarif_id = ""
WHERE sarif_id is NULL
AND sarif_url = ""
LIMIT ?`)
