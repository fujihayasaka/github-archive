package migrations

var _ = Transitions.Batched("ts_analyses", `
UPDATE ts_analyses AS upd
INNER JOIN (
	SELECT id,
		CAST(CONCAT('/', GROUP_CONCAT(CONCAT(name, ':', value) SEPARATOR '/')) AS CHAR(1024)) AS env_category
	FROM (
		SELECT a.id,
			JSON_UNQUOTE(JSON_EXTRACT(JSON_KEYS(a.environment), CONCAT('$[', t.n, ']'))) AS name,
			JSON_UNQUOTE(JSON_EXTRACT(a.environment, CONCAT('$.', JSON_EXTRACT(JSON_KEYS(a.environment), CONCAT('$[', t.n, ']'))))) AS value
		FROM ts_analyses a
		INNER JOIN (SELECT 0 AS n UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12 UNION SELECT 13 UNION SELECT 14 UNION SELECT 15 UNION SELECT 16 UNION SELECT 17 UNION SELECT 18 UNION SELECT 19) t
		WHERE a.id IN (SELECT id FROM ts_analyses FORCE INDEX(PRIMARY) WHERE id BETWEEN ? AND ? AND analysis_category IS NULL AND analysis_key != '(default)' AND JSON_LENGTH(environment) != 0)
		HAVING name IS NOT NULL
		ORDER BY a.id, name
	) x
	GROUP BY id
) y ON upd.id = y.id
SET upd.analysis_category = CONCAT(upd.analysis_key, COALESCE(y.env_category, ''))
`)
