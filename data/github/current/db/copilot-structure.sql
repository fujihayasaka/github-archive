DROP TABLE IF EXISTS `agent_session_finished_notifications`;
CREATE TABLE `agent_session_finished_notifications` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `agent_id` bigint unsigned NOT NULL,
  `pull_request_id` bigint unsigned DEFAULT NULL,
  `session_id` varchar(55) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `task_id` varchar(55) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `session_state` varchar(20) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `session_name` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `task_name` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_agent_session_finished_notifications_on_session_id` (`session_id`),
  KEY `idx_on_user_id_created_at_3b42c4e3dc` (`user_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_activities`;
CREATE TABLE `copilot_activities` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `copilot_seat_id` bigint NOT NULL COMMENT 'Specific Copilot Seat for this activity',
  `activity_details` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `activity_at` datetime(6) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `activity_source` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_activities_on_copilot_seat_id` (`copilot_seat_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_activity_histories`;
CREATE TABLE `copilot_activity_histories` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `copilot_seat_id` bigint unsigned NOT NULL COMMENT 'Specific Copilot Seat for this activity',
  `activity_date` date NOT NULL COMMENT 'Date of activity',
  `activity_details` json NOT NULL COMMENT 'Details of the activity',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_cah_on_seat_and_date` (`copilot_seat_id`,`activity_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_administrative_blocks`;
CREATE TABLE `copilot_administrative_blocks` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `actor_id` bigint unsigned NOT NULL,
  `blockable_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `blockable_id` bigint NOT NULL,
  `reason` varchar(1024) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `state` tinyint unsigned NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_copilot_administrative_blocks_on_blockable` (`blockable_type`,`blockable_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_agent_sessions`;
CREATE TABLE `copilot_agent_sessions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `business_id` bigint unsigned DEFAULT NULL,
  `organization_id` bigint unsigned NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `agent_id` bigint unsigned NOT NULL,
  `agent_type` enum('Integration','OauthApplication') COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT 'Integration',
  `resource_id` bigint unsigned DEFAULT NULL,
  `resource_type` enum('PullRequest') COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `copilot_session_id` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `name` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `state` varchar(20) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `task_description` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `event_type` varbinary(128) DEFAULT NULL,
  `automation_id` varchar(64) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `is_triggered` tinyint(1) NOT NULL DEFAULT '0',
  `head_ref` varbinary(255) DEFAULT NULL,
  `base_ref` varbinary(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_on_business_id_organization_id_d858eb51a4` (`business_id`,`organization_id`),
  KEY `index_copilot_agent_sessions_on_business_id_and_agent_id` (`business_id`,`agent_id`),
  KEY `idx_on_business_id_task_description_e08f95bd92` (`business_id`,`task_description`),
  KEY `index_copilot_agent_sessions_on_resource_id_and_resource_type` (`resource_id`,`resource_type`),
  KEY `index_copilot_agent_sessions_on_copilot_session_id` (`copilot_session_id`),
  KEY `index_copilot_agent_sessions_on_business_id_created_at` (`business_id`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_anthropic_user_profiles`;
CREATE TABLE `copilot_anthropic_user_profiles` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` bigint unsigned NOT NULL,
  `owner_type` varchar(20) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `anthropic_id` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `external_id` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `grants` json DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_copilot_anthropic_user_profiles_on_owner_id_and_owner_type` (`owner_id`,`owner_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_authentication_histories`;
CREATE TABLE `copilot_authentication_histories` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `copilot_seat_id` bigint unsigned NOT NULL COMMENT 'Specific Copilot Seat for this authentication',
  `authentication_date` date NOT NULL COMMENT 'Date of authentication',
  `authentication_details` json NOT NULL COMMENT 'Details of the authentication',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_cahis_on_seat_and_date` (`copilot_seat_id`,`authentication_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_authentications`;
CREATE TABLE `copilot_authentications` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `copilot_seat_id` bigint NOT NULL COMMENT 'Specific Copilot Seat for this authentication',
  `authentication_details` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `authentication_at` datetime(6) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_authentications_on_copilot_seat_id` (`copilot_seat_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_business_trials`;
CREATE TABLE `copilot_business_trials` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `copilot_plan` tinyint NOT NULL DEFAULT '0' COMMENT 'the GitHub Copilot plan the trial is for, e.g. Copilot Enterprise or Copilot Business',
  `trialable_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `trialable_id` bigint unsigned NOT NULL COMMENT 'The object (Business/Enterprise or Org) that this trial is for',
  `trial_length` int NOT NULL DEFAULT '30' COMMENT 'The length of the trial in days',
  `started_at` datetime(6) NOT NULL COMMENT 'The time the trial started',
  `ends_at` datetime(6) NOT NULL COMMENT 'The time the trial ends',
  `managing_user_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `state` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_business_trials_on_trialable` (`trialable_type`,`trialable_id`),
  KEY `index_copilot_business_trials_on_managing_user_id` (`managing_user_id`),
  KEY `index_copilot_business_trials_on_state` (`state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_chat_attachments`;
CREATE TABLE `copilot_chat_attachments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `guid` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `uploader_id` bigint unsigned NOT NULL,
  `storage_blob_id` bigint unsigned DEFAULT NULL,
  `state` int NOT NULL DEFAULT '0',
  `size` int NOT NULL,
  `content_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `thread_id` varchar(36) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'Thread ID, if the chat attachment is associated to a chat thread.',
  PRIMARY KEY (`id`),
  KEY `index_copilot_chat_attachments_on_uploader_id_and_state` (`uploader_id`,`state`),
  KEY `index_copilot_chat_attachments_on_thread_id` (`thread_id`),
  KEY `index_copilot_chat_attachments_on_created_at` (`created_at`),
  KEY `index_copilot_chat_attachments_on_guid` (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_code_review_repo_enablements`;
CREATE TABLE `copilot_code_review_repo_enablements` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` bigint unsigned NOT NULL COMMENT 'The ID of the owner of the repository',
  `repository_id` bigint unsigned NOT NULL COMMENT 'The ID of the enabled repository',
  `setting_type` int NOT NULL COMMENT 'The type of Copilot code review repository setting that is enabled',
  `created_at` datetime(6) NOT NULL COMMENT 'The time when the feature was enabled for this repository',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_ccr_repo_enablements_on_repo_owner_setting` (`repository_id`,`owner_id`,`setting_type`),
  KEY `idx_ccr_repo_enablements_on_owner_setting` (`owner_id`,`setting_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_code_review_repository_approval_settings`;
CREATE TABLE `copilot_code_review_repository_approval_settings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `repo_auto_approve_when_delegated` tinyint(1) NOT NULL DEFAULT '0',
  `repo_qualified_approval_when_delegated` tinyint(1) NOT NULL DEFAULT '0',
  `repo_qualified_approval_scope_when_enabled` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT 'all_files',
  `repo_qualified_approval_file_patterns` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_ccr_repo_approval_settings_on_repo_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_code_review_repository_settings`;
CREATE TABLE `copilot_code_review_repository_settings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `repo_custom_instructions_enabled` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repo_auto_approve_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `repo_auto_reject_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `repo_mcp_enabled` tinyint(1) NOT NULL DEFAULT '1',
  `repo_review_effort_level` tinyint NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_ccr_repo_settings_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_coding_guideline_paths`;
CREATE TABLE `copilot_coding_guideline_paths` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `copilot_coding_guideline_id` bigint unsigned NOT NULL,
  `path` varchar(200) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_on_copilot_coding_guideline_id_02dcbc1309` (`copilot_coding_guideline_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_coding_guidelines`;
CREATE TABLE `copilot_coding_guidelines` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT '0',
  `name` varchar(200) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `example_code_violations` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `copilot_code_guidelines_repo_id_and_name` (`repository_id`,`name`),
  KEY `index_copilot_coding_guidelines_on_enabled` (`enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_completion_feedback`;
CREATE TABLE `copilot_completion_feedback` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `job_id` varchar(55) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sentiment` int NOT NULL DEFAULT '0',
  `contact` tinyint(1) NOT NULL DEFAULT '0',
  `context` blob NOT NULL,
  `body` mediumblob,
  `classification` int NOT NULL DEFAULT '0',
  `session_id` varchar(55) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_copilot_completion_feedback_on_sentiment` (`sentiment`),
  KEY `index_copilot_completion_feedback_on_session_id` (`session_id`),
  KEY `index_copilot_completion_feedback_on_job_id` (`job_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_complimentary_users`;
CREATE TABLE `copilot_complimentary_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `free_user_type` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'the type of the free user',
  `last_checked_date` date NOT NULL,
  `subscribed` tinyint(1) NOT NULL DEFAULT '0',
  `subscribed_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_complimentary_users_on_user_id` (`user_id`),
  KEY `index_free_user_type` (`free_user_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_condition_expressions`;
CREATE TABLE `copilot_condition_expressions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `targetable_attribute` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `operation` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `root_condition_expression_id` bigint unsigned DEFAULT NULL,
  `parent_condition_expression_id` bigint unsigned DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_copilot_condition_expressions_on_root_condition` (`root_condition_expression_id`),
  KEY `index_copilot_condition_expressions_on_parent_condition` (`parent_condition_expression_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_configurations`;
CREATE TABLE `copilot_configurations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `configurable_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `configurable_id` bigint NOT NULL COMMENT 'The object (Business, Org, or User) that this configuration is for',
  `public_code_suggestions` int NOT NULL DEFAULT '0' COMMENT 'Whether to show code suggestions from public sources',
  `user_telemetry` int NOT NULL DEFAULT '0' COMMENT 'Whether to send telemetry data to GitHub',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `copilot_enabled` int NOT NULL DEFAULT '0' COMMENT 'Whether Copilot is enabled for this configurable (Organization or Business)',
  `seat_management` int NOT NULL DEFAULT '0',
  `chat_enabled` int NOT NULL DEFAULT '0',
  `max_seats` int NOT NULL DEFAULT '0' COMMENT 'The maximum number of seats allowed for this configurable (Organization or Business)',
  `dotcom_chat` tinyint NOT NULL DEFAULT '0',
  `custom_models` tinyint NOT NULL DEFAULT '0',
  `cli` tinyint NOT NULL DEFAULT '0',
  `private_docs` tinyint NOT NULL DEFAULT '0',
  `github_enterprise_feature_group` tinyint NOT NULL DEFAULT '0' COMMENT 'Keep track if the group of enterprise features has been enabled',
  `pr_summarizations` tinyint NOT NULL DEFAULT '0' COMMENT 'policy for GitHub Copilot for Pull Request Summarizations',
  `usage_telemetry_api` tinyint NOT NULL DEFAULT '0',
  `copilot_plan` tinyint NOT NULL DEFAULT '0' COMMENT 'the current GitHub Copilot plan, e.g. Copilot Enterprise or Copilot Business',
  `pending_plan_downgrade_date` date DEFAULT NULL,
  `ide_chat` tinyint NOT NULL DEFAULT '2',
  `user_feedback_opt_in` tinyint NOT NULL DEFAULT '1' COMMENT 'policy for GitHub Copilot for user feedback opt in',
  `bing_github_chat` tinyint NOT NULL DEFAULT '0' COMMENT 'policy for Bing usage by Copilot in GitHub',
  `mobile_chat` tinyint NOT NULL DEFAULT '0' COMMENT 'The policy for Copilot in Mobile',
  `copilot_extensions` tinyint NOT NULL DEFAULT '0' COMMENT 'The policy for allowing Copilot extensions',
  `beta_features_github_chat` tinyint NOT NULL DEFAULT '0' COMMENT 'policy for beta features usage by Copilot in GitHub',
  `private_telemetry` tinyint NOT NULL DEFAULT '0' COMMENT 'The policy for allowing private telemetry capture',
  `prompt_overlap` tinyint NOT NULL DEFAULT '0' COMMENT 'Whether to show code suggestions from public sources when the response is contained within the prompt',
  `a_chat` tinyint NOT NULL DEFAULT '0',
  `o1` tinyint NOT NULL DEFAULT '0',
  `g_chat` tinyint NOT NULL DEFAULT '0',
  `editor_preview_features` tinyint NOT NULL DEFAULT '0',
  `workspace_for_emu` tinyint NOT NULL DEFAULT '0' COMMENT 'The policy for allowing Copilot Workspace for EMUs',
  `o3` tinyint NOT NULL DEFAULT '0',
  `a_f` tinyint NOT NULL DEFAULT '0',
  `o_f` tinyint NOT NULL DEFAULT '0',
  `o_ff` tinyint NOT NULL DEFAULT '0',
  `desktop` tinyint NOT NULL DEFAULT '0',
  `overages` tinyint NOT NULL DEFAULT '0',
  `o_t` tinyint NOT NULL DEFAULT '0',
  `o_fm` tinyint NOT NULL DEFAULT '0',
  `g_tf` tinyint NOT NULL DEFAULT '0',
  `ofo` tinyint NOT NULL DEFAULT '0',
  `user_automatic_code_review` tinyint NOT NULL DEFAULT '0' COMMENT 'Automatically request Copilot code reviews for a user',
  `billable_customer_id` bigint unsigned DEFAULT NULL COMMENT 'The customer that will be billed for this user',
  `swe_agent` tinyint NOT NULL DEFAULT '0' COMMENT 'Policy for Copilot SWE Agent usage',
  `mcp` tinyint NOT NULL DEFAULT '0' COMMENT 'Policy for Copilot MCP server usage',
  `al` tinyint NOT NULL DEFAULT '0',
  `gtff` tinyint NOT NULL DEFAULT '0' COMMENT 'Policy for Gemini 2.5 Flash in Copilot',
  `afos` tinyint NOT NULL DEFAULT '0',
  `insights` tinyint NOT NULL DEFAULT '0' COMMENT 'Policy for Insights Dashboards',
  `ea_user_fallback_policy` tinyint NOT NULL DEFAULT '1' COMMENT 'Defines the fallback policy state for enterprise-assigned users in Copilot configurations when the business selects "No policy" for any policy. Defaults to disabled.',
  `spark` tinyint NOT NULL DEFAULT '0' COMMENT 'The policy for enabling or disabling Spark for members of an organization',
  `code_review` tinyint NOT NULL DEFAULT '0' COMMENT 'Policy for Copilot Code Review usage',
  `code_review_beta_features` tinyint NOT NULL DEFAULT '0' COMMENT 'Policy for beta features usage by Copilot Code Review',
  `obmb` tinyint NOT NULL DEFAULT '0',
  `agent_mode` tinyint NOT NULL DEFAULT '0',
  `obmw` tinyint NOT NULL DEFAULT '0',
  `aofo` tinyint NOT NULL DEFAULT '0',
  `emergency_model_1` tinyint NOT NULL DEFAULT '0',
  `emergency_model_2` tinyint NOT NULL DEFAULT '0',
  `emergency_model_3` tinyint NOT NULL DEFAULT '0',
  `grok_code` tinyint NOT NULL DEFAULT '0',
  `m_ironman` tinyint NOT NULL DEFAULT '0',
  `m_spiderman` tinyint NOT NULL DEFAULT '0',
  `m_thor` tinyint NOT NULL DEFAULT '0',
  `model_policies` json DEFAULT NULL,
  `ofct` tinyint NOT NULL DEFAULT '0',
  `generated_commit_message` tinyint NOT NULL DEFAULT '0' COMMENT 'Policy for Copilot Generated Commit Message usage',
  `loops` tinyint NOT NULL DEFAULT '0' COMMENT 'The policy for enabling or disabling Loops for members of an organization',
  `spark_force_org` tinyint NOT NULL DEFAULT '0' COMMENT 'Policy for forcing Spark repo creation to the copilot providing organization instead of the user',
  `acb` tinyint NOT NULL DEFAULT '0',
  `spaces` tinyint NOT NULL DEFAULT '0' COMMENT 'The policy for allowing Copilot Spaces for members of an organization',
  `ccr_direct_org_billing` tinyint NOT NULL DEFAULT '0' COMMENT 'Enable Copilot code review for all members of this organization, including those without a Copilot license (Organization or Business)',
  `bento` tinyint NOT NULL DEFAULT '0',
  `spaces_individual_access` tinyint NOT NULL DEFAULT '0' COMMENT 'The policy for allowing organization members to create individually owned Copilot Spaces',
  `spaces_individual_sharing` tinyint NOT NULL DEFAULT '0' COMMENT 'The policy for individual sharing in Copilot Spaces for members of an organization',
  `restrict_to_azure` tinyint NOT NULL DEFAULT '0',
  `tulip` tinyint NOT NULL DEFAULT '0',
  `sunflower` tinyint NOT NULL DEFAULT '0',
  `peony` tinyint NOT NULL DEFAULT '0',
  `lotus` tinyint NOT NULL DEFAULT '0',
  `arcticfox` tinyint NOT NULL DEFAULT '0',
  `watermelon` tinyint NOT NULL DEFAULT '0',
  `hulk` tinyint NOT NULL DEFAULT '0',
  `captainamerica` tinyint NOT NULL DEFAULT '0',
  `antman` tinyint NOT NULL DEFAULT '0',
  `blackpanther` tinyint NOT NULL DEFAULT '0',
  `wintersoldier` tinyint NOT NULL DEFAULT '0',
  `cucumber` tinyint NOT NULL DEFAULT '0',
  `blueberry` tinyint NOT NULL DEFAULT '0',
  `restrict_to_fedramp` tinyint NOT NULL DEFAULT '0',
  `memory` tinyint NOT NULL DEFAULT '0',
  `cherry` tinyint NOT NULL DEFAULT '0',
  `model_native_search` tinyint NOT NULL DEFAULT '0' COMMENT 'policy for model native search usage by Copilot',
  `cca_direct_org_billing` tinyint NOT NULL DEFAULT '0' COMMENT 'Enable Copilot code agent for all members of this organization, including those without a Copilot license (Organization or Business)',
  `restrict_to_data_residency` tinyint NOT NULL DEFAULT '0' COMMENT 'Whether to restrict this configurable to data residency compliant models only',
  `cli_direct_org_billing` tinyint NOT NULL DEFAULT '0' COMMENT 'Enable Copilot CLI for all members of this organization, including those without a Copilot license (Organization or Business)',
  `agent_mode_enterprise_management` tinyint NOT NULL DEFAULT '0' COMMENT 'Enterprise toggle to lock org admins from changing the agent_mode policy',
  `coding_agent_enterprise_management` tinyint NOT NULL DEFAULT '0' COMMENT 'Enterprise toggle to lock org admins from changing the coding_agent policy',
  `client_byok` tinyint NOT NULL DEFAULT '2' COMMENT 'Enterprise and org toggle to enable client-side Bring Your Own Key (BYOK)',
  `snippy_opt_out` tinyint NOT NULL DEFAULT '0' COMMENT 'Whether to opt out of snippy',
  `cli_remote_control` tinyint NOT NULL DEFAULT '0' COMMENT 'Enable Copilot CLI remote control — allows CLI sessions to be monitored and steered from cloud-based clients (Organization or Business)',
  `models_default` tinyint NOT NULL DEFAULT '2' COMMENT 'Default setting for model policies. Customers can configure this to automatically enable/disable new models.',
  `features_default` tinyint NOT NULL DEFAULT '2' COMMENT 'Default setting for feature policies. Customers can configure this to automatically enable/disable new features.',
  `blackbird_external_indexing` tinyint NOT NULL DEFAULT '0' COMMENT 'Policy setting for Blackbird external indexing.',
  `cli_cloud_session_storage` tinyint NOT NULL DEFAULT '0' COMMENT 'Enable storing CLI and VSCode sessions in the cloud.',
  `cca_agentic_github_apps` tinyint NOT NULL DEFAULT '0' COMMENT 'If enabled, enterprise admins can turn on agentic features provided by GitHub Apps',
  `experimental_auto_models` tinyint NOT NULL DEFAULT '0' COMMENT 'Policy setting for access to experimental auto models in Copilot.',
  `copilot_usage_records_api` tinyint NOT NULL DEFAULT '0' COMMENT 'If enabled, Enterprises will be able to view their members Copilot Usage Records via API',
  `copilot_usage_records_streaming` tinyint NOT NULL DEFAULT '0' COMMENT 'If enabled, Enterprises will be able to view their members Copilot Usage Records via streaming',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_index_copilot_configurations_on_configurable` (`configurable_id`,`configurable_type`),
  KEY `idx_configurable_type_pending_plan_downgrade_date` (`configurable_type`,`pending_plan_downgrade_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_custom_instructions`;
CREATE TABLE `copilot_custom_instructions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` bigint unsigned NOT NULL,
  `owner_type` varchar(20) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `prompt` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `updated_by_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_custom_instructions_on_owner_id_and_owner_type` (`owner_id`,`owner_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_custom_keys`;
CREATE TABLE `copilot_custom_keys` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(60) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'User-given name',
  `kredz_key` varchar(60) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'Identifier for where the key is stored in kredz',
  `provider` int NOT NULL DEFAULT '0',
  `organization_id` bigint unsigned DEFAULT NULL,
  `business_id` bigint unsigned DEFAULT NULL,
  `deployment_url` text COLLATE utf8mb4_unicode_520_ci COMMENT 'Azure deployment URL if applicable',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `encrypted_secret_value` text COLLATE utf8mb4_unicode_520_ci,
  `provider_data` text COLLATE utf8mb4_unicode_520_ci COMMENT 'provider-specific configuration data',
  PRIMARY KEY (`id`),
  KEY `index_copilot_custom_keys_on_organization_id_and_kredz_key` (`organization_id`,`kredz_key`),
  KEY `index_copilot_custom_keys_on_organization_id_and_name` (`organization_id`,`name`),
  KEY `index_copilot_custom_keys_on_business_id_and_kredz_key` (`business_id`,`kredz_key`),
  KEY `index_copilot_custom_keys_on_business_id_and_name` (`business_id`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_custom_model_capabilities`;
CREATE TABLE `copilot_custom_model_capabilities` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `copilot_custom_model_id` bigint unsigned NOT NULL,
  `max_output_tokens` int unsigned NOT NULL DEFAULT '0',
  `max_input_tokens` int unsigned NOT NULL DEFAULT '0',
  `tool_calling` tinyint(1) NOT NULL DEFAULT '0',
  `vision` tinyint(1) NOT NULL DEFAULT '0',
  `thinking` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `endpoint_type` tinyint unsigned NOT NULL DEFAULT '0',
  `streaming` tinyint(1) NOT NULL DEFAULT '0',
  `max_context_window` int unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_on_copilot_custom_model_id_8f662cf553` (`copilot_custom_model_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_custom_model_rules`;
CREATE TABLE `copilot_custom_model_rules` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `status` tinyint(1) NOT NULL COMMENT 'Whether the model(s) are enabled by this rule',
  `target_id` bigint unsigned NOT NULL COMMENT 'The custom key or custom model this rule affects',
  `target_type` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Whether target_id references copilot_custom_models or copilot_custom_keys',
  `business_id` bigint unsigned NOT NULL COMMENT 'The enterprise that made this rule',
  `organization_id` bigint unsigned DEFAULT NULL COMMENT 'The specific org this rule affects, if any',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_on_business_id_target_id_target_type_organizati_ef34cc4b1a` (`business_id`,`target_id`,`target_type`,`organization_id`),
  KEY `idx_on_organization_id_business_id_4816ac8dc1` (`organization_id`,`business_id`),
  KEY `index_copilot_custom_model_rules_on_target_id_and_target_type` (`target_id`,`target_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_custom_models`;
CREATE TABLE `copilot_custom_models` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(60) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'User-provided name',
  `slug` varchar(80) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Identifier for this model from the provider',
  `copilot_chat_enabled` tinyint(1) NOT NULL DEFAULT '1',
  `custom_key_id` bigint unsigned NOT NULL COMMENT 'Reference to custom_keys record',
  `provider_data` text COLLATE utf8mb4_unicode_520_ci COMMENT 'provider-specific configuration data',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_custom_models_on_custom_key_id_and_name` (`custom_key_id`,`name`),
  UNIQUE KEY `index_copilot_custom_models_on_custom_key_id_and_slug` (`custom_key_id`,`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_engaged_oss_repositories`;
CREATE TABLE `copilot_engaged_oss_repositories` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL COMMENT 'The repository',
  `language_name_id` bigint unsigned NOT NULL COMMENT 'The language the repository qualifies for engaged oss',
  `license_id` bigint unsigned NOT NULL COMMENT 'The license the repository uses',
  `rank` bigint unsigned NOT NULL DEFAULT '0' COMMENT 'The rank of the repository for the language',
  `stargazer_count` bigint unsigned NOT NULL DEFAULT '0' COMMENT 'The number of stargazers the repository has when updated',
  `fork_count` bigint unsigned NOT NULL DEFAULT '0' COMMENT 'The number of forks the repository has when updated',
  `last_pushed_at` datetime(6) DEFAULT NULL COMMENT 'The last time the repository was pushed to when updated',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_engaged_oss_repositories_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_engaged_oss_users`;
CREATE TABLE `copilot_engaged_oss_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `language` varchar(20) COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT 'all' COMMENT 'the language of the processor job (default all for all of github)',
  `role` varchar(20) COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT 'read' COMMENT 'the highest role of the user in this repo',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_engaged_oss_users_on_repository_id_and_user_id` (`repository_id`,`user_id`),
  KEY `index_copilot_engaged_oss_users_on_language` (`language`),
  KEY `index_copilot_engaged_oss_users_on_role` (`role`),
  KEY `index_copilot_engaged_oss_users_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_entity_memberships`;
CREATE TABLE `copilot_entity_memberships` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `entity_id` bigint unsigned NOT NULL,
  `entity_type` enum('User','EnterpriseTeam','Business') COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT 'User',
  `copilot_insights_activities_id` bigint unsigned DEFAULT NULL,
  `platform_insights_activities_id` bigint unsigned DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `membership_history` varbinary(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_entity_memberships_on_user_and_entity` (`user_id`,`entity_id`,`entity_type`),
  KEY `index_copilot_insights_activities_id` (`copilot_insights_activities_id`),
  KEY `index_platform_insights_activities_id` (`platform_insights_activities_id`),
  KEY `index_copilot_entity_memberships_on_entity_id_and_entity_type` (`entity_id`,`entity_type`),
  KEY `index_copilot_entity_memberberships_type_on_entity_type_and_cia` (`entity_type`,`copilot_insights_activities_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_extensions_agreement_signatures`;
CREATE TABLE `copilot_extensions_agreement_signatures` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `signatory_id` bigint unsigned NOT NULL COMMENT 'The user who signed the agreement',
  `organization_id` bigint unsigned DEFAULT NULL COMMENT 'Optional. The organization that the user signed the agreement on behalf of',
  `business_id` bigint unsigned DEFAULT NULL COMMENT 'Optional. The business that the user signed the agreement on behalf of',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_copilot_extensions_agreement_signatures_on_signatory_id` (`signatory_id`),
  KEY `idx_on_organization_id_85e1de1099` (`organization_id`),
  KEY `index_copilot_extensions_agreement_signatures_on_business_id` (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_firewall_allowlists`;
CREATE TABLE `copilot_firewall_allowlists` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organization_id` bigint unsigned DEFAULT NULL COMMENT 'Denormalized org ID for efficient queries',
  `resource_type` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Business, Organization, or Repository',
  `resource_id` bigint unsigned NOT NULL COMMENT 'The entity that owns this allowlist',
  `rules` json NOT NULL DEFAULT (json_array()) COMMENT 'JSON array of allowlist rules (domains, IPs, URLs)',
  `updated_by_id` bigint unsigned NOT NULL COMMENT 'The user who last updated the record',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_firewall_allowlists_on_resource` (`resource_type`,`resource_id`),
  KEY `index_copilot_firewall_allowlists_on_org_id` (`organization_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_ide_notifications`;
CREATE TABLE `copilot_ide_notifications` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `notification_id` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'This represents the notification message to be sent',
  `acknowledged_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_ide_notifications_on_user_id_and_notification_id` (`user_id`,`notification_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_ignores`;
CREATE TABLE `copilot_ignores` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organization_id` bigint unsigned DEFAULT NULL COMMENT 'The organization that ultimately owns this exclusion document',
  `resource_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `resource_id` bigint NOT NULL COMMENT 'The repository or organization that owns this exclusion document',
  `document` mediumblob COMMENT 'The exclusion document itself',
  `updated_by_id` bigint unsigned DEFAULT NULL COMMENT 'The user who last updated the record',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_ignores_on_resource` (`resource_type`,`resource_id`),
  KEY `index_copilot_ignores_on_organization_id` (`organization_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_indexed_repositories`;
CREATE TABLE `copilot_indexed_repositories` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organization_id` bigint unsigned DEFAULT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `markdown_only` tinyint(1) NOT NULL DEFAULT '0',
  `embeddings_indexing_only` tinyint(1) NOT NULL DEFAULT '0',
  `last_requested_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'The last time the repo was requested for indexing or search',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_indexed_repositories_on_repository_id` (`repository_id`),
  KEY `index_copilot_indexed_repositories_on_organization_id` (`organization_id`),
  KEY `index_on_last_requested_at_and_repository_id` (`last_requested_at`,`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_insights_activities`;
CREATE TABLE `copilot_insights_activities` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `engagement_events` blob,
  `loc_suggested` blob,
  `loc_accepted` blob,
  `code_suggestion_events` blob,
  `code_suggestion_events_accepted` blob,
  `prs_merged` blob,
  `pr_lead_time` blob,
  `commit_count` blob,
  `engagement_events_updated_at` datetime(6) DEFAULT NULL,
  `loc_suggested_updated_at` datetime(6) DEFAULT NULL,
  `loc_accepted_updated_at` datetime(6) DEFAULT NULL,
  `code_suggestion_events_updated_at` datetime(6) DEFAULT NULL,
  `code_suggestion_events_accepted_updated_at` datetime(6) DEFAULT NULL,
  `prs_merged_updated_at` datetime(6) DEFAULT NULL,
  `pr_lead_time_updated_at` datetime(6) DEFAULT NULL,
  `commit_count_updated_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_key_values`;
CREATE TABLE `copilot_key_values` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` blob NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `expires_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_key_values_on_key` (`key`),
  KEY `index_copilot_key_values_on_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_limited_users`;
CREATE TABLE `copilot_limited_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `subscribed_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_limited_users_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_mcp_allowlists`;
CREATE TABLE `copilot_mcp_allowlists` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `entity_id` bigint unsigned NOT NULL COMMENT 'The ID of the entity (business or organization)',
  `entity_type` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'The type of the entity (Business or Organization)',
  `allowlist_url` text COLLATE utf8mb4_unicode_520_ci COMMENT 'The MCP allowlist URL',
  `updated_by_id` bigint unsigned DEFAULT NULL COMMENT 'The user who last updated the record',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `registry_access` tinyint unsigned NOT NULL DEFAULT '0' COMMENT 'Indicates MCP Registry URL access',
  `registry_type` tinyint unsigned NOT NULL DEFAULT '0' COMMENT 'Indicates MCP Registry type: 0 = external, 1 = github',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_mcp_allowlists_on_entity` (`entity_type`,`entity_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_metric_summaries`;
CREATE TABLE `copilot_metric_summaries` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` bigint unsigned NOT NULL,
  `owner_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `total_seats` int NOT NULL,
  `active_seats` int NOT NULL,
  `inactive_seats` int NOT NULL,
  `dormant_seats` int NOT NULL,
  `code_suggestion_events` json DEFAULT NULL,
  `loc_generated` json DEFAULT NULL,
  `commit_counts` json DEFAULT NULL,
  `prs_merged` json DEFAULT NULL,
  `pr_lead_times` json DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_cms_on_owner_and_dates` (`owner_id`,`owner_type`,`start_date`,`end_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_metrics_report_links`;
CREATE TABLE `copilot_metrics_report_links` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `business_id` bigint unsigned NOT NULL COMMENT 'The enterprise ID that this report belongs to',
  `report_type` tinyint NOT NULL,
  `download_links` json NOT NULL COMMENT 'The blob storage URLs for downloading the report files',
  `report_end_day` date NOT NULL COMMENT 'The end day of the report period',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_metrics_report_links_unique` (`business_id`,`report_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_monitored_users`;
CREATE TABLE `copilot_monitored_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_monitored_users_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_plg_key_values`;
CREATE TABLE `copilot_plg_key_values` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` blob NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `expires_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_plg_key_values_on_key` (`key`),
  KEY `index_copilot_plg_key_values_on_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_policies`;
CREATE TABLE `copilot_policies` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `config_name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `display_name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `description` json NOT NULL COMMENT 'Nested structure with business/org/user descriptions',
  `policy_config` json NOT NULL COMMENT 'Scalar policy configuration',
  `plans` json NOT NULL COMMENT 'Array of plan strings that have access to this policy',
  `feature_flag` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_by_login` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Username of Hubber who created this in Stafftools',
  `github_issue_url` text COLLATE utf8mb4_unicode_520_ci COMMENT 'GitHub issue with more details about the policy',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_policies_on_config_name` (`config_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_premium_interactions`;
CREATE TABLE `copilot_premium_interactions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned DEFAULT NULL COMMENT 'User ID of the user who made the request can be null until the request is completed',
  `user_tracking_id` varchar(32) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Tracking ID for the user, used for tracking purposes',
  `owner_id` bigint unsigned NOT NULL COMMENT 'Billable entity for this interaction',
  `owner_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Type of the owner, can be a user or an organization or a business',
  `interaction_id` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Unique ID for the interaction, but not unique for owner',
  `interaction_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Type of the interaction',
  `premium_request` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Whether this request is a premium request or not',
  `model` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Model used for this interaction',
  `token_count` int NOT NULL DEFAULT '0' COMMENT 'Token count for this interaction',
  `overage` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Whether this interaction is overage or not',
  `interaction_details` json DEFAULT NULL COMMENT 'Other metadata for the interaction',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `organization_id` bigint unsigned DEFAULT NULL COMMENT 'ID of the Organization, used for usage reports',
  `business_id` bigint unsigned DEFAULT NULL COMMENT 'ID of the Business, used for usage reports',
  PRIMARY KEY (`id`),
  KEY `idx_copilot_premium_interactions_user_id` (`user_id`),
  KEY `idx_copilot_premium_interactions_owner_id_and_owner_type` (`owner_id`,`owner_type`),
  KEY `idx_copilot_premium_interactions_user_tracking_id` (`user_tracking_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_public_users`;
CREATE TABLE `copilot_public_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `settings` json DEFAULT NULL COMMENT 'The user''s settings and details for Copilot',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_public_users_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_required_authorizations`;
CREATE TABLE `copilot_required_authorizations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `owner_id` bigint NOT NULL,
  `reason` varchar(1024) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `state` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `index_copilot_required_authorizations_on_owner` (`owner_type`,`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_seat_assignments`;
CREATE TABLE `copilot_seat_assignments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` bigint unsigned DEFAULT NULL,
  `owner_type` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `organization_id` bigint DEFAULT NULL,
  `assignable_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `assignable_id` bigint NOT NULL,
  `pending_cancellation_date` date DEFAULT NULL,
  `assigning_user_id` bigint DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `access_revoked_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_copilot_seat_assignments_on_organization_id` (`organization_id`),
  KEY `index_copilot_seat_assignments_on_assignables` (`assignable_id`,`assignable_type`),
  KEY `index_copilot_seat_assignments_on_owner_id_and_owner_type` (`owner_id`,`owner_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_seat_emissions`;
CREATE TABLE `copilot_seat_emissions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` bigint unsigned DEFAULT NULL,
  `owner_type` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `emission` json NOT NULL COMMENT 'The emission message (in JSON) that was sent',
  `unique_id` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'UUID - The unique ID of the seat emission',
  `occurred_at` datetime(6) NOT NULL COMMENT 'The date/time that the seat emission occurred',
  `quantity` decimal(22,9) NOT NULL DEFAULT '0.000000000' COMMENT 'The quantity of the seat emission',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_copilot_seat_emissions_on_unique_id` (`unique_id`),
  KEY `index_copilot_seat_emissions_on_occurred_at` (`occurred_at`),
  KEY `index_copilot_seat_assignments_on_owner_id_and_owner_type` (`owner_id`,`owner_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_seat_histories`;
CREATE TABLE `copilot_seat_histories` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` bigint unsigned DEFAULT NULL,
  `owner_type` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `business_id` bigint DEFAULT NULL,
  `organization_id` bigint DEFAULT NULL,
  `seat_id` bigint DEFAULT NULL,
  `assigned_user_id` bigint DEFAULT NULL,
  `seat_created_at` date DEFAULT NULL,
  `seat_deleted_at` date DEFAULT NULL,
  `billing_cycle_start_date` date NOT NULL,
  `billing_cycle_end_date` date NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_seat_histories_on_seat_id` (`seat_id`),
  KEY `index_copilot_seat_histories_on_assigned_user_id` (`assigned_user_id`),
  KEY `business_and_billing_cycle` (`business_id`,`billing_cycle_start_date`,`billing_cycle_end_date`),
  KEY `organization_and_billing_cycle` (`organization_id`,`billing_cycle_start_date`,`billing_cycle_end_date`),
  KEY `index_owner_id_owner_type_seat_created_at` (`owner_id`,`owner_type`,`seat_created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_seats`;
CREATE TABLE `copilot_seats` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organization_id` bigint DEFAULT NULL,
  `copilot_seat_assignment_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `assigned_user_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_copilot_seats_on_organization_id` (`organization_id`),
  KEY `index_copilot_seats_on_copilot_seat_assignment_id` (`copilot_seat_assignment_id`),
  KEY `index_copilot_seats_on_assigned_user_id` (`assigned_user_id`),
  KEY `index_copilot_seats_on_org_user_assignment` (`organization_id`,`assigned_user_id`,`copilot_seat_assignment_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_setting_rules`;
CREATE TABLE `copilot_setting_rules` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `setting_id` bigint unsigned NOT NULL,
  `condition_expression_id` bigint unsigned NOT NULL,
  `rule_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `priority` int unsigned NOT NULL DEFAULT '0',
  `parameters` json DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_copilot_setting_rules_on_setting_id` (`setting_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_settings`;
CREATE TABLE `copilot_settings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `resource_id` bigint unsigned NOT NULL,
  `resource_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` json DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_settings_on_resource_and_name` (`resource_id`,`resource_type`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_shared_threads`;
CREATE TABLE `copilot_shared_threads` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `slug` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `thread_id` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `shared_at` datetime(6) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_shared_threads_on_slug` (`slug`),
  UNIQUE KEY `index_copilot_shared_threads_on_thread_id` (`thread_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_swe_agent_configuration`;
CREATE TABLE `copilot_swe_agent_configuration` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `resource_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `resource_id` bigint NOT NULL COMMENT 'The repository or organization that owns this configuration',
  `mcp_configuration` blob COMMENT 'The mcp configuration document',
  `updated_by_id` bigint unsigned DEFAULT NULL COMMENT 'The user who last updated the record',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `require_actions_workflow_approval_for_copilot_prs` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Whether to require human approval for workflow runs on Copilot pull requests',
  `use_codeql` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Whether copilot_swe_agent uses code scanning with CodeQL to review its work',
  `use_ccr` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Whether copilot_swe_agent uses Copilot Code Review to check its work',
  `use_secret_scanning` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Whether copilot_swe_agent uses secret scanning to check its work',
  `use_dependency_vuln_checks` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Whether copilot_swe_agent uses dependency vulnerability checks against the GitHub Advisory Database to check its work',
  `runner_type` enum('standard','labeled') COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT 'standard' COMMENT 'The default runner type for copilot runs.  Standard used a default runner, labeled uses a series of labels',
  `runner_group_name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT '' COMMENT 'The runner group to use, when runner_type is of type ''labeled''',
  `runner_labels` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT '' COMMENT 'The runner labels to use, when runner_type is of type ''labeled''. A comma-delimited list of labels',
  `allow_repo_custom_runner` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Allows repositories to override the organization runner setting',
  `memory_disabled` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Whether agentic memory is disabled for this repository',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_swe_agent_configuration_on_resource` (`resource_type`,`resource_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_swe_agent_repo_enablements`;
CREATE TABLE `copilot_swe_agent_repo_enablements` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` bigint unsigned NOT NULL COMMENT 'The ID of the owner of the repository',
  `repository_id` bigint unsigned NOT NULL COMMENT 'The ID of the enabled repository',
  `enabled_by_id` bigint unsigned NOT NULL COMMENT 'The ID of the user that enabled the feature for this repository',
  `created_at` datetime(6) NOT NULL COMMENT 'The time when the feature was enabled for this repository',
  PRIMARY KEY (`id`),
  KEY `index_copilot_swe_agent_repo_enablements_on_owner_id` (`owner_id`),
  KEY `index_copilot_swe_agent_repo_enablements_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_tech_preview_users`;
CREATE TABLE `copilot_tech_preview_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `sent_email_count` int NOT NULL DEFAULT '0' COMMENT 'incremented after each email sent and checked before sending',
  `subscribed` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_tech_preview_users_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `copilot_usage_metrics`;
CREATE TABLE `copilot_usage_metrics` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `business_id` bigint DEFAULT NULL COMMENT 'The business that this usage metric is under (if any)',
  `organization_id` bigint DEFAULT NULL COMMENT 'The organization that this usage metric is under',
  `team_id` bigint DEFAULT NULL COMMENT 'The team that this usage metric is under',
  `enterprise_team_id` bigint DEFAULT NULL COMMENT 'The enterprise team that this usage metric is under',
  `language_name_id` bigint DEFAULT NULL COMMENT 'The language this usage metric is for',
  `date` date NOT NULL COMMENT 'The date this usage metric is for',
  `suggestions_count` int NOT NULL DEFAULT '0' COMMENT 'The number of suggestions made',
  `acceptances_count` int NOT NULL DEFAULT '0' COMMENT 'The number of suggestions accepted',
  `lines_suggested` int NOT NULL DEFAULT '0' COMMENT 'The number of lines suggested',
  `lines_accepted` int NOT NULL DEFAULT '0' COMMENT 'The number of lines accepted',
  `active_users` int NOT NULL DEFAULT '0' COMMENT 'The number of active users (have accepted at least one suggestion)',
  `chat_messages` int NOT NULL DEFAULT '0' COMMENT 'The number of chat messages sent',
  `chat_active_users` int NOT NULL DEFAULT '0' COMMENT 'The number of active chat users',
  `chat_acceptances` int NOT NULL DEFAULT '0' COMMENT 'The number of chat messages sent',
  `editor` int NOT NULL DEFAULT '0' COMMENT 'The editor this usage metric is for',
  `metadata` json NOT NULL COMMENT 'The metadata for this usage metric',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `language` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'The language this usage metric is for (if no matching LanguageName)',
  `schema_version` int DEFAULT NULL COMMENT 'Version of the schema present in the metadata column',
  PRIMARY KEY (`id`),
  KEY `index_copilot_usage_metrics_on_business_id` (`business_id`),
  KEY `index_copilot_usage_metrics_on_organization_id` (`organization_id`),
  KEY `index_copilot_usage_metrics_on_team_id` (`team_id`),
  KEY `index_copilot_usage_metrics_on_date` (`date`),
  KEY `index_copilot_usage_metrics_on_enterprise_team_id` (`enterprise_team_id`),
  KEY `index_schema_version_date` (`schema_version`,`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `custom_copilot_resources`;
CREATE TABLE `custom_copilot_resources` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `custom_copilot_id` bigint unsigned NOT NULL,
  `copilot_chat_attachment_id` bigint unsigned DEFAULT NULL,
  `resource_type` int NOT NULL,
  `metadata` json NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `denormalized_repository_id` bigint unsigned DEFAULT NULL,
  `organization_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_on_copilot_chat_attachment_id_custom_copilot_id_3de3112116` (`copilot_chat_attachment_id`,`custom_copilot_id`),
  KEY `index_custom_copilot_resources_on_custom_copilot_id` (`custom_copilot_id`),
  KEY `index_custom_copilot_resources_on_denormalized_repository_id` (`denormalized_repository_id`),
  KEY `index_custom_copilot_resources_on_organization_id` (`organization_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `custom_copilots`;
CREATE TABLE `custom_copilots` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `description` text COLLATE utf8mb4_unicode_520_ci,
  `icon_url` text COLLATE utf8mb4_unicode_520_ci,
  `owner_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `owner_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `general_instructions` text COLLATE utf8mb4_unicode_520_ci,
  `slug` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `icon_type` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `icon_color` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `number` bigint unsigned DEFAULT NULL,
  `creator_id` bigint unsigned DEFAULT NULL COMMENT 'The ID of the user who created the custom copilot.',
  `visibility` int NOT NULL DEFAULT '0',
  `base_role` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_custom_copilots_on_owner_id_and_owner_type_and_slug` (`owner_id`,`owner_type`,`slug`),
  UNIQUE KEY `index_custom_copilots_on_owner_id_and_owner_type_and_name` (`owner_id`,`owner_type`,`name`),
  UNIQUE KEY `index_custom_copilots_owner_number` (`owner_id`,`owner_type`,`number`),
  KEY `index_custom_copilots_on_owner` (`owner_type`,`owner_id`),
  KEY `index_custom_copilots_on_creator_id` (`creator_id`),
  KEY `index_custom_copilot_on_owner_id_and_owner_type_and_visibility` (`owner_id`,`owner_type`,`visibility`),
  KEY `index_custom_copilot_on_owner_id_and_owner_type_and_base_role` (`owner_id`,`owner_type`,`base_role`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `favorite_spark_workbenches`;
CREATE TABLE `favorite_spark_workbenches` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `spark_workbench_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_favorite_spark_workbenches_on_user_id` (`user_id`),
  KEY `index_favorite_spark_workbenches_on_spark_workbench_id` (`spark_workbench_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `integration_agent_sources`;
CREATE TABLE `integration_agent_sources` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `integration_id` bigint unsigned NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `commit_oid` varchar(64) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `update_message` text COLLATE utf8mb4_unicode_520_ci,
  `model_vendors` text COLLATE utf8mb4_unicode_520_ci,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_integration_agent_sources_on_integration_id` (`integration_id`),
  KEY `index_integration_agent_sources_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `integration_agents`;
CREATE TABLE `integration_agents` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `integration_id` bigint unsigned NOT NULL,
  `url` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `description` blob NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `client_authorization_url` text COLLATE utf8mb4_unicode_520_ci,
  `skill_data` json DEFAULT NULL,
  `app_type` enum('disabled','agent','skill') COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT 'disabled',
  `token_exchange_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `token_exchange_url` text COLLATE utf8mb4_unicode_520_ci,
  `third_party_token_header_key` text COLLATE utf8mb4_unicode_520_ci,
  `third_party_token_header_value` text COLLATE utf8mb4_unicode_520_ci,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_integration_agents_on_integration_id` (`integration_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `integration_installation_agent_consents`;
CREATE TABLE `integration_installation_agent_consents` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `integration_installation_id` bigint unsigned NOT NULL,
  `integration_agent_source_id` bigint unsigned NOT NULL,
  `approver_id` bigint unsigned NOT NULL,
  `approved_at` datetime(6) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_on_integration_installation_id_473e5dc709` (`integration_installation_id`),
  KEY `idx_on_integration_agent_source_id_0e09c7af37` (`integration_agent_source_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `mcp_server_configs`;
CREATE TABLE `mcp_server_configs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `mcp_server_id` bigint unsigned NOT NULL,
  `code_verifier` text COLLATE utf8mb4_unicode_520_ci,
  `access_token` text COLLATE utf8mb4_unicode_520_ci,
  `refresh_token` text COLLATE utf8mb4_unicode_520_ci,
  `access_token_expires_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `display_name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_copilot_external_tokens_on_user_id_and_mcp_server_id` (`user_id`,`mcp_server_id`),
  UNIQUE KEY `index_mcp_server_configs_on_user_id_and_display_name` (`user_id`,`display_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `mcp_servers`;
CREATE TABLE `mcp_servers` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `url` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `oauth_client_id` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `oauth_client_secret` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `oauth_redirect_uri` text COLLATE utf8mb4_unicode_520_ci,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_mcp_servers_on_url_and_oauth_redirect_uri` (`url`(255),`oauth_redirect_uri`(255))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `model_registry_cache`;
CREATE TABLE `model_registry_cache` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `description` json DEFAULT NULL,
  `plans` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `feature_flag` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `internal` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `model_key` varchar(30) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `preview` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates if the model is a preview model',
  `documentation_link` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `documentation_link_text` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `inline_approval_enabled` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'Indicates if inline approval is enabled for the model',
  `vendor` varchar(32) COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT 'Unknown' COMMENT 'Indicates what vendor (e.g. OpenAI, Anthropic, etc.) the model is from',
  `policy_pro_feature_flag` varchar(128) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'Feature flag for Policy Pro access',
  `policy_ga_feature_flag` varchar(128) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'Feature flag for Policy GA access',
  `policy_rollout_complete_feature_flag` varchar(128) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'Feature flag indicating completion of Policy rollout',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_model_registry_cache_on_model_key` (`model_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `orca_models`;
CREATE TABLE `orca_models` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organization_id` bigint unsigned NOT NULL,
  `resource` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `deployment` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `pipeline_id` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `pipeline_group_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_orca_models_on_pipeline_id` (`pipeline_id`),
  KEY `index_orca_models_on_organization_id` (`organization_id`),
  KEY `index_orca_models_on_pipeline_group_id` (`pipeline_group_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `orca_pipeline_groups`;
CREATE TABLE `orca_pipeline_groups` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organization_id` bigint unsigned NOT NULL,
  `name` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_orca_pipeline_groups_on_organization_id` (`organization_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `orca_rollouts`;
CREATE TABLE `orca_rollouts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organization_id` bigint unsigned NOT NULL,
  `orca_pipeline_group_id` bigint unsigned NOT NULL,
  `control_model_id` bigint unsigned DEFAULT NULL,
  `treatment_model_id` bigint unsigned DEFAULT NULL,
  `percentage` int unsigned NOT NULL DEFAULT '0',
  `evaluation_started_at` datetime(6) DEFAULT NULL,
  `evaluation_duration` int unsigned DEFAULT NULL,
  `status` varchar(16) COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT 'ready',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_orca_rollouts_on_organization_id` (`organization_id`),
  KEY `index_orca_rollouts_on_orca_pipeline_group_id` (`orca_pipeline_group_id`),
  KEY `index_orca_rollouts_on_control_model_id` (`control_model_id`),
  KEY `index_orca_rollouts_on_treatment_model_id` (`treatment_model_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `runtime_app_deploys`;
CREATE TABLE `runtime_app_deploys` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `runtime_app_id` bigint unsigned NOT NULL COMMENT 'Runtime App this deployment belongs to',
  `revision` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Either the SHA or another identifier for the deployment',
  `display_name` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'User-assigned slug of the app',
  `url` tinytext COLLATE utf8mb4_unicode_520_ci COMMENT 'URL of the deployed app',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_runtime_app_deploys_on_runtime_app_id` (`runtime_app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `runtime_app_owners`;
CREATE TABLE `runtime_app_owners` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` bigint unsigned NOT NULL COMMENT 'User/Org ID of this Spark owner',
  `permanent_name` varchar(20) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Permanent identifier to use with ACA',
  `last_seen_login` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Last seen login for user/org',
  `deploy_login` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'Name to use with ACA on deployment',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_runtime_app_owners_on_owner_id` (`owner_id`),
  UNIQUE KEY `index_runtime_app_owners_on_permanent_name` (`permanent_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `runtime_apps`;
CREATE TABLE `runtime_apps` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL COMMENT 'User ID of the app creator',
  `permanent_name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Permanent slug of the app used in the default URL',
  `friendly_name` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'User-assigned slug of the app',
  `description` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'User-assigned description of the app',
  `username` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Login handle of the app creator at time of creation',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `visibility` int DEFAULT '0',
  `owner_id` bigint unsigned DEFAULT NULL COMMENT 'User/Org ID of this Spark owner',
  `organization_id` bigint unsigned DEFAULT NULL COMMENT 'Organization if the Spark is org owned',
  `visibility_organization_id` bigint unsigned DEFAULT NULL COMMENT 'The organization that this RuntimeApp is visible to, if selected.',
  `read_only_kv` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'If the data store is read-only',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_runtime_apps_on_permanent_name` (`permanent_name`),
  KEY `index_runtime_apps_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `runtime_key_values`;
CREATE TABLE `runtime_key_values` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` blob NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `expires_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_runtime_key_values_on_key` (`key`),
  KEY `index_runtime_key_values_on_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `self_serve_banners`;
CREATE TABLE `self_serve_banners` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `slug` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `body` varchar(1024) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `cta_url` text COLLATE utf8mb4_unicode_520_ci,
  `cta_text` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `visibility` tinyint DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_self_serve_banners_on_slug` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `spark_model_rate_limits`;
CREATE TABLE `spark_model_rate_limits` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `model` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_spark_model_rate_limits_on_model_and_created_at` (`model`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `spark_workbench_iterations`;
CREATE TABLE `spark_workbench_iterations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `spark_workbench_id` bigint unsigned NOT NULL,
  `prompt` blob,
  `sha` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `iteration_type` tinyint unsigned DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `suggestions` json DEFAULT NULL,
  `parent_id` bigint unsigned DEFAULT NULL,
  `events` json DEFAULT NULL,
  `intent_summary` json DEFAULT NULL,
  `completion_summary` json DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_spark_workbench_iterations_on_spark_workbench_id` (`spark_workbench_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `spark_workbenches`;
CREATE TABLE `spark_workbenches` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `uuid` binary(16) NOT NULL,
  `repository_id` bigint unsigned DEFAULT NULL,
  `cloud_environment_id` bigint unsigned DEFAULT NULL,
  `initialized` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `runtime_app_id` bigint unsigned DEFAULT NULL COMMENT 'Runtime App this spark deploys to',
  `description` text COLLATE utf8mb4_unicode_520_ci,
  `current_iteration_id` bigint unsigned DEFAULT NULL,
  `last_snapshot_environment_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_spark_workbenches_on_uuid` (`uuid`),
  KEY `index_spark_workbenches_on_user_id` (`user_id`),
  KEY `index_spark_workbenches_on_repository_id` (`repository_id`),
  KEY `index_spark_workbenches_on_runtime_app_id` (`runtime_app_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `starred_custom_copilots`;
CREATE TABLE `starred_custom_copilots` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `custom_copilot_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_starred_custom_copilots_on_user_id_and_custom_copilot_id` (`user_id`,`custom_copilot_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
