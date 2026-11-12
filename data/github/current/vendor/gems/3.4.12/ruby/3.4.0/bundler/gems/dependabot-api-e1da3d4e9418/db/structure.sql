
/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
DROP TABLE IF EXISTS `account_transitions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `account_transitions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `to_state` varchar(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `metadata` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `sort_key` int NOT NULL,
  `account_id` bigint NOT NULL,
  `most_recent` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `installation_id` bigint NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_account_transitions_parent_sort` (`account_id`,`sort_key`),
  UNIQUE KEY `unique_installation_id_across_accounts` (`installation_id`,`account_id`,`sort_key`),
  UNIQUE KEY `index_account_transitions_parent_most_recent` (`account_id`,`most_recent`),
  KEY `index_account_transitions_on_most_recent_and_to_state` (`most_recent`,`to_state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `accounts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `accounts` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `github_id` bigint NOT NULL,
  `github_login` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `account_type` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `create_merge_commits` tinyint(1) NOT NULL,
  `initial_update_runs_pr_limit` int DEFAULT NULL,
  `merge_on_approval` tinyint(1) NOT NULL,
  `unlimited_private_repos_override` tinyint(1) NOT NULL,
  `allow_automerging` tinyint(1) NOT NULL,
  `event_source` int NOT NULL DEFAULT '0',
  `tenant_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_accounts_on_github_id_and_account_type` (`github_id`,`account_type`),
  KEY `index_accounts_on_github_login` (`github_login`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `active_storage_attachments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `active_storage_attachments` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `record_type` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `record_id` bigint NOT NULL,
  `blob_id` bigint NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_active_storage_attachments_uniqueness` (`record_type`,`record_id`,`name`,`blob_id`),
  KEY `index_active_storage_attachments_on_blob_id` (`blob_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `active_storage_blobs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `active_storage_blobs` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `key` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `filename` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `content_type` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `metadata` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `byte_size` bigint NOT NULL,
  `checksum` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `service_name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_active_storage_blobs_on_key` (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `active_storage_variant_records`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `active_storage_variant_records` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `blob_id` bigint NOT NULL,
  `variation_digest` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_active_storage_variant_records_uniqueness` (`blob_id`,`variation_digest`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `ar_internal_metadata`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ar_internal_metadata` (
  `key` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL,
  `value` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `autofix_suggestion_jobs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `autofix_suggestion_jobs` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `pull_request_id` bigint NOT NULL,
  `target_sha` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `rule_sarif_identifier` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `sarif_content` json DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `check_run_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_autofix_suggestion_jobs_on_pull_request_and_sha` (`pull_request_id`,`target_sha`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `config_file_errors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `config_file_errors` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `repo_id` bigint NOT NULL,
  `error_details` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `error_type` varchar(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_rails_0d1aa35a98` (`repo_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `dependency_groups`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `dependency_groups` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `update_config_id` bigint DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `rules` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `deleted_at` datetime(6) DEFAULT NULL,
  `applies_to` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `sort_order` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dependency_groups_on_update_config_id_and_deleted_at` (`update_config_id`,`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `flipper_features`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `flipper_features` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `key` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_flipper_features_on_key` (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `flipper_gates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `flipper_gates` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `feature_key` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `key` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `value` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_flipper_gates_on_feature_key_and_key_and_value` (`feature_key`,`key`,`value`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `ignore_conditions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ignore_conditions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `update_config_id` bigint NOT NULL,
  `dependency_name` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `version_requirement` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `from_config_file` tinyint(1) NOT NULL DEFAULT '0',
  `issue_comment_id` bigint DEFAULT NULL,
  `update_types` json DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_ignored_updates_on_details_to_ignore` (`update_config_id`,`dependency_name`,`version_requirement`),
  KEY `index_ignore_conditions_on_config_and_file` (`update_config_id`,`from_config_file`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `issue_transitions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `issue_transitions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `to_state` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `metadata` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `sort_key` int NOT NULL,
  `issue_id` bigint NOT NULL,
  `most_recent` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_issue_transitions_parent_sort` (`issue_id`,`sort_key`),
  UNIQUE KEY `index_issue_transitions_parent_most_recent` (`issue_id`,`most_recent`),
  KEY `index_issue_transitions_on_most_recent_and_to_state` (`most_recent`,`to_state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `issues`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `issues` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `github_number` bigint NOT NULL,
  `update_job_id` bigint DEFAULT NULL,
  `repo_id` bigint NOT NULL,
  `issue_type` varchar(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `issue_detail` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `update_config_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_issues_on_repo_id_and_github_number` (`repo_id`,`github_number`),
  KEY `index_issues_on_update_job_id` (`update_job_id`),
  KEY `index_issues_on_update_config_id` (`update_config_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `multi_ecosystem_configs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `multi_ecosystem_configs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `pending_pull_request_transitions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `pending_pull_request_transitions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `to_state` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `metadata` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `sort_key` int NOT NULL,
  `pending_pull_request_id` bigint NOT NULL,
  `most_recent` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_pending_pull_request_transitions_parent_sort` (`pending_pull_request_id`,`sort_key`),
  UNIQUE KEY `index_pending_pull_request_transitions_parent_most_recent` (`pending_pull_request_id`,`most_recent`),
  KEY `index_pending_prs_on_most_recent_and_to_state` (`most_recent`,`to_state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `pending_pull_request_updates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `pending_pull_request_updates` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `pull_request_id` bigint NOT NULL,
  `updated_base_commit_sha` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `pending_pull_requests`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `pending_pull_requests` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `update_job_id` bigint NOT NULL,
  `updated_dependency_details` mediumtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `sort_key` int NOT NULL,
  `grouped_update` tinyint(1) DEFAULT '0',
  `dependency_group_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_pending_pull_requests_parent_sort` (`update_job_id`,`sort_key`),
  KEY `index_pending_pull_requests_on_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `pull_request_transitions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `pull_request_transitions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `to_state` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `metadata` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `sort_key` int NOT NULL,
  `pull_request_id` bigint NOT NULL,
  `most_recent` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `update_job_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_pull_request_transitions_parent_sort` (`pull_request_id`,`sort_key`),
  UNIQUE KEY `index_pull_request_transitions_parent_most_recent` (`pull_request_id`,`most_recent`),
  KEY `index_pull_request_transitions_on_update_job_id` (`update_job_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `pull_requests`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `pull_requests` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `github_number` bigint DEFAULT NULL,
  `update_job_id` bigint NOT NULL,
  `repo_id` bigint NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `head_commit_sha` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `head_commit_ci_status` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `base_commit_sha` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `base_commit_ci_status` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `multiple_dependencies` tinyint(1) NOT NULL,
  `merge_requested` tinyint(1) NOT NULL DEFAULT '0',
  `dependabot_commit_sha` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `dependabot_commit_ci_status` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `squash_requested` tinyint(1) NOT NULL DEFAULT '0',
  `automerge_block_requested` tinyint(1) NOT NULL DEFAULT '0',
  `update_config_id` bigint NOT NULL,
  `grouped_update` tinyint(1) DEFAULT '0',
  `dependency_group_id` bigint DEFAULT NULL,
  `affected_directories` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_pull_requests_on_repo_id_and_github_number` (`repo_id`,`github_number`),
  KEY `index_pull_requests_on_head_commit_sha` (`head_commit_sha`),
  KEY `index_pull_requests_on_update_job_id` (`update_job_id`),
  KEY `index_existing_pull_check` (`update_config_id`,`grouped_update`,`multiple_dependencies`),
  KEY `index_pull_requests_on_dependency_group_id` (`dependency_group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `registries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `registries` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `registry_type` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `credentials` json NOT NULL,
  `source_type` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `source_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_source_name` (`source_type`,`source_id`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `repos`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `repos` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `account_id` bigint NOT NULL,
  `github_id` bigint NOT NULL,
  `name` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `fork` tinyint(1) DEFAULT NULL,
  `private` tinyint(1) NOT NULL,
  `primary_language` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `default_branch` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `unreliable_test_suite` tinyint(1) NOT NULL,
  `has_ci` tinyint(1) NOT NULL,
  `config_file_path` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `will_pause_at` datetime(6) DEFAULT NULL,
  `paused_at` datetime(6) DEFAULT NULL,
  `security_updates_enabled` tinyint(1) DEFAULT NULL,
  `automerge_enabled` tinyint(1) DEFAULT NULL,
  `days_before_automerge` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_repos_on_github_id` (`github_id`),
  KEY `fk_rails_24ca51d8f1` (`account_id`),
  KEY `index_repos_on_private` (`private`),
  KEY `index_repos_on_will_pause_at_and_paused_at` (`will_pause_at`,`paused_at`),
  KEY `index_repos_on_security_updates_enabled_and_paused` (`paused_at`,`security_updates_enabled`,`will_pause_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `repository_accesses`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `repository_accesses` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `account_id` bigint NOT NULL,
  `github_id` bigint NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_repository_accesses_on_github_id` (`github_id`),
  KEY `index_repository_accesses_on_account_id` (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `schema_migrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `schema_migrations` (
  `version` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `suggested_fix_files`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `suggested_fix_files` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `suggested_fix_id` bigint NOT NULL,
  `file_path` varchar(4096) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `file_path_hash` varbinary(32) NOT NULL,
  `file_checksum` varbinary(20) NOT NULL,
  `diff_content` blob NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_suggested_fix_files_on_suggested_fix_id` (`suggested_fix_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `suggested_fixes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `suggested_fixes` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `autofix_suggestion_job_id` bigint NOT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `ai_version` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `ai_model` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `dependency_metadata` json DEFAULT NULL,
  `review_status` int DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_suggested_fixes_on_autofix_suggestion_job_id` (`autofix_suggestion_job_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `tenants`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `tenants` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `slug` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `github_id` int NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `shortcode` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_tenants_on_github_id` (`github_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `update_config_cooldowns`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `update_config_cooldowns` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `update_config_id` bigint unsigned DEFAULT NULL,
  `default_days` int NOT NULL DEFAULT '0',
  `semver_major_days` int NOT NULL DEFAULT '0',
  `semver_minor_days` int NOT NULL DEFAULT '0',
  `semver_patch_days` int NOT NULL DEFAULT '0',
  `include` json DEFAULT NULL,
  `exclude` json DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_update_config_cooldowns_on_config_id` (`update_config_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `update_config_registries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `update_config_registries` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `update_config_id` bigint NOT NULL,
  `registry_name` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_update_config_registries_on_config_id_and_name` (`update_config_id`,`registry_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `update_config_transitions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `update_config_transitions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `to_state` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `metadata` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `sort_key` int NOT NULL,
  `update_config_id` bigint NOT NULL,
  `most_recent` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_update_config_transitions_parent_sort` (`update_config_id`,`sort_key`),
  UNIQUE KEY `index_update_config_transitions_parent_most_recent` (`update_config_id`,`most_recent`),
  KEY `index_update_config_transitions_on_most_recent_and_to_state` (`most_recent`,`to_state`),
  KEY `index_per_config_most_recent_and_state` (`update_config_id`,`most_recent`,`to_state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `update_configs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `update_configs` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `repo_id` bigint NOT NULL,
  `package_manager` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `directory` varbinary(1024) DEFAULT NULL,
  `update_schedule` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `target_branch` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `custom_labels` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `lockfile_only` tinyint(1) NOT NULL,
  `default_reviewers` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `default_assignees` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `default_milestone` bigint DEFAULT NULL,
  `requirements_update_strategy` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `monitored_files` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `default_labels` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `allowed_updates` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `required_instance_size` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `commit_message_prefix` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `commit_message_include_scope` tinyint(1) DEFAULT NULL,
  `commit_message_prefix_development` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `update_schedule_time_of_day` time NOT NULL,
  `update_schedule_day_of_week` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `update_schedule_timezone` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `pull_request_branch_name_separator` varchar(1) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `open_pull_requests_limit` int NOT NULL,
  `rebase_strategy` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `last_scheduled_job_id` bigint DEFAULT NULL,
  `vendor` tinyint(1) NOT NULL DEFAULT '0',
  `all_registries` tinyint(1) DEFAULT '0',
  `insecure_external_code_execution` enum('allow','deny') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `directories` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `enable_beta_ecosystems` tinyint(1) NOT NULL DEFAULT '0',
  `update_schedule_cron_expression` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `multi_ecosystem_config_id` bigint unsigned DEFAULT NULL,
  `exclude_paths` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  PRIMARY KEY (`id`),
  KEY `index_update_configs_on_package_manager` (`package_manager`),
  KEY `index_update_configs_on_repo_id` (`repo_id`),
  KEY `index_update_configs_on_update_schedule` (`update_schedule`),
  KEY `index_update_configs_on_multi_ecosystem_config_id` (`multi_ecosystem_config_id`),
  KEY `index_update_configs_on_update_schedule_and_repo_id` (`update_schedule`,`repo_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `update_job_errors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `update_job_errors` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `update_job_id` bigint NOT NULL,
  `error_details` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `error_type` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_update_job_errors_on_update_job_id` (`update_job_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `update_job_transitions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `update_job_transitions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `to_state` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `metadata` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `sort_key` int NOT NULL,
  `update_job_id` bigint NOT NULL,
  `most_recent` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_update_job_transitions_parent_sort` (`update_job_id`,`sort_key`),
  UNIQUE KEY `index_update_job_transitions_parent_most_recent` (`update_job_id`,`most_recent`),
  KEY `index_update_job_transitions_on_most_recent_and_to_state` (`most_recent`,`to_state`),
  KEY `index_per_job_most_recent_and_state` (`update_job_id`,`most_recent`,`to_state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `update_job_unknown_errors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `update_job_unknown_errors` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `update_job_id` bigint NOT NULL,
  `error_details` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `error_type` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_update_job_unknown_errors_on_update_job_id` (`update_job_id`),
  KEY `idx_uerr_ct_at` (`error_type`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `update_job_warnings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `update_job_warnings` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `update_job_id` bigint NOT NULL,
  `warn_type` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `warn_title` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `warn_description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_update_job_warnings_on_update_job_id` (`update_job_id`),
  KEY `idx_ujwarns_ct_at` (`warn_type`,`warn_title`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `update_jobs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `update_jobs` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `base_commit_sha` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `hashed_token` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `dependencies` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `update_config_id` bigint NOT NULL,
  `pull_request_transition_id` bigint DEFAULT NULL,
  `security_updates_only` tinyint(1) NOT NULL DEFAULT '0',
  `initiator_metadata` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `hashed_credentials_token` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `dry_run` tinyint(1) NOT NULL DEFAULT '0',
  `github_request_id` bigint unsigned DEFAULT NULL,
  `triggered_at` datetime DEFAULT NULL,
  `trigger_type` varchar(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'unknown',
  `firecracker` tinyint(1) DEFAULT '0',
  `expires_at` datetime DEFAULT NULL,
  `metrics_metadata` json DEFAULT NULL,
  `actions_external_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `runner_type` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT 'actions',
  `triggered_by_ghsa_id` varchar(19) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `actions_workflow_run_id` bigint DEFAULT NULL,
  `directories` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `enqueue_scheduled_update_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `command` tinyint NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_update_jobs_on_hashed_token` (`hashed_token`),
  UNIQUE KEY `index_update_jobs_on_actions_external_id` (`actions_external_id`),
  UNIQUE KEY `index_update_jobs_on_actions_workflow_run_id` (`actions_workflow_run_id`),
  KEY `index_update_jobs_on_pull_request_transition_id` (`pull_request_transition_id`),
  KEY `index_update_jobs_on_github_request_id` (`github_request_id`),
  KEY `index_update_jobs_on_update_config_id_and_pr_transition_id` (`update_config_id`,`pull_request_transition_id`),
  KEY `index_update_jobs_on_created_at` (`created_at`),
  KEY `index_update_jobs_on_enqueue_scheduled_update_id` (`enqueue_scheduled_update_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `updated_dependencies`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `updated_dependencies` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `pull_request_id` bigint NOT NULL,
  `name` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `version` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `package_manager` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `previous_version` varchar(190) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `requirements` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `previous_requirements` text CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `non_breaking_if_semver` tinyint(1) NOT NULL,
  `removed` tinyint(1) NOT NULL DEFAULT '0',
  `directory` varbinary(1024) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_updated_dependencies_on_pr_id_and_dependency_details` (`pull_request_id`,`name`,`package_manager`,`version`,`previous_version`),
  KEY `index_updated_dependencies_on_dependency_details_and_pr_id` (`name`,`package_manager`,`version`,`previous_version`,`pull_request_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `updater_versions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `updater_versions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `env` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `ecosystem` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `version` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_updater_versions_on_env_and_ecosystem` (`env`,`ecosystem`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

INSERT INTO `schema_migrations` (version) VALUES
('20180401113324'),
('20180401130107'),
('20180402194134'),
('20180402222359'),
('20180405131805'),
('20180406144407'),
('20180408101218'),
('20180408102340'),
('20180411105723'),
('20180430170122'),
('20180509171332'),
('20180509230227'),
('20180510202009'),
('20180511151607'),
('20180511160229'),
('20180512120140'),
('20180513194405'),
('20180516123507'),
('20180604103117'),
('20180611155122'),
('20180611164732'),
('20180626013242'),
('20180703024211'),
('20180703031107'),
('20180703123834'),
('20180704122209'),
('20180704130700'),
('20180710141849'),
('20180715171421'),
('20180715225650'),
('20180716023303'),
('20180716164828'),
('20180730081951'),
('20180730082939'),
('20180730130323'),
('20180803080906'),
('20180807124157'),
('20180809221544'),
('20180814160249'),
('20180814161134'),
('20180921111524'),
('20180921112901'),
('20181002155544'),
('20181015193553'),
('20181015213545'),
('20181109100418'),
('20181110180951'),
('20181111235123'),
('20181116124542'),
('20181118120908'),
('20181203155341'),
('20181203160722'),
('20181206103531'),
('20181206110158'),
('20181217202615'),
('20181218141433'),
('20181218143307'),
('20181218145423'),
('20181218235322'),
('20181224123119'),
('20181224231228'),
('20181224234008'),
('20181228160608'),
('20181229124721'),
('20181229210158'),
('20190102171238'),
('20190105105536'),
('20190105111216'),
('20190106133821'),
('20190106144427'),
('20190106160942'),
('20190106163122'),
('20190106164654'),
('20190106173937'),
('20190107160107'),
('20190108154801'),
('20190108160753'),
('20190114104458'),
('20190114110018'),
('20190115155743'),
('20190115161022'),
('20190115171826'),
('20190115214603'),
('20190115221027'),
('20190115222046'),
('20190116101521'),
('20190121220600'),
('20190122145641'),
('20190123105801'),
('20190123184434'),
('20190123192728'),
('20190125093453'),
('20190127170216'),
('20190127175502'),
('20190127185119'),
('20190128173940'),
('20190130101352'),
('20190130132204'),
('20190205144400'),
('20190206111525'),
('20190206114430'),
('20190206152523'),
('20190206154431'),
('20190207141508'),
('20190207141931'),
('20190209180838'),
('20190214134055'),
('20190226122851'),
('20190226124500'),
('20190226125128'),
('20190316213224'),
('20190319203106'),
('20190324120648'),
('20190324222117'),
('20190326181108'),
('20190409121526'),
('20190410100836'),
('20190418105731'),
('20190427093035'),
('20190427094353'),
('20190427100246'),
('20190430170434'),
('20190503154129'),
('20190506152005'),
('20190506230606'),
('20190507124550'),
('20190507125941'),
('20190507141343'),
('20190507144651'),
('20190507192206'),
('20190507212614'),
('20190507215823'),
('20190515154450'),
('20190516134536'),
('20190603083504'),
('20190621230557'),
('20190626183102'),
('20190627105340'),
('20190628143630'),
('20190723105128'),
('20190723111137'),
('20190807170513'),
('20190808184719'),
('20190814114542'),
('20190820152848'),
('20190828115841'),
('20190828120247'),
('20190828123125'),
('20190828134615'),
('20190828143343'),
('20190828144343'),
('20190828152133'),
('20190828152303'),
('20190828162511'),
('20190919165643'),
('20191024152347'),
('20191026170654'),
('20191108113913'),
('20191209210135'),
('20200302161929'),
('20200316161225'),
('20200316181554'),
('20200317112822'),
('20200317125040'),
('20200318142848'),
('20200318171551'),
('20200318190209'),
('20200527125554'),
('20200601171200'),
('20200605173821'),
('20200625154539'),
('20200728110503'),
('20200806164836'),
('20200827151047'),
('20200828115159'),
('20200903102744'),
('20200907140753'),
('20201022155120'),
('20201022171127'),
('20201022175445'),
('20201022195131'),
('20201027205206'),
('20201029203125'),
('20201103152422'),
('20201109193300'),
('20201113175919'),
('20201120173559'),
('20201123131918'),
('20210127101922'),
('20210128195740'),
('20210202142807'),
('20210211170332'),
('20210211224345'),
('20210217212729'),
('20210217225247'),
('20210317134032'),
('20210331124504'),
('20210412175353'),
('20210421185141'),
('20210602095846'),
('20210625122014'),
('20210804110234'),
('20210826191620'),
('20211007170835'),
('20220523105629'),
('20220803155110'),
('20220816085703'),
('20220817094409'),
('20220822225754'),
('20220822230359'),
('20221017131013'),
('20221031172209'),
('20221103195142'),
('20221121121836'),
('20221122140050'),
('20221123112141'),
('20221208202701'),
('20221209114337'),
('20221213204903'),
('20230105211334'),
('20230110000224'),
('20230203164327'),
('20230206125933'),
('20230207130930'),
('20230214212651'),
('20230307130931'),
('20230313174217'),
('20230320173900'),
('20230320201307'),
('20230322161040'),
('20230412165308'),
('20230412172926'),
('20230426204342'),
('20230503162554'),
('20230726044712'),
('20230907192150'),
('20230912190638'),
('20231113193559'),
('20231204171112'),
('20231211214642'),
('20240212125055'),
('20240216131851'),
('20240216160907'),
('20240219161351'),
('20240220182141'),
('20240304213550'),
('20240307180754'),
('20240425143311'),
('20240618181955'),
('20240702200003'),
('20240719185125'),
('20240812165950'),
('20240828155701'),
('20240913201830'),
('20240920202317'),
('20240925195822'),
('20240925212618'),
('20241006151906'),
('20241209164258'),
('20250120134904'),
('20250225221237'),
('20250326215441'),
('20250508152518'),
('20250508152657'),
('20250509143031'),
('20250701200816'),
('20250807193442'),
('20250903180806'),
('20250915171042');


