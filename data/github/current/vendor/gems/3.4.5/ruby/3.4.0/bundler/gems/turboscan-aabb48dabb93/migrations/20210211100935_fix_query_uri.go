package migrations

var _ = Transitions.Simple(`UPDATE ts_rules
SET query_uri = SUBSTR(query_uri, 2, LENGTH(query_uri)-2 )
WHERE query_uri REGEXP '^".*"$'
LIMIT ?`)
