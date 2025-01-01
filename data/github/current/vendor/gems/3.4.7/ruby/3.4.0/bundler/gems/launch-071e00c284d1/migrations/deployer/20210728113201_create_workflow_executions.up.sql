/* Create a new table to track reruns of workflow_builds */
CREATE TABLE IF NOT EXISTS `workflow_build_executions` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `plan_id` binary(16) DEFAULT NULL,
  `external_build_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '' COMMENT 'The ID from the build backend for this build',
  `workflow_build_id` bigint(20) NOT NULL COMMENT 'References the workflow build that this execution runs',
  `queued_at` datetime(6) DEFAULT NULL,
  `started_at` datetime(6) DEFAULT NULL,
  `completed_at` datetime(6) DEFAULT NULL,
  `state` int(11) NOT NULL DEFAULT '0' COMMENT 'See WorkflowState for values',
  `was_delayed` tinyint(1) DEFAULT '0',
  `actor_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `attempt` int(11) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`),
  UNIQUE KEY `by_plan_id` (`plan_id`),
  KEY `by_started_at` (`started_at`),
  KEY `by_queued_at` (`queued_at`),
  KEY `by_completed_at_queued_at` (`completed_at`,`queued_at`),
  KEY `by_actor_id_state_queued_at` (`actor_id`, `state`, `queued_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
