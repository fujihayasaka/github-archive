
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
DROP TABLE IF EXISTS `advisories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisories` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `cve_id` varchar(40) DEFAULT NULL,
  `summary` varchar(255) DEFAULT NULL,
  `description` mediumblob,
  `severity` int DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `ghsa_id` varchar(19) NOT NULL,
  `withdrawn_at` datetime DEFAULT NULL,
  `white_source_id` varchar(40) DEFAULT NULL,
  `npm_id` int unsigned DEFAULT NULL,
  `cvss_v3` varbinary(255) DEFAULT NULL,
  `source_code_location` varbinary(1024) DEFAULT NULL,
  `reviewed` tinyint(1) DEFAULT '1',
  `published_at` datetime NOT NULL,
  `reviewed_at` datetime(6) DEFAULT NULL,
  `nvd_published_at` datetime(6) DEFAULT NULL,
  `cvss_v4` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_advisories_on_ghsa_id` (`ghsa_id`),
  UNIQUE KEY `index_advisories_on_cve_id` (`cve_id`),
  UNIQUE KEY `index_advisories_on_white_source_id` (`white_source_id`),
  UNIQUE KEY `index_advisories_on_npm_id` (`npm_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisories_cwes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisories_cwes` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `advisory_id` bigint NOT NULL,
  `cwe_id` varchar(9) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_advisories_cwes_on_advisory_id_and_cwe_id` (`advisory_id`,`cwe_id`),
  KEY `index_advisories_cwes_on_advisory_id` (`advisory_id`),
  KEY `index_advisories_cwes_on_cwe_id` (`cwe_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisory_alerting_events`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisory_alerting_events` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `ghsa_id` varchar(19) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `alerting_event_id` bigint NOT NULL,
  `processed_at` datetime(6) DEFAULT NULL,
  `finished_at` datetime(6) DEFAULT NULL,
  `alert_count` int NOT NULL DEFAULT '0',
  `notification_count` int NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisory_payload_affected_function_search_keys`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisory_payload_affected_function_search_keys` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `affected_function_id` bigint NOT NULL,
  `search_key` text,
  `index` int DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_affected_function_id` (`affected_function_id`,`index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisory_payload_cwe_ids`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisory_payload_cwe_ids` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `advisory_payload_id` bigint NOT NULL,
  `cwe_id` varchar(9) DEFAULT NULL,
  `index` int DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_advisory_payload_id` (`advisory_payload_id`,`index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisory_payload_references`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisory_payload_references` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `advisory_payload_id` bigint NOT NULL,
  `url` text,
  `index` int DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_advisory_payload_id` (`advisory_payload_id`,`index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisory_payload_vulnerabilities`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisory_payload_vulnerabilities` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `advisory_payload_id` bigint NOT NULL,
  `package_ecosystem` varchar(255) DEFAULT NULL,
  `package_name` varchar(255) DEFAULT NULL,
  `severity` int DEFAULT NULL,
  `vulnerable_version_range` varchar(255) DEFAULT NULL,
  `first_patched_version` varchar(255) DEFAULT NULL,
  `index` int DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_advisory_payload_id` (`advisory_payload_id`,`index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisory_payload_vulnerability_affected_functions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisory_payload_vulnerability_affected_functions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `vulnerability_id` bigint NOT NULL,
  `fqn` text,
  `fqn_version` int DEFAULT NULL,
  `index` int DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_vulnerability_id` (`vulnerability_id`,`index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisory_payloads`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisory_payloads` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `summary` varchar(255) DEFAULT NULL,
  `description` text,
  `source_code_location` text,
  `severity` varchar(255) DEFAULT NULL,
  `cvss_v3` varchar(255) DEFAULT NULL,
  `payload_container_type` varchar(255) NOT NULL,
  `payload_container_id` bigint NOT NULL,
  `withdrawn` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `cvss_v4` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_advisory_payloads_on_payload_container` (`payload_container_type`,`payload_container_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisory_review_approvals`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisory_review_approvals` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `advisory_review_id` bigint NOT NULL,
  `approved_at` datetime DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_advisory_review_approvals_on_user_id` (`user_id`),
  KEY `index_advisory_review_approvals_on_advisory_review_id` (`advisory_review_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisory_reviews`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisory_reviews` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `ghsa_id` varchar(19) NOT NULL,
  `cve_id` varchar(40) DEFAULT NULL,
  `state` tinyint NOT NULL DEFAULT '0',
  `advisory_payload` longblob NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `review_requested_at` datetime DEFAULT NULL,
  `white_source_id` varchar(40) DEFAULT NULL,
  `friends_of_php_id` varchar(100) DEFAULT NULL,
  `rubysec_id` varchar(100) DEFAULT NULL,
  `npm_id` int unsigned DEFAULT NULL,
  `review_notes` mediumblob,
  `default_ecosystem` varchar(40) DEFAULT NULL,
  `rustsec_id` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_advisory_reviews_on_ghsa_id` (`ghsa_id`),
  UNIQUE KEY `index_advisory_reviews_on_cve_id` (`cve_id`),
  UNIQUE KEY `index_advisory_reviews_on_white_source_id` (`white_source_id`),
  UNIQUE KEY `index_advisory_reviews_on_friends_of_php_id` (`friends_of_php_id`),
  UNIQUE KEY `index_advisory_reviews_on_rubysec_id` (`rubysec_id`),
  UNIQUE KEY `index_advisory_reviews_on_npm_id` (`npm_id`),
  UNIQUE KEY `index_advisory_reviews_on_rustsec_id` (`rustsec_id`),
  KEY `index_advisory_reviews_on_state_and_default_ecosystem` (`state`,`default_ecosystem`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisory_reviews_campaigns`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisory_reviews_campaigns` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `campaign_id` bigint NOT NULL,
  `advisory_review_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `reviewed_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_on_campaign_id_and_advisory_review_id` (`campaign_id`,`advisory_review_id`),
  KEY `index_advisory_reviews_campaigns_on_advisory_review_id` (`advisory_review_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisory_reviews_labels`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisory_reviews_labels` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `label_id` bigint NOT NULL,
  `advisory_review_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_on_label_id_and_advisory_review_id` (`label_id`,`advisory_review_id`),
  KEY `index_advisory_reviews_labels_on_advisory_review_id` (`advisory_review_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `advisory_sync_states`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `advisory_sync_states` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `advisory_id` int DEFAULT NULL,
  `processed_at` datetime DEFAULT NULL,
  `pushed_at` datetime DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_advisory_sync_states_on_advisory_id` (`advisory_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `ai_predictions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ai_predictions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `advisory_review_id` int DEFAULT NULL,
  `feed_entry_id` int DEFAULT NULL,
  `prediction_id` int DEFAULT NULL,
  `review_state_at_prediction` int DEFAULT NULL,
  `ai_model` varchar(255) DEFAULT NULL,
  `predicted_ecosystems` varchar(255) DEFAULT NULL,
  `predicted_packages` varchar(255) DEFAULT NULL,
  `curator_decision` tinyint NOT NULL DEFAULT '0',
  `decided_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `summary` text,
  `description` text,
  `prompt` text,
  `raw_prediction_output` text,
  PRIMARY KEY (`id`),
  KEY `index_ai_predictions_on_prediction_id` (`prediction_id`),
  KEY `idx_ai_predictions_advisory_review_id_and_decision` (`advisory_review_id`,`curator_decision`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `ar_internal_metadata`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ar_internal_metadata` (
  `key` varchar(255) NOT NULL,
  `value` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `blocklist_matches`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `blocklist_matches` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `blocklisted_term_id` int DEFAULT NULL,
  `advisory_review_id` int DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_on_blocklisted_term_id_and_advisory_review_id` (`blocklisted_term_id`,`advisory_review_id`),
  KEY `index_blocklist_matches_on_advisory_review_id` (`advisory_review_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `blocklisted_terms`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `blocklisted_terms` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `pattern` varchar(255) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `level` varchar(255) NOT NULL DEFAULT 'warn',
  `term_type` varchar(255) NOT NULL DEFAULT 'content',
  PRIMARY KEY (`id`),
  KEY `index_blocklisted_terms_on_pattern` (`pattern`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `campaigns`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `campaigns` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_campaigns_on_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cve_requests`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `cve_requests` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `ghsa_id` varchar(19) NOT NULL,
  `actor_id` int NOT NULL,
  `actor_login` varchar(40) NOT NULL,
  `advisory_permalink` varchar(210) NOT NULL,
  `advisory_state` varchar(20) NOT NULL,
  `title` varbinary(1024) NOT NULL,
  `description` mediumblob NOT NULL,
  `severity` int DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `cvss_v3` varbinary(255) DEFAULT NULL,
  `cwe_ids` varbinary(255) DEFAULT NULL,
  `affected_products_payload` longblob,
  `cvss_v4` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_cve_requests_on_ghsa_id` (`ghsa_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cve_reviews`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `cve_reviews` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `ghsa_id` varchar(19) NOT NULL,
  `decision` int NOT NULL DEFAULT '0',
  `comment` mediumblob,
  `assigned_cve_id` varchar(40) DEFAULT NULL,
  `description` mediumblob,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `reviewer_id` int DEFAULT NULL,
  `state` int NOT NULL DEFAULT '0',
  `title` varbinary(1024) DEFAULT NULL,
  `vendor_name` varchar(96) DEFAULT NULL,
  `product` varchar(128) DEFAULT NULL,
  `version_values` mediumblob,
  `problemtype_values` mediumblob,
  `confirm_reference` varchar(210) DEFAULT NULL,
  `misc_references` mediumblob,
  `cvss_vectorString` varchar(120) DEFAULT NULL,
  `review_requested_at` datetime DEFAULT NULL,
  `review_notes` mediumblob,
  `cvss_v4` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_cve_reviews_on_ghsa_id` (`ghsa_id`),
  KEY `index_cve_reviews_on_state` (`state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cves`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `cves` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `cve_id` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `year` smallint NOT NULL,
  `assigning_at` datetime DEFAULT NULL,
  `assigned_at` datetime DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `assigner_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_cves_on_cve_id` (`cve_id`),
  KEY `index_cves_on_year_and_assigned_at_and_assigning_at` (`year`,`assigned_at`,`assigning_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cwes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `cwes` (
  `cwe_id` varchar(9) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `name` varchar(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`cwe_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `feed_entries`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `feed_entries` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `source` int NOT NULL,
  `identifier` varchar(255) NOT NULL,
  `cve_id` varchar(40) DEFAULT NULL,
  `raw_payload` longblob,
  `advisory_payload` longblob NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `resolution_state` int NOT NULL DEFAULT '0',
  `advisory_review_id` int DEFAULT NULL,
  `white_source_id` varchar(40) DEFAULT NULL,
  `ml_reject_prediction` int DEFAULT '0',
  `friends_of_php_id` varchar(100) DEFAULT NULL,
  `rubysec_id` varchar(100) DEFAULT NULL,
  `ghsa_id` varchar(19) DEFAULT NULL,
  `npm_id` int unsigned DEFAULT NULL,
  `rustsec_id` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_feed_entries_on_identifier` (`identifier`),
  KEY `index_feed_entries_on_source` (`source`),
  KEY `index_feed_entries_on_cve_id` (`cve_id`),
  KEY `index_feed_entries_on_resolution_state` (`resolution_state`),
  KEY `index_feed_entries_on_advisory_review_id` (`advisory_review_id`),
  KEY `index_feed_entries_on_white_source_id` (`white_source_id`),
  KEY `index_feed_entries_on_friends_of_php_id` (`friends_of_php_id`),
  KEY `index_feed_entries_on_rubysec_id` (`rubysec_id`),
  KEY `index_feed_entries_on_ghsa_id` (`ghsa_id`),
  KEY `index_feed_entries_on_npm_id` (`npm_id`),
  KEY `index_feed_entries_on_rustsec_id` (`rustsec_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `fix_commits`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `fix_commits` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `vulnerability_id` bigint NOT NULL,
  `commit_url` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `index` int NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `ghsl_requests`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ghsl_requests` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `ghsa_id` varchar(19) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `ghsl_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `ghsl_issue` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_ghsl_requests_on_ghsa_id_and_ghsl_id_and_ghsl_issue` (`ghsa_id`,`ghsl_id`,`ghsl_issue`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `imports`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `imports` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `source` int NOT NULL,
  `slack_message_ts` varchar(255) DEFAULT NULL,
  `started_at` datetime DEFAULT NULL,
  `total_count` int DEFAULT NULL,
  `created_count` int NOT NULL DEFAULT '0',
  `updated_count` int NOT NULL DEFAULT '0',
  `errored_count` int NOT NULL DEFAULT '0',
  `finished_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `skipped_count` int NOT NULL DEFAULT '0',
  `bulk` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `index_imports_on_source_and_finished_at` (`source`,`finished_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `labels`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `labels` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `description` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci,
  `color` varchar(10) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `label_settings` json DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_labels_on_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `mitre_cve_submissions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `mitre_cve_submissions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `ghsa_id` varchar(19) NOT NULL,
  `pull_request_url` varchar(100) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_mitre_cve_submissions_on_ghsa_id` (`ghsa_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `references`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `references` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `advisory_id` int NOT NULL,
  `url` text,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `index` int NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_references_on_advisory_id_and_index` (`advisory_id`,`index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `schema_migrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `schema_migrations` (
  `version` varchar(255) NOT NULL,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `login` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `color_mode` varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_users_on_login` (`login`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `versions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `versions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `item_type` varchar(191) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `item_id` int NOT NULL,
  `event` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `whodunnit` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `object` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `created_at` datetime DEFAULT NULL,
  `object_changes` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  `request_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_versions_on_item_type_and_item_id` (`item_type`,`item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `vulnerabilities`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `vulnerabilities` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `advisory_id` int NOT NULL,
  `package_ecosystem` varchar(255) DEFAULT NULL,
  `package_name` varchar(255) DEFAULT NULL,
  `severity` int DEFAULT NULL,
  `vulnerable_version_range` varchar(255) DEFAULT NULL,
  `first_patched_version` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `withdrawn_at` datetime DEFAULT NULL,
  `index` int NOT NULL,
  `affected_functions` mediumblob,
  `affected_functions_v1` mediumblob,
  PRIMARY KEY (`id`),
  KEY `index_vulnerabilities_on_advisory_id_and_index` (`advisory_id`,`index`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
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
('20240926214438'),
('20240409223850'),
('20240305194107'),
('20231207233002'),
('20231114191618'),
('20231103201206'),
('20231031181129'),
('20230922204735'),
('20230719194308'),
('20230609231931'),
('20230412210622'),
('20230111173751'),
('20221213002227'),
('20221212223843'),
('20221116222924'),
('20221108180438'),
('20221104191212'),
('20221007172302'),
('20221006213049'),
('20220922195144'),
('20220726210644'),
('20220606213351'),
('20220421005638'),
('20220413220659'),
('20220318223722'),
('20220310173946'),
('20220204010004'),
('20220122011133'),
('20211027200559'),
('20211027192315'),
('20211026223050'),
('20211026222435'),
('20210802185833'),
('20210623163248'),
('20210618170327'),
('20210615200416'),
('20210610211111'),
('20210517173602'),
('20210511180503'),
('20210422194353'),
('20210417205931'),
('20210408140128'),
('20210330193338'),
('20210304144509'),
('20201124151713'),
('20201117182955'),
('20201112205657'),
('20201029210441'),
('20201023215823'),
('20201020171923'),
('20201013184654'),
('20201005193849'),
('20201001205630'),
('20200923154956'),
('20200923154955'),
('20200921171753'),
('20200707173856'),
('20200609222802'),
('20200102182420'),
('20191128031631'),
('20191115141347'),
('20191115141346'),
('20191030022608'),
('20191022224123'),
('20191014144220'),
('20190927204513'),
('20190927154137'),
('20190909225511'),
('20190828041430'),
('20190604224538'),
('20190402191529'),
('20190326183702'),
('20190319155859'),
('20190318205834'),
('20190227213559'),
('20190219183940'),
('20181116024857'),
('20181115142151'),
('20181109180708'),
('20181109142436'),
('20181101202249'),
('20181101191449'),
('20181030134511'),
('20180914175317'),
('20180914175316'),
('20180910135050'),
('20180904144651'),
('20180831132844'),
('20180819175336'),
('20180814175815'),
('20180814175530'),
('20180814173757'),
('20180814172903'),
('20180814150733'),
('20180409211722'),
('20180210181454');

