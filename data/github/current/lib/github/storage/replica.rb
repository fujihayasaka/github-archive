# typed: true
# frozen_string_literal: true

module GitHub::Storage::Replica
  def self.get_bad_replica_counts(
    offset,
    next_offset,
    copies,
    fileserver_hosts,
    limit)
    return [] if fileserver_hosts.empty?

    offset_where_clause = offset && next_offset ? "WHERE sb.id BETWEEN :offset AND :next_offset" : ""
    offset_sql = offset ? Arel.sql(offset.to_s) : ""
    next_offset_sql = next_offset ? Arel.sql(next_offset.to_s) : ""

    query = <<-SQL
      SELECT sb.id, sb.oid, COUNT(sr.host) AS copies
      FROM storage_blobs sb
      LEFT JOIN storage_replicas sr
      ON (
        sb.id = sr.storage_blob_id
        AND sr.host IN (:fileserver_hosts)
      )
      #{offset_where_clause}
      GROUP BY sb.id
      HAVING copies != :copies
      ORDER BY sb.id
      LIMIT :limit
    SQL

    ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(query, offset: offset_sql, next_offset: next_offset_sql,
      copies: copies, limit: Arel.sql(limit.to_s), fileserver_hosts: fileserver_hosts))
  end

  def self.get_orphaned_oids
    query = <<-SQL
      SELECT sb.id, sb.oid
      FROM storage_blobs sb
      LEFT JOIN storage_replicas sr
      ON (
        sb.id = sr.storage_blob_id
      )
      GROUP BY sb.id
      HAVING COUNT(sr.host) = 0
      ORDER BY sb.id
    SQL

    ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(query))
  end

  def self.get_online_objects(
    offset,
    next_offset,
    fileserver_hosts,
    limit)
    return [] if fileserver_hosts.empty?

    offset_where_clause = if offset && next_offset
      "WHERE sb.id BETWEEN :offset AND :next_offset"
    else
      ""
    end
    offset_sql = offset ? Arel.sql(offset.to_s) : ""
    next_offset_sql = next_offset ? Arel.sql(next_offset.to_s) : ""

    query = <<-SQL
      SELECT sb.id, sb.oid, COUNT(sr.host) AS copies
      FROM storage_blobs sb
      LEFT JOIN storage_replicas sr
      ON (
        sb.id = sr.storage_blob_id
        AND sr.host IN (:fileserver_hosts)
      )
      #{offset_where_clause}
      GROUP BY sb.id
      ORDER BY sb.id
      LIMIT :limit
    SQL

    ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(query, offset: offset_sql, next_offset: next_offset_sql,
      limit: Arel.sql(limit.to_s), fileserver_hosts: fileserver_hosts))
  end

  def self.get_replicas_for_oid(oid, fileserver_hosts)
    return [] if fileserver_hosts.empty?

    query = <<-SQL
      SELECT sr.host
      FROM storage_blobs sb
      LEFT JOIN storage_replicas sr
      ON (
        sb.id = sr.storage_blob_id
        AND sr.host IN (:fileserver_hosts)
      )
      WHERE sb.oid = :oid
    SQL

    ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(query, oid: oid, fileserver_hosts: fileserver_hosts))
  end

  def self.get_replica_count_for_oid(oid, fileserver_hosts)
    return [] if fileserver_hosts.empty?

    query = <<-SQL
      SELECT COUNT(sr.host)
        FROM storage_blobs sb
        LEFT JOIN storage_replicas sr
          ON (
                   sb.id = sr.storage_blob_id
               AND sr.host IN (:fileserver_hosts)
             )
       WHERE sb.oid = :oid
    SQL

    ApplicationRecord::Domain::Storage.connection.select_value(Arel.sql(query, oid: oid, fileserver_hosts: fileserver_hosts)).to_i
  end
end
