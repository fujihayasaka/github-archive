# typed: true
# frozen_string_literal: true

require "application_record/domain/storage"

module GitHub::Storage::Creator
  PARTITIONS = %w[0 1 2 3 4 5 6 7 8 9 a b c d e f].freeze

  class Result
    attr_accessor :replicated, :uploadable

    def initialize(replicated = nil, uploadable = nil)
      @replicated = replicated
      @uploadable = uploadable
    end
  end

  def self.perform(oid:, size:, host_urls:)
    consensus = GitHub::Storage::ClusterConsensus.new(host_urls)
    return nil unless consensus.reached?

    Storage::Blob.transaction do
      blob = Storage::Blob.create_for_uploadable(oid: oid, size: size)
      uploadable = yield(blob)
      track_uploadable_storage(uploadable, hosts: consensus.replicated_hosts)
      uploadable
    end
  end

  def self.create_blob(meta)
    fields = {
      oid: meta[:oid],
      size: meta[:size].to_i,
    }

    ActiveRecord::Base.connected_to(role: :writing) do
      ApplicationRecord::Domain::Storage.connection.insert(Arel.sql(<<-SQL, **fields))
        INSERT INTO storage_blobs (oid, size, created_at)
        VALUES (:oid, :size, NOW())
        ON DUPLICATE KEY UPDATE oid = oid
      SQL
    end
  end

  def self.track_uploadable_storage(uploadable, hosts:)
    hosts = Array(hosts)

    create_uploadable_references([uploadable])
    return if hosts.empty?
    create_replicas(uploadable.storage_blob.id, hosts)
  end

  def self.create_replicas_for_oid(oid, hosts, remove_existing: false)
    sql = Arel.sql <<-SQL, oid: oid
      SELECT id FROM storage_blobs WHERE oid = :oid
    SQL
    storage_blob_id = ApplicationRecord::Domain::Storage.connection.select_value(sql)

    if storage_blob_id
      if remove_existing
        # Delete any existing paths since they are likely broken (import
        # from single VM's with localhost routes or restores into clusters
        # with a different topology).
        ApplicationRecord::Domain::Storage.connection.delete(Arel.sql(<<-SQL, storage_blob_id: storage_blob_id))
          DELETE FROM storage_replicas WHERE storage_blob_id = :storage_blob_id
        SQL
      end

      create_replicas(storage_blob_id, hosts)
    end
  end

  def self.delete_replica_from_host(fileserver, oid)
    sql = Arel.sql(<<-SQL, host: fileserver, oid: oid)
      SELECT storage_replicas.id FROM storage_replicas, storage_blobs
      WHERE storage_replicas.host = :host AND
        storage_blobs.oid = :oid AND
        storage_replicas.storage_blob_id = storage_blobs.id
    SQL
    storage_replica_id = ApplicationRecord::Domain::Storage.connection.select_value(sql)

    return if storage_replica_id.blank?

    ApplicationRecord::Domain::Storage.connection.delete(Arel.sql(<<-SQL, id: storage_replica_id))
      DELETE FROM storage_replicas WHERE id = :id
    SQL
  end

  def self.create_uploadable_references(uploadables)
    rows = uploadables.map do |u|
      [u.id, u.class.base_class.name, u.storage_blob_id, 1, GitHub::SQL::ArelLiterals::NOW]
    end

    ApplicationRecord::Domain::Storage.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows), state: 1))
      INSERT INTO storage_references
        (uploadable_id, uploadable_type, storage_blob_id, state, created_at)
      :rows
      ON DUPLICATE KEY UPDATE state = :state
    SQL
  end

  def self.create_fileservers(hosts)
    rows = hosts.map do |h|
      [h, true, false, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW]
    end

    last_insert_id = ApplicationRecord::Domain::Storage.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows)))
      INSERT INTO storage_file_servers
        (host, online, embargoed, created_at, updated_at)
      :rows
      ON DUPLICATE KEY UPDATE host=host
    SQL

    return if last_insert_id < 1
    insert_partitions_for(hosts)
  end

  def self.insert_partitions_for(hosts)
    sql = Arel.sql(<<-SQL, hosts: hosts)
      SELECT id FROM storage_file_servers
      WHERE host IN (:hosts)
    SQL

    rows = []
    ApplicationRecord::Domain::Storage.connection.select_values(sql).each do |id|
      PARTITIONS.each do |p|
        rows << [id, p, 0, 0, GitHub::SQL::ArelLiterals::NOW, GitHub::SQL::ArelLiterals::NOW]
      end
    end

    ApplicationRecord::Domain::Storage.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows)))
      INSERT INTO `storage_partitions`
        (`storage_file_server_id`, `partition`, `disk_free`, `disk_used`, `created_at`, `updated_at`)
      :rows
      ON DUPLICATE KEY UPDATE `partition`=`partition`
    SQL
  end

  def self.create_replicas(blob_id, hosts)
    rows = hosts.map do |h|
      [h, blob_id, GitHub::SQL::ArelLiterals::NOW]
    end

    ApplicationRecord::Domain::Storage.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows)))
      INSERT INTO storage_replicas (host, storage_blob_id, created_at)
      :rows
      ON DUPLICATE KEY UPDATE host=host
    SQL
  end
  private_class_method :create_replicas

  def self.create_replicas_from_repair(fileserver, blob_ids)
    rows = blob_ids.map do |b|
      [fileserver, b, GitHub::SQL::ArelLiterals::NOW]
    end

    ApplicationRecord::Domain::Storage.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows)))
      INSERT INTO storage_replicas (host, storage_blob_id, created_at)
      :rows
      ON DUPLICATE KEY UPDATE host=host
    SQL
  end

  def self.delete_replicas(fileserver, blob_ids)
    if blob_ids.any?
      ApplicationRecord::Domain::Storage.connection.delete(Arel.sql(<<-SQL, ids: blob_ids, host: fileserver))
        DELETE FROM storage_replicas WHERE storage_blob_id IN (:ids) AND host = :host
      SQL
    end
  end
end
