ALTER TABLE workflow_builds
ADD COLUMN `payload_id` bigint(20) unsigned DEFAULT NULL COMMENT 'ID of actions_workflow_payloads.payloads row';
