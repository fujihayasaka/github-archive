ALTER TABLE `workflow_builds`
ADD COLUMN `check_suite_next_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL AFTER `check_suite_id`,
ADD COLUMN `repository_next_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL AFTER `repository_id`,
ADD COLUMN `executing_actor_next_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL AFTER `executing_actor_id`,
ADD UNIQUE KEY `by_check_suite_next_id` (`check_suite_next_id`),
ADD KEY `by_repository_next_id` (`repository_next_id`),
ADD KEY `by_workflow_id_event_repository_next_id` (`workflow_id`, `event`, `repository_next_id`),
ADD KEY `by_executing_actor_next_id_state_queued_at` (`executing_actor_next_id`, `state`, `queued_at`);