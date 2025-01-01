ALTER TABLE `workflow_schedules`
MODIFY `schedule_next_hash` varchar(255) COLLATE utf8mb4_bin DEFAULT NULL,
MODIFY `repository_next_id` varchar(255) COLLATE utf8mb4_bin DEFAULT NULL,
MODIFY `actor_next_id` varchar(255) COLLATE utf8mb4_bin DEFAULT NULL;