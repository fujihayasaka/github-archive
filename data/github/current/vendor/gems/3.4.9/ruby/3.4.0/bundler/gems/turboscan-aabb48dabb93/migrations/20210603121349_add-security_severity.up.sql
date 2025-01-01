ALTER TABLE `ts_physical_alerts` ADD COLUMN `security_severity` double DEFAULT NULL;
ALTER TABLE `ts_rules` ADD COLUMN `security_severity` double DEFAULT NULL;
