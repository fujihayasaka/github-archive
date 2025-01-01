ALTER TABLE workflow_builds
  DROP KEY `by_delivery_id_workflow_file_path_event`,
  DROP COLUMN `webhook_delivery_id`;