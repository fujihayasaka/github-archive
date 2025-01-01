DROP TABLE IF EXISTS `authentic_commits`;
CREATE TABLE `authentic_commits` (
  `network_id` bigint unsigned NOT NULL,
  `oid` binary(20) NOT NULL,
  `verified_at` datetime(6) DEFAULT NULL,
  `push_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`network_id`,`oid`),
  KEY `index_authentic_commits_on_push_id` (`push_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `event_action_ref_updates`;
CREATE TABLE `event_action_ref_updates` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `ref_name` varbinary(1024) NOT NULL,
  `before_oid` varchar(40) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `after_oid` varchar(40) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `policy_oid` varchar(40) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_event_action_ref_update` (`repository_id`,`ref_name`,`before_oid`,`after_oid`,`policy_oid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `event_action_repository_operations`;
CREATE TABLE `event_action_repository_operations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `operation` varchar(64) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `operation_value` varchar(64) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_event_action_repository_operation` (`repository_id`,`operation`,`operation_value`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `pushes`;
CREATE TABLE `pushes` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned DEFAULT NULL,
  `pusher_id` bigint unsigned DEFAULT NULL,
  `before` varchar(40) DEFAULT NULL,
  `after` varchar(40) DEFAULT NULL,
  `ref` varbinary(1024) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `pushed_at` datetime(6) NOT NULL,
  `push_type` tinyint unsigned NOT NULL,
  `network_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_pushes_on_repository_id_and_after` (`repository_id`,`after`),
  KEY `index_pushes_on_repository_id_and_ref_and_pushed_at` (`repository_id`,`ref`,`pushed_at`),
  KEY `index_pushes_on_repository_id_and_pusher_id_and_pushed_at` (`repository_id`,`pusher_id`,`pushed_at`),
  KEY `index_pushes_on_repository_id_and_pushed_at` (`repository_id`,`pushed_at`),
  KEY `index_pushes_on_repository_id_and_push_type_and_pushed_at` (`repository_id`,`push_type`,`pushed_at`),
  KEY `index_pushes_on_network_id` (`network_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
DROP TABLE IF EXISTS `ref_pushes`;
CREATE TABLE `ref_pushes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `pusher_id` bigint unsigned NOT NULL,
  `ref` varbinary(1024) NOT NULL,
  `after` varchar(40) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `pushed_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_ref_pushes_on_repository_id_and_pusher_id_and_ref` (`repository_id`,`pusher_id`,`ref`),
  UNIQUE KEY `index_ref_pushes_on_repository_id_and_ref_and_pusher_id` (`repository_id`,`ref`,`pusher_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `ref_updates`;
CREATE TABLE `ref_updates` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `push_id` bigint unsigned NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `before_oid` binary(20) NOT NULL,
  `after_oid` binary(20) NOT NULL,
  `ref` varbinary(1024) NOT NULL,
  `ref_update_type` tinyint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ref_updates_on_repository_id_and_after_oid` (`repository_id`,`after_oid`),
  KEY `index_ref_updates_on_repository_id_and_ref` (`repository_id`,`ref`),
  KEY `index_ref_updates_on_repository_id_and_ref_update_type` (`repository_id`,`ref_update_type`),
  KEY `index_ref_updates_on_push_id` (`push_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `ref_updates_id_ks_idx`;
CREATE TABLE `ref_updates_id_ks_idx` (
  `id` bigint unsigned NOT NULL,
  `keyspace_id` varbinary(128) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `repository_rule_runs`;
CREATE TABLE `repository_rule_runs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_rule_suite_id` bigint unsigned NOT NULL,
  `rule_type` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `rule_provider` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `result` tinyint unsigned NOT NULL DEFAULT '0',
  `repository_rule_configuration_id` bigint unsigned DEFAULT NULL,
  `message` varchar(1024) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `violations` json DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `evaluation_metadata` json DEFAULT NULL,
  `rule_provider_id` bigint unsigned DEFAULT NULL,
  `rule_history_id` bigint unsigned DEFAULT NULL,
  `repository_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_rule_runs_on_rule_suite_and_provider_and_repository_id` (`repository_rule_suite_id`,`rule_provider_id`,`rule_provider`,`repository_id`),
  KEY `index_rule_runs_on_provider_and_rule_suite_and_repository_id` (`rule_provider_id`,`rule_provider`,`repository_rule_suite_id`,`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `repository_rule_suite_source_results`;
CREATE TABLE `repository_rule_suite_source_results` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_rule_suite_id` bigint unsigned NOT NULL,
  `source_id` bigint unsigned DEFAULT NULL,
  `source_type` varchar(64) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `result` tinyint unsigned NOT NULL DEFAULT '0',
  `evaluate_result` tinyint unsigned NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_rule_suite_source_results_rule_suite_source_repo` (`repository_rule_suite_id`,`source_id`,`source_type`,`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `repository_rule_suites`;
CREATE TABLE `repository_rule_suites` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `ref_name` varbinary(1024) DEFAULT NULL,
  `before_oid` varchar(40) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `after_oid` varchar(40) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `policy_oid` varchar(40) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `actor_id` bigint unsigned DEFAULT NULL,
  `actor_type` varchar(64) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `result` tinyint unsigned NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `evaluation_metadata` json DEFAULT NULL,
  `owner_id` bigint unsigned DEFAULT NULL,
  `business_id` bigint unsigned DEFAULT NULL,
  `event_action_id` bigint unsigned DEFAULT NULL,
  `event_action_type` varchar(64) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_repository_rule_suites_ref_update` (`repository_id`,`ref_name`,`before_oid`,`after_oid`,`policy_oid`),
  KEY `index_repository_rule_suites_created_at` (`repository_id`,`created_at`),
  KEY `index_repository_rule_suites_on_created_at` (`created_at`),
  KEY `index_repository_rule_suites_owner_id_created_at` (`owner_id`,`created_at`),
  KEY `index_repository_rule_suites_owner_actor` (`owner_id`,`actor_id`,`actor_type`),
  KEY `index_repository_rule_suites_business_id_created_at` (`business_id`,`created_at`),
  KEY `index_repository_rule_suites_business_actor` (`business_id`,`actor_id`,`actor_type`),
  KEY `index_repository_rule_suites_event_action_id_and_type` (`event_action_id`,`event_action_type`),
  KEY `index_repository_rule_suites_repository_actor` (`repository_id`,`actor_id`,`actor_type`),
  KEY `index_repository_rule_suites_event_action_id_and_repo` (`event_action_id`,`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
