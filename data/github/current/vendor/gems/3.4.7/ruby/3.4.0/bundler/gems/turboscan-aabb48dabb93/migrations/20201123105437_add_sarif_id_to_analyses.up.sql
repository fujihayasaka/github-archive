ALTER TABLE `ts_analyses` ADD COLUMN `sarif_id` varchar(255) DEFAULT NULL, ADD KEY `idx_analyses_on_repo_id_sarif_id` (`repository_id`,`sarif_id`);
