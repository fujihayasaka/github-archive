DROP INDEX by_backend_state_completed_at_created_at
ON `workflow_build_executions`;

ALTER TABLE `workflow_build_executions`
DROP COLUMN `backend`;