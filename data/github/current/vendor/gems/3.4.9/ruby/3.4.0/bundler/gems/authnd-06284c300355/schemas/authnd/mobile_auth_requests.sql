CREATE TABLE `mobile_auth_requests` (
    `id`                bigint unsigned NOT NULL AUTO_INCREMENT,
    `user_id`           int(11)         NOT NULL,
    `payload`           blob            NOT NULL,
    `challenge_number`  int(11)         NULL,
    `created_at_utc`    datetime        NOT NULL,
    `expires_at_utc`    datetime        NOT NULL,
    `approved_at_utc`   datetime        NULL,
    `rejected_at_utc`   datetime        NULL,
    `type`              tinyint(4)      NOT NULL DEFAULT '0',
    `from_ip_address`   varchar(40)     NULL,
    `from_display_name` varbinary(1024) NULL,
    PRIMARY KEY (`id`),
    KEY `index_mobile_auth_requests_on_user_id` (`user_id`),
    KEY `index_mobile_auth_requests_on_expires_at_utc` (`expires_at_utc`),
    KEY `index_mobile_auth_requests_on_approved_at_utc` (`approved_at_utc`),
    KEY `index_mobile_auth_requests_on_rejected_at_utc` (`rejected_at_utc`)
)
