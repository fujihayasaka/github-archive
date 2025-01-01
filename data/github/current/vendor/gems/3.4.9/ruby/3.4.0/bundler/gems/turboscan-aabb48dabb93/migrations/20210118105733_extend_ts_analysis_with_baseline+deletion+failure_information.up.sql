ALTER TABLE `ts_analyses` ADD COLUMN `soft_deleted_at` datetime(6) DEFAULT NULL, ADD COLUMN `failed` tinyint(1) NOT NULL DEFAULT '0', ADD COLUMN `baseline_id` bigint(20) unsigned DEFAULT NULL;
