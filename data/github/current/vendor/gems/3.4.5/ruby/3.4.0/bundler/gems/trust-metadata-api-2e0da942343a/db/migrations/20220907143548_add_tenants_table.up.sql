CREATE TABLE tenants (
  id                INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name              VARCHAR(255) COLLATE utf8mb4_unicode_ci NOT NULL
);

INSERT INTO tenants(name) VALUES ("npm"), ("github");
