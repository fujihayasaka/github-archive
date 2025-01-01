
CREATE TABLE vouchers (
  id                BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  artifact          LONGBLOB      NOT NULL,
  artifact_type     VARCHAR(4096) NOT NULL,
  certificate       VARCHAR(4096) NOT NULL,
  included_at       DATETIME      NOT NULL,
  media_type        VARCHAR(4096) NOT NULL,
  organization_name VARCHAR(255)  NOT NULL,
  predicate_type    VARCHAR(255)  NOT NULL,
  repository_name   VARCHAR(255)  NOT NULL,
  subject_digest    VARCHAR(255)  NOT NULL
);
