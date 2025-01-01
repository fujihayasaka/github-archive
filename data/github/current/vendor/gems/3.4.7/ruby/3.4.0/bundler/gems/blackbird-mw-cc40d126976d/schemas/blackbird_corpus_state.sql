CREATE TABLE `blackbird_corpus_state` (
  corpus_id                   int(11) NOT NULL,
  epoch_id                    int(11) NOT NULL, -- FK to blackbird_epochs
  ingest_mode                 int(11) DEFAULT 0 NOT NULL,
  PRIMARY KEY(`corpus_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
