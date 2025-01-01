# typed: false
# frozen_string_literal: true

require "application_record/domain/storage"

module GitHub::Storage::Allocator
  def self.least_loaded_fileservers
    least_loaded_hosts.map { |h| GitHub.storage_replicate_fmt % h }
  end

  def self.least_loaded_hosts
    replicas = least_loaded_replicas
    hosts = replicas[:hosts]
    non_voting = replicas[:non_voting]
    return hosts if non_voting.blank?
    hosts + non_voting
  end

  # Gets the least loaded hosts for the replication of a new object. Since
  # Enterprise only has a single partition, we can't (quickly) get disk stats
  # for each OID partition without scanning every file on disk. So, only
  # partition "0" is checked for now since all the values are the same.
  # Hosts in cache locations will never be returned.
  #
  # Also, the final OID of the new object is not known when this method is
  # called anyway.
  def self.least_loaded_replicas
    {
      hosts: least_loaded_voting_hosts,
      non_voting: least_loaded_non_voting_hosts,
    }
  end

  def self.least_loaded_voting_hosts
    replicas = GitHub.storage_replica_count
    hosts = query_least_loaded_voting_hosts
    if hosts.length != replicas
      if GitHub.storage_auto_localhost_replica? && replicas == 1
        hosts = %w(localhost)
      else
        raise ::Storage::ReplicationError.new(replicas)
      end
    end
    hosts
  end

  def self.least_loaded_non_voting_hosts(datacenter = nil)
    datacenters = datacenter.nil? ? get_non_voting_datacenters : [datacenter]
    non_voting_hosts = []
    datacenters.each do |dc|
      non_voting_hosts += query_least_loaded_non_voting_hosts(dc)
    end
    non_voting_hosts
  end

  def self.least_loaded_non_voting_cache_hosts(datacenter, cache_location, limit)
    query_least_loaded_non_voting_cache_hosts(datacenter, cache_location, limit)
  end

  # Get the least loaded voting hosts for the replication of a new object based
  # on free disk space. Returns a number of hosts up to
  # `GitHub.storage_replica_count`
  # Note that there should never be voting hosts in cache locations.
  def self.query_least_loaded_voting_hosts
    return [] if GitHub.storage_replica_count.zero?

    ApplicationRecord::Domain::Storage.connection.select_values(Arel.sql(<<-SQL, limit: Arel.sql(GitHub.storage_replica_count.to_s)))
      SELECT storage_file_servers.host FROM storage_file_servers
      LEFT JOIN storage_partitions
         ON storage_file_servers.id = storage_partitions.storage_file_server_id
      WHERE storage_file_servers.online = 1
        AND storage_file_servers.embargoed = 0
        AND storage_file_servers.non_voting = 0
        AND storage_file_servers.cache_location IS NULL
        AND (
          storage_partitions.`partition` = '0' OR
          storage_partitions.`partition` IS NULL
        )
      ORDER BY IFNULL(storage_partitions.disk_free, 0) DESC
      LIMIT :limit
    SQL
  end

  # Get the least loaded non-voting hosts for the replication of a new object
  # based on free disk space. Returns a number of hosts up to
  # `GitHub.storage_non_voting_replica_count`
  # Hosts in cache locations will never be returned.
  def self.query_least_loaded_non_voting_hosts(datacenter)
    return [] if GitHub.storage_non_voting_replica_count.zero?

    ApplicationRecord::Domain::Storage.connection.select_values(Arel.sql(<<-SQL, limit: Arel.sql(GitHub.storage_non_voting_replica_count.to_s), dc: datacenter))
      SELECT storage_file_servers.host FROM storage_file_servers
      LEFT JOIN storage_partitions
         ON storage_file_servers.id = storage_partitions.storage_file_server_id
      WHERE storage_file_servers.online = 1
        AND storage_file_servers.embargoed = 0
        AND storage_file_servers.non_voting = 1
        AND storage_file_servers.datacenter = :dc
        AND storage_file_servers.cache_location IS NULL
        AND (
          storage_partitions.`partition` = '0' OR
          storage_partitions.`partition` IS NULL
        )
      ORDER BY IFNULL(storage_partitions.disk_free, 0) DESC
      LIMIT :limit
    SQL
  end

  # Get the least loaded non-voting hosts in a given cache location for the
  # replication of a new object based on free disk space. Returns a number
  # of hosts up to `limit`.
  # Only hosts in the cache location will be returned.
  def self.query_least_loaded_non_voting_cache_hosts(datacenter, cache_location, limit)
    return [] if limit.zero?

    sql = Arel.sql(<<-SQL, cache_location: cache_location)
      SELECT storage_file_servers.host FROM storage_file_servers
        LEFT JOIN storage_partitions
          ON storage_file_servers.id = storage_partitions.storage_file_server_id
       WHERE storage_file_servers.online = 1
         AND storage_file_servers.embargoed = 0
         AND storage_file_servers.non_voting = 1
         AND (
           storage_partitions.`partition` = '0' OR
           storage_partitions.`partition` IS NULL
         )
         AND storage_file_servers.cache_location = :cache_location
    SQL

    if datacenter.nil?
      sql += Arel.sql "AND storage_file_servers.datacenter IS NULL"
    else
      sql += Arel.sql "AND storage_file_servers.datacenter = :datacenter", datacenter: datacenter
    end

    sql += Arel.sql(<<-SQL, limit: Arel.sql(limit.to_s))
      ORDER BY IFNULL(storage_partitions.disk_free, 0) DESC
      LIMIT :limit
    SQL

    ApplicationRecord::Domain::Storage.connection.select_values(sql)
  end

  def self.host_info(host)
    ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(<<-SQL, host: host))[0]
      SELECT host, online, cache_location FROM storage_file_servers
       WHERE host = :host
    SQL
  end

  # Gets all online voting hosts in the storage cluster. Embargoed
  # hosts will be excluded from the list if `exclude_embargoed` is true
  # Note that there should never be voting hosts in cache locations.
  def self.get_hosts(exclude_embargoed: false)
    sql = Arel.sql <<-SQL
      SELECT host FROM storage_file_servers
      WHERE online = 1
        AND non_voting = 0
    SQL
    sql += Arel.sql "AND cache_location IS NULL" if have_cache_location_column?
    sql += Arel.sql "AND embargoed = 0" if exclude_embargoed
    sql += Arel.sql "LIMIT 100"

    ApplicationRecord::Domain::Storage.connection.select_values(sql)
  end

  # Gets all online non-voting hosts in the specified datacenter. Embargoed
  # hosts will be excluded from the list if `exclude_embargoed` is true
  # Hosts in cache locations will never be returned.
  def self.get_non_voting_hosts(datacenter, exclude_embargoed: false)
    sql = Arel.sql(<<-SQL, datacenter: datacenter)
      SELECT host FROM storage_file_servers
      WHERE online = 1
        AND non_voting = 1
        AND datacenter = :datacenter
        AND cache_location IS NULL
    SQL

    sql += Arel.sql "AND embargoed = 0" if exclude_embargoed
    sql += Arel.sql "LIMIT 100"

    ApplicationRecord::Domain::Storage.connection.select_values(sql)
  end

  # Gets all online non-voting hosts in the specified datacenter and cache
  # location. Embargoed hosts will be excluded from the list if
  # `exclude_embargoed` is true.
  # Only hosts in the cache location will be returned.
  def self.get_non_voting_cache_hosts(datacenter, cache_location, exclude_embargoed: false)
    sql = Arel.sql(<<-SQL, cache_location: cache_location)
      SELECT host FROM storage_file_servers
       WHERE online = 1
         AND non_voting = 1
         AND cache_location = :cache_location
    SQL

    if datacenter.nil?
      sql += Arel.sql "AND storage_file_servers.datacenter IS NULL"
    else
      sql += Arel.sql "AND storage_file_servers.datacenter = :datacenter", datacenter: datacenter
    end

    sql += Arel.sql "AND embargoed = 0" if exclude_embargoed
    sql += Arel.sql "LIMIT 100"

    ApplicationRecord::Domain::Storage.connection.select_values(sql)
  end

  # Gets all hosts in the storage cluster
  # Hosts in cache locations will be returned.
  def self.get_all_hosts
    sql = Arel.sql <<-SQL
      SELECT host FROM storage_file_servers
      LIMIT 100
    SQL

    ApplicationRecord::Domain::Storage.connection.select_values(sql)
  end

  # Hosts in cache locations will never be returned.
  def self.hosts_for_blob(blob_id, host:, datacenter:)
    sql = Arel.sql(<<-SQL, blob_id: blob_id)
      SELECT storage_replicas.host FROM storage_replicas
      INNER JOIN storage_file_servers
         ON storage_file_servers.host = storage_replicas.host
      WHERE storage_replicas.storage_blob_id = :blob_id
        AND storage_file_servers.online = 1
        AND storage_file_servers.cache_location IS NULL
      ORDER BY CASE
    SQL

    if host
      sql += Arel.sql "WHEN storage_file_servers.host = :host THEN 0", host: host
    end

    if datacenter
      sql += Arel.sql "WHEN storage_file_servers.datacenter = :datacenter THEN 1", datacenter: datacenter
    end

    sql += Arel.sql <<-SQL
       WHEN storage_file_servers.non_voting = 0 THEN 2
       ELSE 3
        END
    SQL

    ApplicationRecord::Domain::Storage.connection.select_values(sql)
  end

  # Hosts in cache locations will never be returned.
  def self.non_voting_hosts_for_oid(oid, datacenter)
    ApplicationRecord::Domain::Storage.connection.select_values(Arel.sql(<<-SQL, oid: oid, datacenter: datacenter))
      SELECT storage_replicas.host FROM storage_replicas
      INNER JOIN storage_blobs
         ON storage_replicas.storage_blob_id = storage_blobs.id
      INNER JOIN storage_file_servers
         ON storage_file_servers.host = storage_replicas.host
      WHERE storage_blobs.oid = :oid
        AND storage_file_servers.online = 1
        AND storage_file_servers.non_voting = 1
        AND storage_file_servers.datacenter = :datacenter
        AND storage_file_servers.cache_location IS NULL
    SQL
  end

  # Only hosts in the cache location will be returned.
  def self.non_voting_cache_hosts_for_oid(oid, datacenter, cache_location)
    sql = Arel.sql(<<-SQL, oid: oid, cache_location: cache_location)
      SELECT storage_replicas.host FROM storage_replicas
       INNER JOIN storage_blobs
          ON storage_replicas.storage_blob_id = storage_blobs.id
       INNER JOIN storage_file_servers
          ON storage_file_servers.host = storage_replicas.host
       WHERE storage_blobs.oid = :oid
         AND storage_file_servers.online = 1
         AND storage_file_servers.non_voting = 1
         AND storage_file_servers.cache_location = :cache_location
    SQL

    if datacenter.nil?
      sql += Arel.sql "AND storage_file_servers.datacenter IS NULL"
    else
      sql += Arel.sql "AND storage_file_servers.datacenter = :datacenter", datacenter: datacenter
    end

    ApplicationRecord::Domain::Storage.connection.select_values(sql)
  end

  # Note that there should never be voting hosts in cache locations.
  def self.cluster_hosts_for_oid(oid)
    ApplicationRecord::Domain::Storage.connection.select_values(Arel.sql(<<-SQL, oid: oid))
      SELECT storage_replicas.host FROM storage_replicas
      INNER JOIN storage_blobs
         ON storage_replicas.storage_blob_id = storage_blobs.id
      INNER JOIN storage_file_servers
         ON storage_file_servers.host = storage_replicas.host
      WHERE storage_blobs.oid = :oid
        AND storage_file_servers.online = 1
        AND storage_file_servers.non_voting = 0
        AND storage_file_servers.cache_location IS NULL
    SQL
  end

  # Hosts in cache locations will be returned.
  def self.hosts_for_oid(oid, exclude_offline: true)
    sql = Arel.sql(<<-SQL, oid: oid)
      SELECT storage_replicas.host FROM storage_replicas
      INNER JOIN storage_blobs
         ON storage_replicas.storage_blob_id = storage_blobs.id
      INNER JOIN storage_file_servers
         ON storage_file_servers.host = storage_replicas.host
      WHERE storage_blobs.oid = :oid
    SQL

    if exclude_offline
      sql += Arel.sql "AND storage_file_servers.online = 1"
    end

    ApplicationRecord::Domain::Storage.connection.select_values(sql)
  end

  def self.blob_id_for_oid(oid)
    ApplicationRecord::Domain::Storage.connection.select_values(Arel.sql(<<-SQL, oid: oid))
      SELECT storage_replicas.storage_blob_id FROM storage_replicas
      INNER JOIN storage_blobs
         ON storage_replicas.storage_blob_id = storage_blobs.id
      WHERE storage_blobs.oid = :oid
    SQL
  end

  def self.oids_on_host(host)
    ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(<<-SQL, host: host))
      SELECT storage_blobs.id, storage_blobs.oid FROM storage_blobs
      INNER JOIN storage_replicas
         ON storage_blobs.id = storage_replicas.storage_blob_id
      WHERE storage_replicas.host = :host
    SQL
  end

  # Hosts in cache locations will be returned.
  def self.all_hosts_with_partitions
    hosts = ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(<<-SQL))
      SELECT storage_file_servers.host, storage_partitions.`partition` FROM storage_file_servers
      INNER JOIN storage_partitions
         ON storage_file_servers.id = storage_partitions.storage_file_server_id
      WHERE storage_file_servers.online = 1
        AND storage_file_servers.embargoed = 0
    SQL

    results = {}
    hosts.each do |h|
      results[h[0]] ||= []
      results[h[0]] << h[1]
    end
    results
  end

  def self.update_partition_usage(host, partition, disk_free, disk_used)
    affected_rows = ApplicationRecord::Domain::Storage.connection.update(Arel.sql(<<-SQL, host: host, partition: partition, free: disk_free, used: disk_used))
      UPDATE storage_partitions p
      JOIN storage_file_servers f ON (p.storage_file_server_id = f.id)
      SET disk_free = :free, disk_used = :used
      WHERE p.partition = :partition AND f.host = :host
    SQL
    affected_rows == 1
  end

  # Gets the full list of datacenters that contain non-voting hosts
  # that are not in cache locations.
  def self.get_non_voting_datacenters
    sql = Arel.sql <<-SQL
      SELECT DISTINCT datacenter FROM storage_file_servers
      WHERE non_voting = 1
        AND datacenter IS NOT NULL
        AND cache_location IS NULL
    SQL

    ApplicationRecord::Domain::Storage.connection.select_values(sql)
  end

  # Gets the full list of datacenters that contain non-voting hosts
  # that are in cache locations.
  def self.get_non_voting_datacenter_cache_locations(online: false)
    sql = Arel.sql <<-SQL
      SELECT DISTINCT datacenter, cache_location FROM storage_file_servers
       WHERE non_voting = 1
         AND cache_location IS NOT NULL
    SQL

    sql += Arel.sql "AND online = 1" if online

    ApplicationRecord::Domain::Storage.connection.select_rows(sql)
  end

  # Gets the count of non-voting hosts that exist within the specified
  # datacenter
  # Hosts in cache locations will never be counted.
  def self.non_voting_host_count(datacenter)
    query = Arel.sql(<<-SQL, datacenter: datacenter)
      SELECT COUNT(*) FROM storage_file_servers
      WHERE non_voting = 1
        AND datacenter = :datacenter
        AND cache_location IS NULL
    SQL

    ApplicationRecord::Domain::Storage.connection.select_value(query)
  end

  # Gets the number of replicas required for sufficient non-voting replication
  # within the specified datacenter. Will return
  # `GitHub.storage_non_voting_replica_count` unless a datacenter doesn't have
  # enough non-voting hosts, in which case it will just use the non-voting host
  # count.
  def self.non_voting_replica_count(datacenter)
    [GitHub.storage_non_voting_replica_count.to_i, non_voting_host_count(datacenter)].min
  end

  # HACK:  When restoring/migrating a database from GHES <3.4, we may be
  # running this new code with an old database schema.
  # If removing this method, make sure to update storage-cluster-backup-routes.
  def self.have_cache_location_column?
    return @@have_cache_location_column if defined?(@@have_cache_location_column)

    sql = Arel.sql <<-SQL
      SELECT 1 FROM information_schema.COLUMNS
       WHERE table_schema=DATABASE()
         AND table_name='storage_file_servers'
         AND column_name='cache_location'
    SQL

    @@have_cache_location_column = ApplicationRecord::Domain::Storage.connection.select_rows(sql).size > 0
  end
end
