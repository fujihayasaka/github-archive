ALTER TABLE `ts_timeline_events` ADD COLUMN `resolution_note` varchar(280) DEFAULT NULL;
ALTER TABLE `ts_logical_alerts` ADD COLUMN `resolution_note` varchar(280) DEFAULT NULL;
