package migrations

var _ = Transitions.Simple(`UPDATE ts_rules SET query_uri = COALESCE(JSON_EXTRACT(properties, '$.queryURI'), "") WHERE query_uri is NULL LIMIT ?`)
