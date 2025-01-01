ALTER TABLE workflow_builds
DROP KEY `by_queued_at`,
DROP KEY `by_completed_at_created_at`;