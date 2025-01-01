ALTER TABLE workflow_build_executions
ADD KEY `by_workflow_build_id_state` (`workflow_build_id`,`state`),
ADD KEY `by_workflow_build_id_completed_at_state` (`workflow_build_id`, `completed_at`, `state`);
