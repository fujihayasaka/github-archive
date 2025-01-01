ALTER TABLE `ts_analyses` ADD KEY `idx_analyses_on_archival_state_created_at` (`most_recent`,`archival_state`,`created_at`);
