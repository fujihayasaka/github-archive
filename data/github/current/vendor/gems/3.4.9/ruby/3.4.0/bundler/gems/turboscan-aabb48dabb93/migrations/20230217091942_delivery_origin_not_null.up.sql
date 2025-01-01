ALTER TABLE `ts_analyses` MODIFY COLUMN `delivery_origin` tinyint unsigned NOT NULL;
ALTER TABLE `ts_deliveries` MODIFY COLUMN `origin` tinyint unsigned NOT NULL;
