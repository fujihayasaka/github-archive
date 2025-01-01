ALTER TABLE workflow_builds
  DROP KEY `by_cloud_build_id`,
  DROP COLUMN `cloud_build_id`;