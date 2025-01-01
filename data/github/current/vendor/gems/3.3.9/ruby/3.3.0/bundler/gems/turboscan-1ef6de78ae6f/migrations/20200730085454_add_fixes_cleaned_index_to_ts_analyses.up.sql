ALTER TABLE `ts_analyses` ADD KEY `idx_analyses_on_fixes_cleaned` (`fixes_cleaned`,`most_recent`,`processing_completed_at`);
