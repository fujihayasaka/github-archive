ALTER TABLE `workflow_builds`
ADD COLUMN `installation_id` bigint NOT NULL DEFAULT '0' COMMENT 'Id of the GitHub Actions app installation in the repository';