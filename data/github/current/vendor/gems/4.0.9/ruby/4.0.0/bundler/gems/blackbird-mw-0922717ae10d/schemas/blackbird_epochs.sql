CREATE TABLE `blackbird_epochs` (
  id                          int(11) unsigned NOT NULL AUTO_INCREMENT,
  corpus_id                   int(11) NOT NULL,
  `description`               varchar(100) NOT NULL,
  updated_at                  datetime NOT NULL,
  created_at                  datetime NOT NULL,
  PRIMARY KEY(`id`),
  INDEX `idx_corpus_id` (`corpus_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
