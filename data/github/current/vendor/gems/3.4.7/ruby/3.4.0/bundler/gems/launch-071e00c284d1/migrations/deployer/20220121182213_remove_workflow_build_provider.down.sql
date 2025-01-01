ALTER TABLE workflow_builds
  ADD COLUMN `provider` varchar(255) NOT NULL DEFAULT '' COMMENT 'The build provider',
  ADD KEY `by_provider_queued_at` (`provider`,`queued_at`);