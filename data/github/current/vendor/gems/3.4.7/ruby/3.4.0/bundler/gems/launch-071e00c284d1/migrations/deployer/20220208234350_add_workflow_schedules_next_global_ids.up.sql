ALTER TABLE `workflow_schedules`
ADD COLUMN `schedule_next_hash` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL AFTER `schedule_hash`,
ADD COLUMN `repository_next_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL AFTER `repository_node_id`,
ADD COLUMN `actor_next_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL AFTER `actor_node_id`,
ADD UNIQUE KEY `by_schedule_next_hash` (`schedule_next_hash`),
ADD KEY `by_repository_next_id` (`repository_next_id`);