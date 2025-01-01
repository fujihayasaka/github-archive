ALTER TABLE `ts_analyses` ADD COLUMN `delivery_origin` tinyint(3) unsigned DEFAULT NULL, ADD COLUMN `workflow_path` varbinary(1024) DEFAULT NULL;
