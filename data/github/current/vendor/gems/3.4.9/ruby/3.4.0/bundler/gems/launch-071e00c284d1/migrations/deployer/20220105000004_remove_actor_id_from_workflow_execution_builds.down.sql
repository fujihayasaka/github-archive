ALTER TABLE `workflow_build_executions`
    ADD COLUMN `actor_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL AFTER `was_delayed`,
    ADD KEY `by_actor_id_state_queued_at` (`actor_id`, `state`, `queued_at`);