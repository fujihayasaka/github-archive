ALTER TABLE `workflow_build_executions`
ADD COLUMN `backend` tinyint NOT NULL DEFAULT '0';

ALTER TABLE `workflow_build_executions`
ADD INDEX `by_backend_state_completed_at_created_at` (`backend`,`state`,`completed_at`,`created_at`);
