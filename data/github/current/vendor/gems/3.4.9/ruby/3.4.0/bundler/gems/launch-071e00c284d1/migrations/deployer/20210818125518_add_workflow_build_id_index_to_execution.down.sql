ALTER TABLE workflow_build_executions
DROP KEY `by_workflow_build_id_state`,
DROP KEY `by_workflow_build_id_completed_at_state`;
