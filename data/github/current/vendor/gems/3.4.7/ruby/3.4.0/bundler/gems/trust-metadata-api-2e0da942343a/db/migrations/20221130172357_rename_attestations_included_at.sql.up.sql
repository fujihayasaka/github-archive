ALTER TABLE attestations CHANGE COLUMN included_at created_at datetime NOT NULL AFTER statement;
