ALTER TABLE `workflow_builds`
  ADD COLUMN `started_at` datetime(6) DEFAULT NULL,
  ADD COLUMN `external_build_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '' COMMENT 'The ID from the build backend for this build',
  ADD COLUMN `was_delayed` tinyint(1) DEFAULT '0';
