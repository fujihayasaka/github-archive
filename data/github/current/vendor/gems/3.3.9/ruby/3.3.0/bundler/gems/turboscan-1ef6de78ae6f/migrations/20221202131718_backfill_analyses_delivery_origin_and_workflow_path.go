package migrations

var _ = Transitions.Batched("ts_analyses", `
UPDATE ts_analyses FORCE INDEX(PRIMARY)
SET delivery_origin = CASE
						WHEN analysis_key LIKE ".github/workflows%" THEN 0 -- YML
						WHEN analysis_key LIKE "dynamic/github-code-scanning/codeql%" THEN 1 -- MANAGED
						WHEN analysis_key LIKE "dynamic/%" THEN 2 -- DYNAMIC
						ELSE 3 -- API
					  END,
	workflow_path = IF(analysis_key LIKE ".github/workflows%", SUBSTRING_INDEX(analysis_key, ':', 1), NULL)
WHERE analysis_key IS NOT NULL AND id BETWEEN ? AND ?`)
