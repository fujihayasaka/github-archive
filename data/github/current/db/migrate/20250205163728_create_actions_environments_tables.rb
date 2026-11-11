# typed: true

class CreateActionsEnvironmentsTables < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::ActionsEnvironments)

  def up
    return unless (Rails.env.test? || Rails.env.development?) && !GitHub.enterprise? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `environments`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      CREATE TABLE `environments` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `repository_id` bigint unsigned NOT NULL,
        `name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
        `created_at` datetime NOT NULL,
        `updated_at` datetime NOT NULL,
        `gates_admin_enforced` tinyint(1) NOT NULL DEFAULT '0',
        PRIMARY KEY (`id`),
        UNIQUE KEY `index_environments_on_repository_id_and_name` (`repository_id`,`name`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `gate_approval_logs`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      CREATE TABLE `gate_approval_logs` (
        `id` int NOT NULL AUTO_INCREMENT,
        `repository_id` int NOT NULL,
        `check_suite_id` bigint NOT NULL,
        `user_id` int NOT NULL COMMENT 'the actual user that approved the gate request',
        `state` int NOT NULL COMMENT 'whether if it was approved, denied or dismissed',
        `comment` varbinary(1024) NOT NULL COMMENT 'approval comment',
        `created_at` datetime NOT NULL,
        `updated_at` datetime NOT NULL,
        PRIMARY KEY (`id`),
        KEY `index_gate_approval_logs_on_check_suite_id` (`check_suite_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `gate_approvals`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      CREATE TABLE `gate_approvals` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `gate_request_id` bigint unsigned NOT NULL,
        `repository_id` bigint unsigned NOT NULL,
        `approver_type` varchar(4) NOT NULL COMMENT 'the type of approver (user or team)',
        `approver_id` bigint unsigned NOT NULL COMMENT 'the id of the approver (user_id or team_id)',
        `state` int NOT NULL COMMENT 'whether if it was approved, denied or dismissed',
        `user_id` bigint unsigned NOT NULL COMMENT 'the actual user that approved the gate request',
        `gate_approval_log_id` bigint unsigned DEFAULT NULL,
        `environment_id` bigint unsigned NOT NULL,
        PRIMARY KEY (`id`),
        KEY `index_gate_approvals_on_gate_approval_log_id` (`gate_approval_log_id`),
        KEY `index_gate_approvals_on_gate_request_id_and_user_id` (`gate_request_id`,`user_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `gate_approvers`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      CREATE TABLE `gate_approvers` (
        `id` int NOT NULL AUTO_INCREMENT,
        `gate_id` int NOT NULL,
        `repository_id` int NOT NULL,
        `approver_type` varchar(4) NOT NULL COMMENT 'the type of approver (user or team)',
        `approver_id` int NOT NULL COMMENT 'the id of the approver (user_id or team_id)',
        PRIMARY KEY (`id`),
        UNIQUE KEY `index_gate_approvals_on_approver_and_type_and_gate` (`approver_id`,`approver_type`,`gate_id`),
        KEY `index_gate_approvers_on_gate_id` (`gate_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `gate_branch_policies`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      CREATE TABLE `gate_branch_policies` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `gate_id` bigint NOT NULL,
        `repository_id` bigint NOT NULL,
        `name` varbinary(1024) NOT NULL COMMENT 'branch which can include wildcards',
        `created_at` datetime(6) NOT NULL,
        `updated_at` datetime(6) NOT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `index_gate_branch_policies_on_gate_id_name` (`gate_id`,`name`),
        KEY `index_gate_branch_policies_on_gate_id` (`gate_id`),
        KEY `index_gate_branch_policies_on_repository_id` (`repository_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `gate_requests`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      CREATE TABLE `gate_requests` (
        `id` int NOT NULL AUTO_INCREMENT,
        `gate_id` int NOT NULL,
        `state` int NOT NULL DEFAULT '0' COMMENT 'whether the gate is open or closed. Defaults to closed',
        `check_run_id` bigint NOT NULL,
        `token` text NOT NULL COMMENT 'token to pass to actions service',
        `data` blob COMMENT 'potentially store additional info about the gate request depending on the gate type',
        `created_at` datetime NOT NULL,
        `updated_at` datetime NOT NULL,
        `expires_at` datetime(6) DEFAULT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `index_gate_requests_on_gate_id_and_check_run_id` (`gate_id`,`check_run_id`),
        KEY `index_gate_requests_on_gate_id` (`gate_id`),
        KEY `index_gate_requests_on_check_run_id` (`check_run_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `gates`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      CREATE TABLE `gates` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `environment_id` bigint unsigned NOT NULL,
        `name` varbinary(1024) DEFAULT NULL COMMENT 'name of the gate, that can contain emojis',
        `body` blob NOT NULL COMMENT 'data that changes depending on the gate type',
        `type` int NOT NULL COMMENT 'the gate type (e.g. manual / timeout)',
        `timeout` int NOT NULL COMMENT 'timeout in minutes',
        `created_at` datetime NOT NULL,
        `updated_at` datetime NOT NULL,
        `min_approvals` int NOT NULL DEFAULT '0' COMMENT 'minimum number of approvals to open the gate',
        `integration_id` bigint unsigned DEFAULT NULL,
        `integration_installation_id` bigint unsigned DEFAULT NULL,
        `prevent_self_review` tinyint(1) NOT NULL DEFAULT '0',
        PRIMARY KEY (`id`),
        KEY `index_gates_on_environment_id` (`environment_id`),
        KEY `index_gates_on_integration_installation_id` (`integration_installation_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `pinned_environments`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      CREATE TABLE `pinned_environments` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `repository_id` bigint unsigned NOT NULL,
        `environment_id` bigint unsigned NOT NULL,
        `position` int unsigned NOT NULL DEFAULT '1',
        `created_at` datetime(6) NOT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `index_pinned_environments_on_repository_id_and_environment_id` (`repository_id`,`environment_id`),
        KEY `index_pinned_environments_on_repository_id_and_position` (`repository_id`,`position`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `repository_tech_project_stacks`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      CREATE TABLE `repository_tech_project_stacks` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `repository_tech_project_id` bigint unsigned NOT NULL,
        `repository_id` bigint unsigned NOT NULL,
        `stack_name_id` bigint unsigned NOT NULL,
        `settings` json DEFAULT NULL,
        `size` bigint unsigned DEFAULT NULL,
        `created_at` datetime(6) NOT NULL,
        `updated_at` datetime(6) NOT NULL,
        PRIMARY KEY (`id`),
        KEY `repository_tech_project_id_and_repository_id_and_stack_name_id` (`repository_tech_project_id`,`repository_id`,`stack_name_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `repository_tech_projects`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      CREATE TABLE `repository_tech_projects` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `repository_id` bigint unsigned NOT NULL,
        `path` varbinary(1024) NOT NULL,
        `created_at` datetime(6) NOT NULL,
        `updated_at` datetime(6) NOT NULL,
        PRIMARY KEY (`id`),
        KEY `index_repository_tech_projects_on_repository_id_and_path` (`repository_id`,`path`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
    SQL
  end

  def down
    return unless (Rails.env.test? || Rails.env.development?) && !GitHub.enterprise? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `repository_tech_projects`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `repository_tech_project_stacks`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `pinned_environments`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `gates`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `gate_requests`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `gate_branch_policies`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `gate_approvers`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `gate_approvals`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `gate_approval_logs`;
    SQL

    ApplicationRecord::ActionsEnvironments.connection.execute <<-SQL
      DROP TABLE IF EXISTS `environments`;
    SQL
  end
end
