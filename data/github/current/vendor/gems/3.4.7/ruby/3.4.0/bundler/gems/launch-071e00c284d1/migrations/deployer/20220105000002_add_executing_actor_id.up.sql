ALTER TABLE `workflow_builds`
    ADD COLUMN `executing_actor_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL AFTER `actor_id`,
    ADD KEY `by_executing_actor_id_state_queued_at` (`executing_actor_id`, `state`, `queued_at`);