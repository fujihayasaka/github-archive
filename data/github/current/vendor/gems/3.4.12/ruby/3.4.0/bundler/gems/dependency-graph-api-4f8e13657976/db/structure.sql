DROP TABLE IF EXISTS `dg_abstract_package_dependencies`;
CREATE TABLE `dg_abstract_package_dependencies` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `dependent_id` bigint unsigned DEFAULT NULL,
  `package_manager` int DEFAULT NULL,
  `package_name` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_abstract_package_dep_uniq_package` (`package_name`,`dependent_id`,`package_manager`),
  KEY `index_abstract_package_dependencies_on_dependent_id` (`dependent_id`),
  KEY `abstract_package_dep_lookups` (`package_name`,`package_manager`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_abstract_package_dependency_counts`;
CREATE TABLE `dg_abstract_package_dependency_counts` (
  `id` int NOT NULL AUTO_INCREMENT,
  `package_name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `package_manager` int NOT NULL,
  `dependent_count` int DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_abstract_package_dep_count_uniq` (`package_name`,`package_manager`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_abstract_repository_dependencies`;
CREATE TABLE `dg_abstract_repository_dependencies` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `repository_id` int NOT NULL,
  `package_manager` int NOT NULL,
  `package_name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_abstract_repo_dep_uniq_package` (`package_name`,`repository_id`,`package_manager`),
  KEY `index_dg_abstract_repository_dependencies_on_repository_id` (`repository_id`),
  KEY `index_abstract_repo_dep_lookups` (`package_name`,`package_manager`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_abstract_repository_dependency_counts`;
CREATE TABLE `dg_abstract_repository_dependency_counts` (
  `id` int NOT NULL AUTO_INCREMENT,
  `package_name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `package_manager` int NOT NULL,
  `dependent_count` int DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_abstract_repo_dep_count_uniq` (`package_name`,`package_manager`),
  KEY `index_dg_abstract_repository_dependency_counts_on_package_name` (`package_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_ar_internal_metadata`;
CREATE TABLE `dg_ar_internal_metadata` (
  `key` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `value` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_attributions`;
CREATE TABLE `dg_attributions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `attribution` varchar(16000) COLLATE utf8mb4_0900_as_cs NOT NULL,
  `dg_package_versions_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_on_dg_package_versions_id_attribution_a87a5bbd38` (`dg_package_versions_id`,`attribution`(766))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=COMPRESSED;
DROP TABLE IF EXISTS `dg_build_types`;
CREATE TABLE `dg_build_types` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` int NOT NULL,
  `external_type_id` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `external_type_id_display` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dg_build_types_on_repo_id_and_external_type_id` (`repository_id`,`external_type_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_builds`;
CREATE TABLE `dg_builds` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `external_build_id` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `build_type_id` int NOT NULL,
  `scanned_at` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dg_builds_on_build_type_id_and_build_id` (`build_type_id`,`external_build_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_checkpoints`;
CREATE TABLE `dg_checkpoints` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `last_checkpointed_id` bigint DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_checkpoints_on_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_dep_insights_backfills`;
CREATE TABLE `dg_dep_insights_backfills` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `github_owner_id` bigint DEFAULT NULL,
  `last_backfilled_at` datetime DEFAULT NULL,
  `source` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dg_dep_insights_backfills_on_github_owner_id` (`github_owner_id`),
  KEY `index_dg_dep_insights_backfills_on_last_backfilled_at` (`last_backfilled_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_dependency_specifications`;
CREATE TABLE `dg_dependency_specifications` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `requirements` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `dependent_id` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `scope` int DEFAULT '1',
  `encoded_lower_bound` bigint DEFAULT NULL,
  `encoded_upper_bound` bigint DEFAULT NULL,
  `package_manager` int DEFAULT NULL,
  `package_name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `dependent_type_id` int DEFAULT NULL,
  `package_label` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dep_spec_on_dependent_id_and_type_and_package_name` (`dependent_id`,`package_name`),
  KEY `index_dependency_specifications_on_dependent_id` (`dependent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_etl_imports`;
CREATE TABLE `dg_etl_imports` (
  `id` int NOT NULL AUTO_INCREMENT,
  `package_manager` int DEFAULT NULL,
  `metadata` text COLLATE utf8mb4_general_ci,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `stage` int DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_failed_manifest_messages`;
CREATE TABLE `dg_failed_manifest_messages` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `source` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `github_repository_id` int DEFAULT NULL,
  `message` text COLLATE utf8mb4_general_ci,
  `created_at` datetime(6) DEFAULT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dg_failed_manifest_messages_on_github_repository_id` (`github_repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_key_values`;
CREATE TABLE `dg_key_values` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `key` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `value` blob NOT NULL,
  `expires_at` datetime DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dg_key_values_on_key` (`key`),
  KEY `index_dg_key_values_on_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_locks`;
CREATE TABLE `dg_locks` (
  `lockname` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `holder` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `expires` datetime NOT NULL,
  PRIMARY KEY (`lockname`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_manifest_dependencies`;
CREATE TABLE `dg_manifest_dependencies` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `manifest_id` int NOT NULL,
  `requirements` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `package_name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `scope` int DEFAULT '1',
  `encoded_lower_bound` bigint DEFAULT NULL,
  `encoded_upper_bound` bigint DEFAULT NULL,
  `last_seen_at_revision` int NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `package_label` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `package_manager` int DEFAULT NULL,
  `exact_version` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `raw_requirements` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `manifest_dep_spec_package_name_reqs` (`manifest_id`,`package_name`,`requirements`),
  KEY `index_dg_manifest_dependencies_on_package_name_and_id` (`package_name`),
  KEY `index_dg_manifest_dependencies_on_manifest_pkg_mgr_name_version` (`manifest_id`,`package_manager`,`package_name`,`exact_version`),
  KEY `index_dg_manifest_dependencies_on_pkg_name_pkg_mgr_reqs` (`package_name`,`package_manager`,`requirements`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_manifest_entries`;
CREATE TABLE `dg_manifest_entries` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `manifest_id` bigint NOT NULL,
  `manifest_package_version_id` bigint NOT NULL,
  `scope` int NOT NULL DEFAULT '1',
  `last_seen_at_revision` int NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dg_manifest_entries_on_manifest_and_version` (`manifest_id`,`manifest_package_version_id`),
  KEY `index_dg_manifest_entries_on_manifest_package_version_id` (`manifest_package_version_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_manifest_package_versions`;
CREATE TABLE `dg_manifest_package_versions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `manifest_package_id` bigint NOT NULL,
  `requirements` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `encoded_lower_bound` bigint DEFAULT NULL,
  `encoded_upper_bound` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dg_manifest_package_versions_on_package_id_and_reqs` (`manifest_package_id`,`requirements`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_manifest_packages`;
CREATE TABLE `dg_manifest_packages` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `package_name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `package_manager` int NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dg_manifest_packages_on_package_manager_and_package_name` (`package_manager`,`package_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_manifests`;
CREATE TABLE `dg_manifests` (
  `id` int NOT NULL AUTO_INCREMENT,
  `repository_id` int DEFAULT NULL,
  `manifest_type` int NOT NULL,
  `package_manager` int NOT NULL,
  `revision` int NOT NULL DEFAULT '0',
  `latest_git_ref` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `last_pushed_at` datetime NOT NULL,
  `filename` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `path` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `name` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_unique_manifests` (`repository_id`,`manifest_type`,`path`,`filename`),
  KEY `index_manifests_on_name` (`name`),
  KEY `index_dg_manifests_on_package_manager_and_name` (`package_manager`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_package_release_dependent_counts`;
CREATE TABLE `dg_package_release_dependent_counts` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `github_owner_id` int NOT NULL,
  `package_release_id` bigint NOT NULL,
  `count` int NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dg_package_counts` (`github_owner_id`,`package_release_id`),
  KEY `index_dg_package_release_dependent_counts_on_package_release_id` (`package_release_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_package_release_vuln_counts`;
CREATE TABLE `dg_package_release_vuln_counts` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `package_release_id` bigint NOT NULL,
  `total_count` int NOT NULL DEFAULT '0',
  `critical_count` int NOT NULL DEFAULT '0',
  `high_count` int NOT NULL DEFAULT '0',
  `moderate_count` int NOT NULL DEFAULT '0',
  `low_count` int NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dg_package_release_vuln_counts_on_package_release_id` (`package_release_id`),
  KEY `index_dg_package_release_vuln_counts` (`package_release_id`,`total_count`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_package_versions`;
CREATE TABLE `dg_package_versions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `package_id` bigint unsigned NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `external_id` int DEFAULT NULL,
  `repository_id` int DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `encoded` bigint DEFAULT NULL,
  `published_at` datetime DEFAULT NULL,
  `pushed_at` datetime DEFAULT NULL,
  `unpublished_at` datetime DEFAULT NULL,
  `repository_id_certainty` int NOT NULL DEFAULT '0',
  `license` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `clearly_defined_score` int DEFAULT NULL,
  `package_manager` int DEFAULT NULL,
  `package_name` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `source_url` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_package_versions_on_package_id_and_name` (`package_id`,`name`),
  KEY `index_package_versions_on_package_id` (`package_id`),
  KEY `index_package_versions_on_name` (`name`),
  KEY `index_package_versions_on_package_id_and_encoded` (`package_id`,`encoded`),
  KEY `index_dg_package_versions_on_license` (`license`),
  KEY `index_dg_package_versions_on_package_name_package_manager_name` (`package_name`,`package_manager`,`name`),
  KEY `index_dg_package_versions_on_package_id_and_repo_id` (`package_id`,`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_packages`;
CREATE TABLE `dg_packages` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `package_manager` int DEFAULT NULL,
  `repository_id` int DEFAULT NULL,
  `repository_id_certainty` int NOT NULL DEFAULT '0',
  `last_published_at` datetime DEFAULT NULL,
  `label` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_packages_on_name_and_package_manager` (`name`,`package_manager`),
  KEY `index_packages_on_repository_id` (`repository_id`),
  KEY `index_dg_packages_on_package_manager_and_repository_id` (`package_manager`,`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_repositories`;
CREATE TABLE `dg_repositories` (
  `id` int NOT NULL AUTO_INCREMENT,
  `github_repository_id` int NOT NULL,
  `public` tinyint(1) DEFAULT '1',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `nwo` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `github_owner_id` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_repositories_on_github_repository_id` (`github_repository_id`),
  KEY `index_dg_repositories_on_nwo_and_public` (`nwo`,`public`),
  KEY `index_dg_repositories_on_github_repository_id_and_public` (`github_repository_id`,`public`),
  KEY `index_dg_repositories_on_github_owner_id_and_public` (`github_owner_id`,`public`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_schema_migrations`;
CREATE TABLE `dg_schema_migrations` (
  `version` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_snapshot_blobs`;
CREATE TABLE `dg_snapshot_blobs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `blob` json NOT NULL,
  `blob_size_bytes` int NOT NULL,
  `created_at` datetime NOT NULL,
  `blob_hash` varchar(128) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dg_snapshot_blobs_on_hash` (`blob_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_snapshots`;
CREATE TABLE `dg_snapshots` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` int NOT NULL,
  `snapshot_blob_id` bigint unsigned NOT NULL,
  `source` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `sha` varchar(64) COLLATE utf8mb4_general_ci NOT NULL,
  `metadata` json DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `build_id` bigint DEFAULT NULL,
  `branch_ref` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dg_snapshots_on_repository_id_and_sha` (`repository_id`,`sha`),
  KEY `index_dg_snapshots_on_repository_id_source_and_sha` (`repository_id`,`source`,`sha`),
  KEY `index_dg_snapshots_on_repo_build_id_and_branch_ref` (`repository_id`,`build_id`,`branch_ref`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_star_counts`;
CREATE TABLE `dg_star_counts` (
  `id` int NOT NULL AUTO_INCREMENT,
  `github_repository_id` int NOT NULL,
  `star_count` int DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_dg_star_counts_on_github_repository_id` (`github_repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
DROP TABLE IF EXISTS `dg_vulnerable_version_ranges`;
CREATE TABLE `dg_vulnerable_version_ranges` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `github_id` int NOT NULL,
  `package_name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `package_manager` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `version_range` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `encoded_lower_bound` bigint NOT NULL,
  `encoded_upper_bound` bigint NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `severity` varchar(12) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_vulnerable_version_ranges_on_github_id` (`github_id`),
  KEY `index_dg_vuln_version_ranges_on_package_name_and_encoded_bounds` (`package_name`,`encoded_lower_bound`,`encoded_upper_bound`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
INSERT INTO `dg_schema_migrations` (version) VALUES
('20240610160509'),
('20240531092955'),
('20240221170510'),
('20231106165108'),
('20231020160129'),
('20231011184025'),
('20230928174326'),
('20230811181746'),
('20230606173617'),
('20230418175715'),
('20230217193114'),
('20230106155856'),
('20221010190510'),
('20220927161811'),
('20220926103110'),
('20220901155540'),
('20220824165438'),
('20211129230519'),
('20211112182353'),
('20211110164321'),
('20211026211239'),
('20211021225023'),
('20211005221851'),
('20210805150018'),
('20210604150000'),
('20210602181000'),
('20210427194252'),
('20210309174937'),
('20210309174913'),
('20210309174900'),
('20210120175002'),
('20201119194648'),
('20201026112010'),
('20201023083442'),
('20200106211434'),
('20190729230621'),
('20190529210616'),
('20190513171324'),
('20190508182813'),
('20190508175310'),
('20190430142903'),
('20190426235759'),
('20190426210849'),
('20190416175625'),
('20190415214707'),
('20190412172909'),
('20190411163627'),
('20190411163510'),
('20190410202853'),
('20190409183210'),
('20190326000425'),
('20190321184534'),
('20190320162415'),
('20190319212944'),
('20190222230541'),
('20181201050624'),
('20181121232050'),
('20181030035221'),
('20181023194931'),
('20180924185150'),
('20180905203908'),
('20180806211929'),
('20180803200921'),
('20180720221059'),
('20180720212203'),
('20180719163855'),
('20180706070201'),
('20180626140825'),
('20180615173754'),
('20180613163528'),
('20180408164108'),
('20180123001849'),
('20171121004231'),
('20171121002929'),
('20171027073041'),
('20171027071038'),
('20171027070657'),
('20171027070357'),
('20171027065938'),
('20171025162010'),
('20171024213011'),
('20171023172119'),
('20171020171846'),
('20171020013129'),
('20171016164606'),
('20171010225651'),
('20170925231004'),
('20170914015823'),
('20170914000426'),
('20170913181817'),
('20170912212445'),
('20170911185117'),
('20170823174520'),
('20170823174504'),
('20170215030759'),
('20170131223425'),
('20170126213335'),
('20170126012658'),
('20170124051142'),
('20170120004447'),
('20170120003128'),
('20161209220017'),
('20161201221854'),
('20161128222850'),
('20161119013410'),
('20161119001746'),
('20161118174509'),
('20161115020108'),
('20161108023924'),
('20161107225451'),
('20161107204051'),
('20161105073648'),
('20161104234056'),
('20161102205428'),
('20161028222745'),
('20161028210233'),
('20161028182715'),
('20161028022454'),
('20161023231206'),
('20161019222647'),
('20161019010842'),
('20161018225854'),
('20161018220659'),
('20161018204558'),
('20161018194447'),
('20161018192252'),
('20161018183333'),
('20161014214431'),
('20161014204415'),
('20161012232222'),
('20161012005326'),
('20161007191754'),
('20161004233010'),
('20160930205307'),
('20160930204908'),
('20160930203351'),
('20160929064044'),
('20160929001409'),
('20160927230301'),
('20160927021646');
