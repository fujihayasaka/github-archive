ALTER TABLE `ts_codeql_runs` DROP COLUMN `timeout_at`;
ALTER TABLE `ts_codeql_configs` DROP COLUMN `global_repository_id`, DROP COLUMN `global_actor_id`, DROP COLUMN `actor_login`;
