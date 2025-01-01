ALTER TABLE workflow_builds
  DROP KEY `by_provider_queued_at`,
  DROP COLUMN `provider`;