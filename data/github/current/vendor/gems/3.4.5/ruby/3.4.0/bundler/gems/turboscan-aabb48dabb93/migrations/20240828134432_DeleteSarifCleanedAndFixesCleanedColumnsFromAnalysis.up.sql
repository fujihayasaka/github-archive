ALTER TABLE `ts_analyses` DROP COLUMN `sarif_cleaned`, DROP COLUMN `fixes_cleaned`, DROP KEY `idx_analyses_on_sarif_cleaned_updated_at`, DROP KEY `idx_analyses_on_fixes_cleaned_updated_at`;
