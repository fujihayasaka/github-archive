CREATE TABLE releases (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  attestation_id    BIGINT UNSIGNED NOT NULL,
  tenant_id         BIGINT UNSIGNED NOT NULL,
  repository_id     BIGINT UNSIGNED NOT NULL,
  tag               VARCHAR(256) NOT NULL,
  UNIQUE KEY        `index_on_tenant_id_repository_id_tag` (`tenant_id`, `repository_id`, `tag`)
);
