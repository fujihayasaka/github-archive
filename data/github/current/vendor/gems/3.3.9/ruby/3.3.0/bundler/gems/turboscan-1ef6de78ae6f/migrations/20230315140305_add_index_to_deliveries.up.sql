ALTER TABLE `ts_deliveries` ADD KEY `idx_deliveries_on_repo_id_ref_key` (`repository_id`,`ref`,`analysis_key`);
