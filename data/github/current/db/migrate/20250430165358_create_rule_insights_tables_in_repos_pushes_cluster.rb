# typed: true

class CreateRuleInsightsTablesInReposPushesCluster < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def up
    return unless (Rails.env.test? || Rails.env.development?) && !GitHub.enterprise? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
      DROP TABLE IF EXISTS `event_action_ref_updates`;
    SQL

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
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
    SQL

    add_vindex :event_action_ref_updates, :hash, :repository_id
    add_auto_increment :event_action_ref_updates, :id, :event_action_ref_updates_id_seq

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
      DROP TABLE IF EXISTS `event_action_repository_operations`;
    SQL

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
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
    SQL

    add_vindex :event_action_repository_operations, :hash, :repository_id
    add_auto_increment :event_action_repository_operations, :id, :event_action_repository_operations_id_seq

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
      DROP TABLE IF EXISTS `repository_rule_runs`;
    SQL

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
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
    SQL

    add_vindex :repository_rule_runs, :hash, :repository_id
    add_auto_increment :repository_rule_runs, :id, :repository_rule_runs_id_seq

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
      DROP TABLE IF EXISTS `repository_rule_suite_source_results`;
    SQL

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
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
    SQL

    add_vindex :repository_rule_suite_source_results, :hash, :repository_id
    add_auto_increment :repository_rule_suite_source_results, :id, :repository_rule_suite_source_results_id_seq

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
      DROP TABLE IF EXISTS `repository_rule_suites`;
    SQL

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
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
    SQL

    add_vindex :repository_rule_suites, :hash, :repository_id
    add_auto_increment :repository_rule_suites, :id, :repository_rule_suites_id_seq
  end

  def down
    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
      DROP TABLE IF EXISTS `event_action_ref_updates`;
    SQL

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
      DROP TABLE IF EXISTS `event_action_repository_operations`;
    SQL

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
      DROP TABLE IF EXISTS `repository_rule_runs`;
    SQL

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
      DROP TABLE IF EXISTS `repository_rule_suite_source_results`;
    SQL

    ApplicationRecord::RepositoriesPushes.connection.execute <<~SQL
      DROP TABLE IF EXISTS `repository_rule_suites`;
    SQL
  end
end
