CREATE TABLE `blackbird_external_filesets` (
  repository_id     bigint unsigned NOT NULL,                  -- Assigned external (non-GitHub) repository id
  owner_id          bigint unsigned NOT NULL,                  -- GitHub user id
  fileset           varchar(512) NOT NULL,                     -- "<repo_url>-<ref>"
  `checkpoint`      binary(128) NOT NULL,                      -- Client assigned checkpoint/version (e.g. commit sha)
  seq_no            bigint unsigned NOT NULL,                  -- Monotonically increasing per-repository sequence number
  last_requested_at datetime NOT NULL DEFAULT (UTC_TIMESTAMP), -- The last time the repo was requested for indexing or search
  deleted_at        datetime NULL,
  PRIMARY KEY (`repository_id`),
  UNIQUE KEY `blackbird_external_filesets_owner_fileset` (`owner_id`, `fileset`),
  KEY `blackbird_external_filesets_deleted_at_last_requested_at` (`deleted_at`, `last_requested_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
