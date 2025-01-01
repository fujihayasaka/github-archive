ALTER TABLE `workflow_jobs`
ADD COLUMN `check_run_next_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL AFTER `check_run_id`,
ADD KEY `by_check_run_next_id` (`check_run_next_id`);