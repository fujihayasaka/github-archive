ALTER TABLE workflow_builds
ADD KEY `by_completed_at_queued_at` (`completed_at`, `queued_at`);