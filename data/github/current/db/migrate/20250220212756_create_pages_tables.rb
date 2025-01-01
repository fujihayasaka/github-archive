# typed: true

class CreatePagesTables < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Pages)

  def up
    return unless (Rails.env.test? || Rails.env.development?) && !GitHub.enterprise? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `page_builds`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      CREATE TABLE `page_builds` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `page_id` bigint unsigned DEFAULT NULL,
        `page_deployment_id` bigint unsigned DEFAULT NULL,
        `pages_deployment_id` bigint unsigned DEFAULT NULL,
        `raw_data` blob,
        `created_at` datetime DEFAULT NULL,
        `updated_at` datetime DEFAULT NULL,
        `pusher_id` bigint unsigned DEFAULT NULL,
        `commit` char(40) DEFAULT NULL,
        `status` varchar(255) DEFAULT NULL,
        `error` text,
        `backtrace` text,
        `duration` bigint unsigned DEFAULT NULL,
        `workflow_run_id` bigint unsigned DEFAULT NULL,
        PRIMARY KEY (`id`),
        KEY `index_page_builds_on_updated_at` (`updated_at`),
        KEY `index_page_builds_on_page_id_and_updated_at` (`page_id`,`updated_at`),
        KEY `index_page_builds_on_pages_deployment_id_and_updated_at` (`pages_deployment_id`,`updated_at`),
        KEY `index_page_builds_on_page_deployment_id_and_updated_at` (`page_deployment_id`,`updated_at`),
        KEY `index_page_builds_on_page_id_and_commit` (`page_id`,`commit`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `page_certificates`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      CREATE TABLE `page_certificates` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `domain` varchar(255) NOT NULL,
        `state` int DEFAULT NULL,
        `state_detail` text,
        `expires_at` datetime DEFAULT NULL,
        `challenge_path` text,
        `challenge_response` text,
        `earthsmoke_key_version_id` bigint unsigned DEFAULT NULL,
        `fastly_privkey_id` text,
        `authorization_url` text,
        `certificate_url` text,
        `fastly_certificate_id` varchar(255) DEFAULT NULL,
        `order_url` text,
        `alt_domain` varchar(255) DEFAULT NULL,
        `alt_challenge_path` text,
        `alt_challenge_response` text,
        `alt_authorization_url` text,
        `updated_at` datetime(6) DEFAULT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `index_page_certificates_on_domain` (`domain`),
        UNIQUE KEY `index_page_certificates_on_alt_domain` (`alt_domain`),
        KEY `index_page_certificates_on_state_and_expires_at` (`state`,`expires_at`),
        KEY `index_page_certificates_on_expires_at` (`expires_at`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `page_deployments`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      CREATE TABLE `page_deployments` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `page_id` bigint unsigned NOT NULL,
        `ref_name` varbinary(1024) NOT NULL,
        `revision` varchar(40) DEFAULT NULL,
        `status` varchar(255) DEFAULT NULL,
        `created_at` datetime NOT NULL,
        `updated_at` datetime NOT NULL,
        `token` varchar(25) DEFAULT NULL,
        `final_deployment_status` smallint DEFAULT NULL,
        `check_run_id` bigint unsigned DEFAULT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `index_page_deployments_on_page_id_and_ref_name` (`page_id`,`ref_name`(767)),
        UNIQUE KEY `index_page_deployments_on_page_id_and_token` (`page_id`,`token`),
        KEY `index_page_deployments_on_page_id_and_revision` (`page_id`,`revision`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `page_updates`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      CREATE TABLE `page_updates` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `page_id` bigint unsigned NOT NULL,
        `event` tinyint unsigned NOT NULL COMMENT 'the type of event (update, destroy)',
        `created_at` datetime(6) NOT NULL,
        `updated_at` datetime(6) NOT NULL,
        PRIMARY KEY (`id`),
        KEY `index_page_updates_on_page_id` (`page_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      CREATE TABLE `pages` (
        `id` bigint NOT NULL AUTO_INCREMENT,
        `repository_id` bigint DEFAULT NULL,
        `cname` varchar(255) DEFAULT NULL,
        `four_oh_four` tinyint(1) DEFAULT '0',
        `status` varchar(20) DEFAULT NULL,
        `has_public_search` tinyint(1) DEFAULT '0',
        `built_revision` varchar(40) DEFAULT NULL,
        `https_redirect` tinyint(1) NOT NULL DEFAULT '0',
        `hsts_max_age` int DEFAULT NULL,
        `source` varchar(255) DEFAULT NULL,
        `source_ref_name` varbinary(1024) DEFAULT NULL,
        `source_subdir` varbinary(1024) DEFAULT NULL,
        `hsts_include_sub_domains` tinyint(1) NOT NULL DEFAULT '0',
        `hsts_preload` tinyint(1) NOT NULL DEFAULT '0',
        `public` tinyint(1) NOT NULL DEFAULT '1',
        `subdomain` varchar(130) DEFAULT NULL,
        `parent_domain` varchar(255) DEFAULT NULL COMMENT 'subdomains track the name of their parent domain',
        `www_parent_domain` varchar(255) DEFAULT NULL,
        `build_type` tinyint unsigned NOT NULL DEFAULT '0' COMMENT 'default value (0) builds with Jekyll. Other values defined by application.',
        `custom_subdomain` varchar(96) DEFAULT NULL COMMENT 'custom_subdomain is 63 characters + _{tenant shortcode}',
        `deleted_at` datetime(6) DEFAULT NULL,
        `deleted_cname` varchar(255) DEFAULT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `index_pages_on_repository_id` (`repository_id`),
        UNIQUE KEY `index_pages_on_unique_cname` (`cname`),
        UNIQUE KEY `index_pages_on_subdomain` (`subdomain`),
        UNIQUE KEY `index_pages_on_unique_custom_subdomain` (`custom_subdomain`),
        KEY `index_pages_on_parent_domain` (`parent_domain`),
        KEY `index_pages_on_www_parent_domain` (`www_parent_domain`),
        KEY `index_pages_on_deleted_at` (`deleted_at`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages_fileservers`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      CREATE TABLE `pages_fileservers` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `host` varchar(255) NOT NULL,
        `online` tinyint(1) NOT NULL,
        `embargoed` tinyint(1) NOT NULL,
        `evacuating` tinyint(1) NOT NULL DEFAULT '0',
        `disk_free` bigint unsigned NOT NULL DEFAULT '0',
        `disk_used` bigint unsigned NOT NULL DEFAULT '0',
        `created_at` datetime NOT NULL,
        `updated_at` datetime NOT NULL,
        `non_voting` tinyint(1) NOT NULL DEFAULT '0',
        `datacenter` varchar(20) DEFAULT NULL,
        `rack` varchar(20) DEFAULT NULL,
        `ip` varchar(45) DEFAULT NULL,
        `inodes_free` bigint unsigned NOT NULL DEFAULT '0',
        `inodes_used` bigint unsigned NOT NULL DEFAULT '0',
        PRIMARY KEY (`id`),
        UNIQUE KEY `index_pages_fileservers_on_host` (`host`),
        KEY `index_pages_fileservers_by_location` (`datacenter`,`rack`),
        KEY `index_pages_fileservers_on_evacuating` (`evacuating`),
        KEY `index_pages_fileservers_on_online_and_embargoed_and_host` (`online`,`embargoed`,`host`),
        KEY `index_pages_fileservers_on_voting_and_online_and_embarg_and_host` (`non_voting`,`online`,`embargoed`,`host`),
        KEY `index_pages_fileservers_on_voting_and_online_and_embarg_and_df` (`non_voting`,`online`,`embargoed`,`disk_free`),
        KEY `index_pages_fileservers_on_voting_online_embargo_df_inodes` (`non_voting`,`online`,`embargoed`,`disk_free`,`inodes_free`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages_migrations`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      CREATE TABLE `pages_migrations` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `page_id` bigint unsigned NOT NULL,
        `page_deployment_id` bigint unsigned NOT NULL,
        `manifest` json DEFAULT NULL,
        `created_at` datetime(6) DEFAULT NULL,
        `started_at` datetime(6) DEFAULT NULL,
        `updated_at` datetime(6) DEFAULT NULL,
        `status` tinyint unsigned NOT NULL DEFAULT '0' COMMENT 'Current state of migration. See enum in PageMigration model',
        PRIMARY KEY (`id`),
        KEY `index_page_id_page_deployment_id` (`page_id`,`page_deployment_id`),
        KEY `index_status_updated_at_pages_migrations` (`status`,`updated_at`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages_partitions`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      CREATE TABLE `pages_partitions` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `host` varchar(255) NOT NULL,
        `partition` varchar(1) NOT NULL,
        `disk_free` bigint NOT NULL,
        `disk_used` bigint NOT NULL,
        `created_at` datetime NOT NULL,
        `updated_at` datetime NOT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `index_pages_partitions_on_host_and_partition` (`host`,`partition`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages_protected_domains`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      CREATE TABLE `pages_protected_domains` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `owner_id` bigint unsigned NOT NULL,
        `owner_type` enum('User','Organization','Enterprise') COLLATE utf8mb4_unicode_520_ci NOT NULL,
        `name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
        `state` tinyint unsigned NOT NULL DEFAULT '0',
        `challenge` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
        `unverified_at` datetime(6) DEFAULT NULL COMMENT 'datetime when the domain transitions to the unverified state',
        `created_at` datetime(6) NOT NULL,
        `updated_at` datetime(6) NOT NULL,
        `parent_domain` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'subdomains track the name of their parent domain',
        `last_verified_at` datetime(6) DEFAULT NULL COMMENT 'datetime when verification was previously performed',
        PRIMARY KEY (`id`),
        UNIQUE KEY `index_pages_protected_domains_on_name_owner_type_owner_id` (`name`,`owner_type`,`owner_id`),
        KEY `index_pages_protected_domains_on_state_and_unverified_at` (`state`,`unverified_at`),
        KEY `index_pages_protected_domains_on_parent_domain` (`parent_domain`),
        KEY `index_pages_protected_domains_on_owner_id_owner_type` (`owner_id`,`owner_type`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages_replicas`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      CREATE TABLE `pages_replicas` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `page_id` bigint unsigned NOT NULL,
        `host` varchar(255) NOT NULL,
        `created_at` datetime NOT NULL,
        `updated_at` datetime NOT NULL,
        `pages_deployment_id` bigint unsigned DEFAULT NULL,
        PRIMARY KEY (`id`),
        KEY `index_pages_replicas_on_host` (`host`),
        KEY `index_pages_replicas_on_pages_deployment_id_and_host` (`pages_deployment_id`,`host`),
        KEY `index_pages_replicas_on_page_id_and_host` (`page_id`,`host`),
        KEY `index_pages_replicas_on_page_id_and_pages_deployment_id_and_host` (`page_id`,`pages_deployment_id`,`host`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages_routes`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      CREATE TABLE `pages_routes` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `user_id` bigint unsigned NOT NULL,
        `host` varchar(255) NOT NULL,
        `https_behavior` int DEFAULT NULL,
        PRIMARY KEY (`id`),
        UNIQUE KEY `index_pages_routes_on_user_id` (`user_id`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL
  end

  def down
    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `page_builds`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `page_certificates`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `page_deployments`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `page_updates`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages_fileservers`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages_migrations`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages_partitions`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages_protected_domains`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages_replicas`;
    SQL

    ApplicationRecord::Pages.connection.execute <<~SQL
      DROP TABLE IF EXISTS `pages_routes`;
    SQL
  end
end
