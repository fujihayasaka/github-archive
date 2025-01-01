ALTER TABLE `ts_code_flows_documents` DROP COLUMN `hash`, MODIFY COLUMN `document_hash` binary(32) NOT NULL, DROP KEY `index_repository_id_hash`;
