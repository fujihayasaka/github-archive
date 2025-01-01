ALTER TABLE workflow_builds
  ADD COLUMN `webhook_delivery_id` VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  ADD UNIQUE KEY `by_delivery_id_workflow_file_path_event` (`webhook_delivery_id`,`workflow_file_path`,`event`);