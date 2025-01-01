ALTER TABLE workflow_builds
  ADD COLUMN `cloud_build_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT 'The ID from the build backend for this build',
  ADD KEY `by_cloud_build_id` (`cloud_build_id`);