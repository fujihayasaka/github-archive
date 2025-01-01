ALTER TABLE `ts_tool_versions` DROP COLUMN `repository_id`;
ALTER TABLE `ts_tools` DROP COLUMN `repository_id`, DROP KEY `index_repository_guid`, DROP KEY `index_repository_canonical_name`;
