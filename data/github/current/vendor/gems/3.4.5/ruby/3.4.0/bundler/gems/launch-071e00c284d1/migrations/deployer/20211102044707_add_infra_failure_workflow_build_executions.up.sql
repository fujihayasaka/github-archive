ALTER TABLE workflow_build_executions
ADD COLUMN infrastructure_failed tinyint(1) DEFAULT '0',
ADD COLUMN azp_completed_at datetime(6) DEFAULT NULL;