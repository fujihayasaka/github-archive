ALTER TABLE workflow_builds
ADD COLUMN `gcp_project_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT 'GCP project ID - not used in AZP';