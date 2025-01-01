ALTER TABLE `workflow_build_executions`
    ADD COLUMN `triggering_actor_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL AFTER `actor_id`,
    ADD KEY `by_triggering_actor_id_state_queued_at` (`triggering_actor_id`, `state`, `queued_at`);