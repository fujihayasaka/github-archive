ALTER TABLE `ts_physical_alerts` ADD COLUMN `snippet_id` bigint(20) unsigned DEFAULT NULL;
CREATE TABLE `ts_snippets` (
    `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
    `created_at` datetime(6) NOT NULL,
    `updated_at` datetime(6) NOT NULL,
    `repository_id` bigint(20) unsigned NOT NULL,
    `start_line` int(10) unsigned NOT NULL,
    `end_line` int(10) unsigned NOT NULL,
    `start_column` int(10) unsigned DEFAULT NULL,
    `end_column` int(10) unsigned DEFAULT NULL,
    `text` text NOT NULL,
    `hash` binary(32) NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `idx_snippets_uniq_repo_hash` (`repository_id`,`hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
