ALTER TABLE `ts_deliveries` ADD COLUMN `processing_lock` varchar(36) COLLATE utf8mb4_general_ci DEFAULT NULL, ADD KEY `idx_deliveries_on_repo_id_complete` (`repository_id`,`complete`);
