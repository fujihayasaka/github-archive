/* No need to directly edit the schemas/authnd/enterprise version of this file, only the /schemas/authnd version. Git hooks will handle syncing any changes to enterprise directory */

CREATE TABLE `programmatic_access_tokens` (
    `id`                bigint unsigned     NOT NULL AUTO_INCREMENT,
    `hashed_token`      varbinary(64)       NOT NULL,
    `token_suffix`      varbinary(8)        NOT NULL,
    `actor_id`          bigint unsigned     NOT NULL,
    `actor_type`        nvarchar(40)        NOT NULL,
    `access_id`         bigint unsigned     NOT NULL,
    `issued_at_utc`     datetime            NOT NULL,
    `expires_at_utc`    datetime            NULL,
    `revoked_at_utc`    datetime            NULL,
    `attributes`        blob                NOT NULL,
    `last_event_at_utc` datetime            NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `index_programmatic_access_tokens_on_hashed_token` (`hashed_token`),
    KEY `index_programmatic_access_tokens_on_actor_type_and_id` (`actor_type`, `actor_id`),
    KEY `index_programmatic_access_tokens_on_actor_type_id_and_access_id` (`actor_type`, `actor_id`, `access_id`),
    KEY `index_programmatic_access_tokens_on_expires_at_utc` (`expires_at_utc`),
    KEY `index_programmatic_access_tokens_on_last_event_at_utc` (`last_event_at_utc`)
)
