ALTER TABLE `ts_process_errors` MODIFY COLUMN `repository_id` bigint(20) unsigned NOT NULL, MODIFY COLUMN `analysis_id` bigint(20) unsigned DEFAULT NULL;
ALTER TABLE `ts_timeline_events` MODIFY COLUMN `analysis_id` bigint(20) unsigned DEFAULT NULL;
