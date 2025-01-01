ALTER TABLE `ts_analysis_rules` MODIFY COLUMN `count` int(10) unsigned NOT NULL;
ALTER TABLE `ts_rules` MODIFY COLUMN `hash` binary(32) NOT NULL;
