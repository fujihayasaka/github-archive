ALTER TABLE `ts_analysis_messages` MODIFY COLUMN `analysis_id` bigint(20) unsigned DEFAULT NULL, ADD COLUMN `delivery_id` bigint(20) unsigned DEFAULT NULL;
