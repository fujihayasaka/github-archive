CREATE TABLE `ts_code_flows_documents` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
-- contains an array of indexed codeflows, threadflows and locations:
-- [CodeFlowIndex, FilePath, Message, Region.EndColumn, Region.EndLine, Region.StartColumn, Region.StartLine, StepIndex, ThreadFlowIndex]
  `document` json NOT NULL,
  `document_hash` binary(32) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_code_flows_documents_repository_id_document_hash` (`repository_id`,`document_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
