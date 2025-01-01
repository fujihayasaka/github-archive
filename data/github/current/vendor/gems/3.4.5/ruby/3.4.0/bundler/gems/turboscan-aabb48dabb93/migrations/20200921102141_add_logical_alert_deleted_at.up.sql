ALTER TABLE `ts_logical_alerts` ADD COLUMN `soft_deleted_at` datetime(6) DEFAULT NULL;
ALTER TABLE `ts_logical_alerts` ADD COLUMN `soft_deleter_id` int(10) unsigned DEFAULT NULL;
ALTER TABLE `ts_logical_alerts` ADD KEY `index_logical_alerts_on_repository_id_deleted` (`repository_id`, `soft_deleted_at`);
