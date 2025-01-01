package migrations

var _ = Transitions.Step(1000).Batched(
	"ts_codeql_configs",
	`UPDATE ts_codeql_configs FORCE INDEX(PRIMARY)
SET
	languages = COALESCE(JSON_KEYS((SELECT JSON_OBJECTAGG((CASE lang
WHEN 'javascript' THEN 'javascript-typescript'
WHEN 'typescript' THEN  'javascript-typescript'
WHEN 'java' THEN 'java-kotlin'
WHEN 'kotlin' THEN 'java-kotlin'
WHEN 'c' THEN 'c-cpp'
WHEN 'cpp' THEN 'c-cpp'
ELSE lang
END), true) FROM json_table(languages, '$[*]' columns (lang TEXT PATH '$')) AS langs)), '[]'),
    initial_languages = COALESCE(JSON_KEYS((SELECT JSON_OBJECTAGG((CASE lang
WHEN 'javascript' THEN 'javascript-typescript'
WHEN 'typescript' THEN  'javascript-typescript'
WHEN 'java' THEN 'java-kotlin'
WHEN 'kotlin' THEN 'java-kotlin'
WHEN 'c' THEN 'c-cpp'
WHEN 'cpp' THEN 'c-cpp'
ELSE lang
END), true) FROM json_table(initial_languages, '$[*]' columns (lang TEXT PATH '$')) AS langs)), '[]')
WHERE id BETWEEN ? AND ? AND JSON_OVERLAPS(languages, '["javascript", "typescript", "java", "kotlin", "c", "cpp"]')`,
)
