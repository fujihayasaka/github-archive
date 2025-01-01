/* Create tables for deployer */
CREATE TABLE IF NOT EXISTS `workflow_builds` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `uuid` binary(16),
  `queued_at` datetime(6) DEFAULT NULL,
  `created_at`  datetime(6) DEFAULT NULL,
  `completed_at` datetime(6) DEFAULT NULL,
  `gcp_project_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT 'GCP project ID - not used in AZP',
  `cloud_build_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT 'The ID from the build backend for this build',
  `external_build_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '' COMMENT 'The ID from the build backend for this build',
  `repository_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `commit_sha` varchar(40) NOT NULL,
  `workflow_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT 'Workflow identifier',
  `check_suite_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `request_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `state` int(11) NOT NULL DEFAULT '0' COMMENT 'See WorkflowState for values',
  `workflow_file_path` varchar(255) NOT NULL DEFAULT '.github/main.workflow',
  `reporting_metadata` JSON COMMENT 'See WorkflowMetadata for values',
  `token_permissions` JSON COMMENT 'See InstallationPermissions for values',
  `payload_id` bigint(20) unsigned DEFAULT NULL COMMENT 'ID of actions_workflow_payloads.payloads row',
  `workflow_run_id` bigint(20) unsigned DEFAULT '0' COMMENT 'The workflow run database ID',
  `workflow_run_number` bigint(20) unsigned DEFAULT '0' COMMENT 'The workflow run number',
  `delivery_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `installation_id` bigint(20) NOT NULL DEFAULT '0' COMMENT 'Id of the GitHub Actions app installation in the repository',

  -- present as of github/launch#1476
  `event` varchar(255) NOT NULL DEFAULT '' COMMENT 'The GitHub event that kicked off a build',
  -- added as of github/launch#1476, still unused
  `provider` varchar(255) NOT NULL DEFAULT '' COMMENT 'The build provider',

  PRIMARY KEY (`id`),
  UNIQUE KEY `by_check_suite_id` (`check_suite_id`),
  UNIQUE KEY `by_uuid` (`uuid`),
  KEY `by_created_at` (`created_at`),
  KEY `by_repository_id` (`repository_id`),
  KEY `by_provider_queued_at` (`provider`, `queued_at`),
  KEY `by_workflow_id_event_repository_id` (`workflow_id`, `event`, `repository_id`),
  KEY `by_external_build_id` (`external_build_id`),
  KEY `by_cloud_build_id` (`cloud_build_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS workflow_schedules
(
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `schedule_hash` varchar(255) NOT NULL COMMENT 'hash of properties that uniquely identify a schedule, see ScheduleHash',
  `repository_node_id` varchar(255) NOT NULL,
  `workflow_identifier` varchar(2048) NOT NULL COMMENT 'user defined name for a workflow',
  `workflow_file_path` varchar(255) NOT NULL,
  `environment` varchar(40) NOT NULL,

  -- scheduling columns
  `schedule` varchar(255) NOT NULL,
  `scatter_offset` double NOT NULL,
  `next_run_at` datetime(6) NOT NULL COMMENT 'when this should be run next',

  -- worker columns
  `locked_at` datetime(6) DEFAULT NULL COMMENT 'when a worker picked up the task, used to clear stale locks',
  `locked_by` varchar(255) DEFAULT NULL COMMENT 'ID unique to worker processing this run',

  -- metadata for workflow invocation
  `commit_sha` char(40) NOT NULL COMMENT 'commit from which schedules were read from workflow file',
  `installation_id` bigint(20) NOT NULL COMMENT 'Id of the GitHub Actions app installation in the repository the workflow is in',
  `actor_node_id` varchar(255) NOT NULL COMMENT 'last person to alter schedules via push or modifying default branch',
  `actor_login` varchar(255) NOT NULL,

  UNIQUE KEY `by_schedule_hash` (schedule_hash) COMMENT 'quickly synchronise schedules as they change',
  KEY `by_repository_node_id` (repository_node_id) COMMENT 'synchronisation requires us to find existing state for a repo',
  KEY `by_next_run_at` (next_run_at) COMMENT 'we poll to find tasks up next for execution',
  KEY `by_locked_by` (locked_by) COMMENT 'we poll to find rows a worker locked',
  KEY `by_locked_at` (locked_at) COMMENT 'we poll to identify rows that are assumed abandoned',
  KEY `by_locked_by_environment_next_run_at` (locked_by, environment, next_run_at) COMMENT 'optimises finding rows to work on'
) ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `azp_resources` (
	`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT PRIMARY KEY,
	-- NB: this should be called entity_id, as this table stores
	-- tenants for repos, owners and plans
	`repository_id` varchar(120) NOT NULL COMMENT 'stores a global_relay_id that can relate to any github type - see azp_resources.go',
	`entity_id` varchar(120) DEFAULT NULL COMMENT 'to replace repository_id',
	`environment` varchar(40) NOT NULL,
	`locked_at` datetime(6) DEFAULT NULL COMMENT 'the point at which the row was locked for creation',
	`locked_by` varchar(255) NOT NULL COMMENT 'the call that created the resources this row tracks',
	`created_at` datetime(6) DEFAULT NULL,
	`organization_name` varchar(255),
	`tenant_name` varchar(255) COMMENT 'to replace organization_name',
	`tenant_id` varchar(255) DEFAULT NULL COMMENT 'Stores a GUID for the tenant host',
	`project_name` varchar(255),
	`pipeline_id` int(11),
	`client_id` varchar(255),
	`private_key` mediumblob,
	UNIQUE KEY (`repository_id`, `environment`),
	UNIQUE KEY (`entity_id`, `environment`),
    KEY `by_entity_id` (`entity_id`),
    KEY `by_organization_name` (`organization_name`),
    KEY `by_tenant_name` (`tenant_name`),
    KEY `by_tenant_id` (`tenant_id`),
    KEY `by_locked_at` (`locked_at`),
    KEY `by_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS `workflow_jobs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `workflow_build_id` bigint(20) unsigned NOT NULL,
  `external_job_id` varchar(255) NOT NULL COMMENT 'The external AZP Job ID',
  `check_run_id` varchar(255) DEFAULT NULL COMMENT 'The GitHub Check Run ID',
  `created_at` datetime(6) DEFAULT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `by_external_job_id` (`external_job_id`),
  KEY `by_workflow_build_id` (`workflow_build_id`),
  KEY `by_check_run_id` (`check_run_id`),
  KEY `by_created_at` (`created_at`)
) ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
