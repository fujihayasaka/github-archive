ALTER TABLE `workflow_build_executions`
ADD KEY `by_state_completed_at_created_at` (`state`,`completed_at`,`created_at`);