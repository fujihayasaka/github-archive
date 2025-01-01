# typed: true
# frozen_string_literal: true

require "application_record/domain/storage"

module GitHub::Storage::PartitionStats
  def self.partition_stats
    ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(<<-SQL))
      SELECT storage_file_servers.host, storage_partitions.partition, storage_partitions.disk_used, storage_partitions.disk_free FROM storage_file_servers
      LEFT JOIN storage_partitions
         ON storage_file_servers.id = storage_partitions.storage_file_server_id
      WHERE storage_file_servers.online = 1
        AND storage_file_servers.embargoed = 0
        AND (
          storage_partitions.`partition` = '0' OR
          storage_partitions.`partition` IS NULL
        )
      ORDER BY IFNULL(storage_partitions.disk_free, 0) DESC
    SQL
  end
end
