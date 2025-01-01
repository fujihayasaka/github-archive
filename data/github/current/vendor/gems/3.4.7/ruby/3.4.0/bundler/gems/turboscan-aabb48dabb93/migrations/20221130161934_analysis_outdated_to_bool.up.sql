ALTER TABLE `ts_analyses` DROP COLUMN `outdated_at`, ADD COLUMN `is_outdated` tinyint(1) NOT NULL DEFAULT '0';
