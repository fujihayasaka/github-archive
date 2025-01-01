ALTER TABLE `ts_timeline_events` ADD KEY `idx_timeline_events_on_repository_id_ref_logical_id` (`repository_id`,`ref`,`logical_alert_id`);
