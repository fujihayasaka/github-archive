ALTER TABLE `ts_suggested_fixes` ADD COLUMN `invalid` tinyint(1) NOT NULL DEFAULT '0', ADD COLUMN `dependency_metadata` json DEFAULT NULL, ADD COLUMN `problems` json DEFAULT NULL;
