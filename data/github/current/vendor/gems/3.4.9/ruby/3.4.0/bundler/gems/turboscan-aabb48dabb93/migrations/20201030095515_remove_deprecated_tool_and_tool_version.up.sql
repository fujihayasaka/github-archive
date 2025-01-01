ALTER TABLE `ts_rules` DROP COLUMN `tool`, DROP KEY `index_repo_tool_sarif`;
ALTER TABLE `ts_analyses` DROP COLUMN `tool`, DROP COLUMN `tool_version`, DROP KEY `idx_analyses_on_repo_id_most_recent_ref_tool`;
ALTER TABLE `ts_timeline_events` DROP COLUMN `tool_version`;
