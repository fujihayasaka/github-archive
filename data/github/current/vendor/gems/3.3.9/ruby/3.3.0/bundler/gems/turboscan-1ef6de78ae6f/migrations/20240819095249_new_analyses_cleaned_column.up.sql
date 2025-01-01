ALTER TABLE `ts_analyses` ADD COLUMN `cleaned` tinyint(1) DEFAULT '0', ADD KEY `idx_analyses_on_cleaned_updated_at` (`cleaned`,`most_recent`,`updated_at`);
