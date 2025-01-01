ALTER TABLE `ts_analyses` ADD KEY `idx_analyses_on_repo_id_latest_for_category` (`repository_id`,`soft_deleted_at`,`is_outdated`,`most_recent`,`tool_id`,`analysis_category`(512),`id`);
