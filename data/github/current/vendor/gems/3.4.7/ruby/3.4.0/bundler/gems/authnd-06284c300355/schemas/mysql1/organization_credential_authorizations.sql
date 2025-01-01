DROP TABLE IF EXISTS `organization_credential_authorizations`;
CREATE TABLE `organization_credential_authorizations` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `organization_id` int(11) NOT NULL,
  `credential_id` int(11) NOT NULL,
  `credential_type` varchar(30) NOT NULL,
  `actor_id` int(11) NOT NULL,
  `actor_type` varchar(30) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `revoked_at` datetime DEFAULT NULL,
  `revoked_by_id` int(11) DEFAULT NULL,
  `fingerprint` char(48) DEFAULT NULL,
  `fingerprint_sha256` varbinary(64) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_org_credential_authorizations_on_org_id_and_fingerprint` (`organization_id`,`fingerprint`),
  UNIQUE KEY `index_org_cred_auth_on_org_id_and_fingerprint_sha256` (`organization_id`,`fingerprint_sha256`),
  KEY `index_org_credential_authorizations_on_fingerprint_and_cred_type` (`fingerprint`,`credential_type`),
  KEY `index_org_cred_authorizations_on_org_and_cred_and_revoked_by` (`organization_id`,`credential_id`,`credential_type`,`revoked_by_id`),
  KEY `index_org_credential_authorizations_on_org_id_and_actor_id` (`organization_id`,`actor_id`),
  KEY `index_on_credential_id_and_credential_type_and_revoked_by_id` (`credential_id`,`credential_type`,`revoked_by_id`),
  KEY `index_org_cred_auth_on_fingerprint_sha_256_and_cred_type` (`fingerprint_sha256`,`credential_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
