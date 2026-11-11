# typed: true
# frozen_string_literal: true

require "github/throttler"
require "set"

module GitHub::Storage::Destroyer
  # Evaluate a `Storage::Purge` and either cause the removal of the objects
  # and references if the refcount is still zero, or remove the purge leaving
  # everything intact if refcount rose.
  #
  # purge - An Enumerable of Storage::Purge instances
  #
  # Returns a list of Integer Storage::Blob ids for which the purge was performed,
  #         which should no longer exist in the DB.
  def self.perform_purge(purges)
    return if purges.empty?

    ApplicationRecord::Domain::Storage.transaction do
      storage_blob_ids = purges.map { |p| p.storage_blob_id }
      refcounts = count_references(storage_blob_ids)

      dead_blob_ids, live_blob_ids = storage_blob_ids.partition { |id| refcounts[id] == 0 }

      # Abort the purges for any objects that still have references
      abort_purges_for(live_blob_ids)

      # Fetch the dead set's oids
      dead_blob_oids = oids_for_blobs(dead_blob_ids)

      # Map the blob ownerships to the replica hosts
      host_blobs = {}
      storage_hosts_for(dead_blob_ids).each do |host_blob|
        host, blob_id = host_blob
        (host_blobs[host] ||= []) << blob_id
      end

      # Perform the purge on a per-host level and delete any
      # Storage::Blob, Storge::Reference and Storage::Replica
      # for any blobs that do not fail to be removed.
      #
      # Failed blobs' Storage::Purge records will be retained
      # and re-attempted on the next purging pass.
      #
      # Any blobs that can't be mapped to a replica host will be
      # uncondintonally finalized.
      finalize_for = Set.new(dead_blob_ids - host_blobs.values.flatten)
      host_blobs.each do |host, ids|
        oids = ids.map { |i| dead_blob_oids[i] }.compact
        ok, info = GitHub::Storage::Client.delete(host, oids)
        raise RuntimeError, "Failed to delete from #{host}: #{info.inspect}" unless ok

        # If the reply is malformed, let the nil deref bubble up and fail this txn
        succeeded = info["succeeded"].map { |oid| dead_blob_oids.key(oid) }
        failed = info["failed"].map { |oid| dead_blob_oids.key(oid) }

        GitHub::Storage::Creator.delete_replicas(host, succeeded)
        finalize_for.merge(succeeded)
      end

      finalize_purge_for(finalize_for)
    end
  end

  # Removes all of the the Storage::Blob, Storage::Replica and Storage::Reference
  # rows for all of the Storage::Blob instances or ids passed.
  def self.finalize_purge_for(blobs)
    return if blobs.empty?
    blob_ids = to_ids(blobs)
    ApplicationRecord::Domain::Storage.connection.delete(Arel.sql("DELETE FROM storage_blobs WHERE id IN (:blobs)", blobs: blob_ids))
    ApplicationRecord::Domain::Storage.connection.delete(Arel.sql("DELETE FROM storage_references WHERE storage_blob_id IN (:blobs)", blobs: blob_ids))
    ApplicationRecord::Domain::Storage.connection.delete(Arel.sql("DELETE FROM storage_purges WHERE storage_blob_id IN (:blobs)", blobs: blob_ids))
    blob_ids
  end

  # Return an Array of [host, storage_blob_id] tuples
  # for the given blob ids from the Storage::Replica table
  def self.storage_hosts_for(blobs)
    return [] if blobs.empty?
    blob_ids = to_ids(blobs)
    ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(<<-SQL, blobs: blob_ids))
      SELECT host, storage_blob_id FROM storage_replicas
      WHERE storage_blob_id IN (:blobs)
    SQL
  end

  # Returns a Hash mapping blob id to oid
  def self.oids_for_blobs(blobs)
    return {} if blobs.empty?
    blob_ids = to_ids(blobs)
    results = ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(<<-SQL, blobs: blob_ids))
      SELECT id, oid FROM storage_blobs
      WHERE id IN (:blobs)
    SQL
    Hash[results]
  end

  # Delete Storage::Purge records for Storage::Blobs without
  # performing a purge
  def self.abort_purges_for(blob_ids)
    blob_ids = blob_ids.map { |b| to_id(b) }
    return if blob_ids.empty?
    ApplicationRecord::Domain::Storage.connection.delete(Arel.sql(<<-SQL, blob_ids: blob_ids))
      DELETE from storage_purges WHERE
        storage_blob_id IN (:blob_ids)
    SQL
  end

  # Wrapper around `dereference_raw` that can take an ActiveRecord model
  # See `dereference_raw` for more info.
  #
  # The time the purge is scheduled for is set by `purge_at:` if provided,
  # then from `.purge_at` class method if not nil, and finally defaulting to
  # SQL::NOW if no source is available.
  def self.dereference(uploadable, purge_at: nil)
    deadline = purge_at&.floor || uploadable.class.purge_at&.floor || GitHub::SQL::NOW
    dereference_raw(uploadable.class, uploadable.id, purge_at: deadline || purge_at)
  end

  # Find the reference for the uploadable, and mark it as `:deleted`.
  # If there are no other non-deleted references to the underlying blob
  # it is scheduled for deletion with a `Storage::Purge`
  #
  # If no referece is found, a zero-reference check will still be performed.
  def self.dereference_raw(uploadable_class, uploadable_id, purge_at: GitHub::SQL::NOW)
    uploadable_class = uploadable_class.base_class.name if uploadable_class.try(:descends_from_active_record?)
    storage_blob_id = storage_blob_id_for(uploadable_class, uploadable_id)

    ApplicationRecord::Domain::Storage.transaction do
      # Dereference the current uploadable's Storage::Reference by marking it deleted
      params = { new_state: deleted_value, uploadable_id: uploadable_id, uploadable_type: uploadable_class }
      ApplicationRecord::Domain::Storage.connection.update(Arel.sql(<<-SQL, **params))
        UPDATE storage_references SET
          state = :new_state
        WHERE
          uploadable_id = :uploadable_id AND
          uploadable_type = :uploadable_type
      SQL

      # If we don't have a storage blob, we can't preform a 0-ref check
      if !storage_blob_id.nil?

        # If the refcount reached zero, schedule a purge
        refcount = count_references([storage_blob_id])[storage_blob_id]
        create_purge(storage_blob_id, at: purge_at) if refcount.zero?
      end
    end
  end

  # Create a new `Storage::Purge` record for the blob given
  # either as a Storage::Blob instance or id scheduled to be finally
  # removed at the date specified as `at:` which defaults to right now.
  #
  # If a Purge has already been scheduled for the given blob, the purge_at
  # time is updated to the supplied time.
  def self.create_purge(blob_or_id, at: GitHub::SQL::ArelLiterals::NOW)
    blob_id = to_id(blob_or_id)

    ApplicationRecord::Domain::Storage.connection.insert(Arel.sql(<<-SQL, when: at, blob_id: blob_id))
      INSERT INTO storage_purges
        (storage_blob_id, purge_at, created_at, updated_at)
      VALUES
        (:blob_id, :when, NOW(), NOW())
      ON DUPLICATE KEY UPDATE purge_at = :when
    SQL
  end

  # Return the number of non-deleted references that exist for the given
  # Storage::Blob's, which can be specified as a model instnace or
  # numeric IDs.
  #
  # blob_ids - List of integer Storage::Blob ids or instances
  #
  # Returns a Hash mapping {blob_id => references count, ...} with a default value of 0
  def self.count_references(blob_ids)
    blob_ids = blob_ids.map { |b| to_id(b) }
    results = ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(<<-SQL, blob_ids: blob_ids, state: deleted_value))
      SELECT storage_blob_id, count(id) FROM storage_references
      WHERE
        storage_blob_id in (:blob_ids) AND state != :state
      GROUP BY storage_blob_id
    SQL

    # Return a mapping with a default value of 0 to avoid
    # consumer nil-checks
    Hash[results].tap { |h| h.default = 0 }
  end

  # Destroys all storage replicas and removes the given host from the
  # storage_file_servers table.
  #
  # force - A boolean determining whether or not to destroy hosts that have a
  #         non-zero amount of objects allocated to them. Defaults: false.
  #
  # Raises a RuntimeError if objects were found and force was given as false.
  #
  # Returns nothing.
  def self.destroy_host(host, force: false)
    if !force && ::GitHub::Storage::Allocator.oids_on_host(host).any?
      raise RuntimeError, "Failed to destroy host #{host} without force, some objects remain"
    end

    replicas_iterator = GitHub::QueryBatching::IteratorBuilder.new(start: 0, batch_size: 20) do |iteration|
      bindings = iteration.cursor.arel_bindings.merge(host: host)
      results = ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(<<-SQL, **bindings))
        SELECT
          storage_replicas.id
        FROM storage_replicas
        WHERE storage_replicas.id >= :lower_id
          AND storage_replicas.host = :host
        ORDER BY storage_replicas.id ASC
        LIMIT :limit
      SQL

      iteration << results
    end

    replicas_iterator.batches.each do |replicas|
      ApplicationRecord::Domain::Storage.throttle do
        ApplicationRecord::Domain::Storage.connection.delete(Arel.sql(<<-SQL, replicas: replicas.flatten))
          DELETE FROM storage_replicas
          WHERE
              storage_replicas.id IN (:replicas)
        SQL
      end
    end

    ApplicationRecord::Domain::Storage.connection.delete(Arel.sql("DELETE FROM storage_file_servers WHERE host = :host", host: host))
  end

  # 2 is the numeric value of the `:deleted` as defined
  # by the Storage::Reference model.
  # > Storage::Reference.states[:deleted]
  # => 2
  #
  # Returns 2
  private_class_method def self.deleted_value
    2
  end

  # Ensure that the given parameter is a Numeric
  # id, not a model instnace.
  private_class_method def self.to_id(model_or_id)
    if !model_or_id.is_a?(Integer)
      model_or_id.id
    else
      model_or_id
    end
  end

  # Helper Enumerable map for `to_id`
  private_class_method def self.to_ids(models_or_ids)
    models_or_ids.map { |i| to_id(i) }
  end

  # Find a Storage::Blob id for a given Storage::Uploadable class and id
  private_class_method def self.storage_blob_id_for(class_name, uploadable_id)
    params = { uploadable_class: class_name, uploadable_id: uploadable_id }
    values = ApplicationRecord::Domain::Storage.connection.select_values(Arel.sql(<<-SQL, **params))
      SELECT
        storage_blob_id FROM storage_references
      WHERE
        uploadable_type = :uploadable_class AND
        uploadable_id = :uploadable_id
    SQL
    values.first
  end
end
