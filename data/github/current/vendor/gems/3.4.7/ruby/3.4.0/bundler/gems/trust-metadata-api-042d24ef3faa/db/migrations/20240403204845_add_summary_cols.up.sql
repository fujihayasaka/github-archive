ALTER TABLE attestations
ADD COLUMN `subject_name` varchar(255) COLLATE utf8mb4_unicode_ci,
ADD COLUMN `statement_preview` varchar(1024) COLLATE utf8mb4_unicode_ci;
