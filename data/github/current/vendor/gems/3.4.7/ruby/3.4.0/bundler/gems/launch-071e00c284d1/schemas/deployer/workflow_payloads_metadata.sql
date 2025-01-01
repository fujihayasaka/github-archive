CREATE TABLE `workflow_payloads_metadata` (
  `workflow_build_id` bigint unsigned NOT NULL COMMENT 'The workflow build database ID',
  `created_at` datetime(6) NOT NULL,
  `storage_account_id` tinyint unsigned NOT NULL COMMENT 'The storage account where the payload is stored',
  `version` tinyint unsigned NOT NULL COMMENT 'The version of the payload, used to track changes like the blob path naming convention used',
  PRIMARY KEY (`workflow_build_id`),
  KEY `by_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
