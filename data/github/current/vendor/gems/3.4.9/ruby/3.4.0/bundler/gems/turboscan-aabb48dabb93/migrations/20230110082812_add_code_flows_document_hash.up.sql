ALTER TABLE `ts_code_flows_documents` ADD COLUMN `document_hash` binary(32) DEFAULT NULL, ADD UNIQUE KEY `index_code_flows_documents_repository_id_document_hash` (`repository_id`,`document_hash`);
