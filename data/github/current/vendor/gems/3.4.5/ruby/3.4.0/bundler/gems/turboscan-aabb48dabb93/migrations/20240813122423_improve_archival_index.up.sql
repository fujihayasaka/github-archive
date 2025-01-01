ALTER TABLE `ts_analyses` DROP KEY `idx_analyses_on_archival_updated_at`, ADD KEY `idx_analyses_on_archival_updated_at` (`most_recent`,`archival_state`,`archival_failed`,`failed`,`updated_at`);
