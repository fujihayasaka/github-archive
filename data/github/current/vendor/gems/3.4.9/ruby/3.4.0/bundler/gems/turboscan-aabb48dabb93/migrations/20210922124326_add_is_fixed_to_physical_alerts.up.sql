ALTER TABLE `ts_physical_alerts` ADD COLUMN `is_fixed` tinyint(1) GENERATED ALWAYS AS ((`last_seen_analysis_id` is not null)) VIRTUAL;
