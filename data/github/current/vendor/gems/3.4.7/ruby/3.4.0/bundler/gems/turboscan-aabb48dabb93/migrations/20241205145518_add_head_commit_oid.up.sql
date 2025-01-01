ALTER TABLE `ts_analyses` ADD COLUMN `head_commit_oid` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL, ADD KEY `idx_analyses_on_repo_id_head_commit_oid` (`repository_id`,`head_commit_oid`);
ALTER TABLE `ts_deliveries` ADD COLUMN `head_commit_oid` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL;
