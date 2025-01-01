ALTER TABLE `ts_rules` DROP COLUMN `properties`, MODIFY COLUMN `query_uri` varchar(1024) NOT NULL;
