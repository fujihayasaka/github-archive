CREATE TABLE IF NOT EXISTS `notifyd_schema_migrations` (
  `version` varchar(255) NOT NULL,
  UNIQUE KEY `notifyd_schema_migrations` (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
