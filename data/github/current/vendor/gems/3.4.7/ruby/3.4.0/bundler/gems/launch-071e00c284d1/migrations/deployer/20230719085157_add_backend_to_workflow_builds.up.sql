ALTER TABLE `workflow_builds`
ADD COLUMN `backend` tinyint NOT NULL DEFAULT '0' COMMENT 'The backend service that is orchestrating this workflow';
