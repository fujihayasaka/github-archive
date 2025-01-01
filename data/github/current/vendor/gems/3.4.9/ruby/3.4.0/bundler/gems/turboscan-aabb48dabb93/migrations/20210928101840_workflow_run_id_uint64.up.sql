ALTER TABLE `ts_timeline_events` MODIFY COLUMN `workflow_run_id` bigint(20) unsigned DEFAULT NULL;
ALTER TABLE `ts_analyses` MODIFY COLUMN `workflow_run_id` bigint(20) unsigned DEFAULT NULL;
