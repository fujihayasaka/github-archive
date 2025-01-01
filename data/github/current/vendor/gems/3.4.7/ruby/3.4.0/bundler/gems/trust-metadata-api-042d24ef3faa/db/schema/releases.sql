CREATE TABLE `releases` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `attestation_id` bigint unsigned NOT NULL,
  `tenant_id` bigint unsigned NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `tag` varchar(256) COLLATE utf8mb4_unicode_ci NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_on_tenant_id_repository_id_tag` (`tenant_id`,`repository_id`,`tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
