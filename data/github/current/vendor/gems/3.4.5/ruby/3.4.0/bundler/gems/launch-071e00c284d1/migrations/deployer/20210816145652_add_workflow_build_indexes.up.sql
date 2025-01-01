ALTER TABLE workflow_builds
ADD KEY `by_queued_at` (`queued_at`),
ADD KEY `by_completed_at_created_at` (`completed_at`, `created_at`);