CREATE TABLE IF NOT EXISTS `mint_v0_tokens` (
    `id` bigint unsigned NOT NULL AUTO_INCREMENT,
    `hashed_identifier` varbinary(64) NOT NULL,
    `last_eight` varbinary(8) NOT NULL,
    `actor_id` bigint unsigned NOT NULL,
    `actor_type` nvarchar(40) NOT NULL,
    `issued_at_utc` datetime NOT NULL,
    `expires_at_utc` datetime NULL,
    `revoked_at_utc` datetime NULL,
    `attributes` blob NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `index_mint_v0_tokens_on_hashed_identifier` (`hashed_identifier`),
    KEY `index_mint_v0_tokens_on_actor_type_and_id` (`actor_type`, `actor_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
