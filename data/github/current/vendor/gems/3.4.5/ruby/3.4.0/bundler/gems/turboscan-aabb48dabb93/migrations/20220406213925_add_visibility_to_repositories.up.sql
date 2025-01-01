ALTER TABLE `ts_repositories` ADD COLUMN `visibility` enum('public','private','internal') DEFAULT NULL;
