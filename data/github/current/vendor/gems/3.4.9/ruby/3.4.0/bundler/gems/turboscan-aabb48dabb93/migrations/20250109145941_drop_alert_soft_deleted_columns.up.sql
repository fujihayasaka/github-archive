ALTER TABLE `ts_logical_alerts` DROP COLUMN `soft_deleted_at`, DROP COLUMN `soft_deleter_id`, DROP KEY `index_logical_alerts_on_repository_id_deleted`;
