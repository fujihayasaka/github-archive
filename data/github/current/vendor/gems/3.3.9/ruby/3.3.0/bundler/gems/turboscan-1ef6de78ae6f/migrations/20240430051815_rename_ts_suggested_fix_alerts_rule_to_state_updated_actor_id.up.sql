ALTER TABLE `ts_suggested_fix_alerts` DROP COLUMN `rule`, ADD COLUMN `rule_sarif_identifier` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL;
