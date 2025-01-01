package migrations

var _ = Transitions.Batched("ts_tool_statuses", `
INSERT IGNORE INTO ts_analysis_extracted_files (repository_id, analysis_id, created_at, updated_at, files_extracted, files_not_extracted)
SELECT repository_id, analysis_id, created_at, updated_at, files_extracted, files_not_extracted
FROM ts_tool_statuses FORCE INDEX(PRIMARY)
WHERE id BETWEEN ? AND ?`)
