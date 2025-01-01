ALTER TABLE workflow_schedules
ADD KEY `by_locked_environment_tier_next_run_at` (`locked_by`,`environment`,`tier`,`next_run_at`) COMMENT 'optimises finding rows with tiers to work on';