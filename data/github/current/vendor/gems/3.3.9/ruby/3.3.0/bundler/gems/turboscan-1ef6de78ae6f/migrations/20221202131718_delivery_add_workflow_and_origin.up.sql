ALTER TABLE `ts_deliveries` ADD COLUMN `origin` tinyint(3) unsigned DEFAULT NULL, ADD COLUMN `workflow_path` varbinary(1024) DEFAULT NULL;
