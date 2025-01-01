CREATE TABLE `blackbird_epoch_offsets` (
  epoch_id        int(11) NOT NULL,
  kafka_partition int(11) NOT NULL,
  kafka_offset    bigint(20) NOT NULL,
  PRIMARY KEY(`epoch_id`, `kafka_partition`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
