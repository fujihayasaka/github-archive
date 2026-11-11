CREATE TABLE `blackbird_repositories` (
  id                int(11) NOT NULL,
  owner_id          int(11) NOT NULL,
  owner_login       varchar(40) NOT NULL,
  `name`            varchar(100) NOT NULL,
  `is_public`       tinyint(1) DEFAULT 0 NOT NULL,
  repo_score        int(11) NULL,
  source_topic      varchar(100) NULL DEFAULT NULL,
  deleted_at        datetime NULL,
  is_archived       tinyint(1) DEFAULT 0 NOT NULL,
  pushed_at         datetime NULL,
  created_at        datetime NULL,
  has_license       tinyint(1) NULL,
  num_watchers      int(11) NULL,
  num_stars         int(11) NULL,
  has_readme        tinyint(1) NULL,
  public_fork_count int(11) NULL,
  seq_no            bigint(20) unsigned NULL, -- Monotonically increasing per-repository sequence number
  commit_oid        binary(20) NULL,          -- Commit OID of most recent attempted ingest
  network_id        int(11) NULL,             -- ID of the repository's fork network
  license_name      varchar(100) NULL,        -- SPDX licence identifier per https://spdx.org/licenses/. NULL if there is no license.
  is_fork           tinyint(1) NULL,          -- Whether or not this repository is a fork
  experiments       varchar(512) NULL,        -- Experiments set on this repo. Comma separated in the form of key=value.
  repo_seq_no       bigint(20) NULL,          -- Tracks the repository sequence number for changes to the GitHub repositories table associated with an ingest operation (and has no relation to the `seq_no` column).
  PRIMARY KEY (`id`),
  INDEX `idx_owner_id` (`owner_id`),
  INDEX `idx_owner_login` (`owner_login`),
  INDEX `idx_owner_login_id` (`owner_login`, `owner_id`),
  INDEX `idx_name` (`name`),
  INDEX `idx_is_public` (`is_public`),
  INDEX `idx_source_topic` (`source_topic`),
  INDEX `idx_deleted_at` (`deleted_at`),
  INDEX `idx_repo_score` (`repo_score`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
