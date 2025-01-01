# typed: true
# frozen_string_literal: true

require "database_selector/replication_state"
require "database_selector/last_operations"

class DatabaseSelector
  # If the last write was more than FORCE_REPLICA_READ_TIMEOUT seconds ago
  # we don't do any calculation and assume we can read from the replica.
  FORCE_REPLICA_READ_TIMEOUT = 5.seconds

  attr_reader :force_replica_read_timeout

  def self.instance
    @database_selector ||= new
  end

  def initialize(force_replica_read_timeout: FORCE_REPLICA_READ_TIMEOUT)
    @force_replica_read_timeout = force_replica_read_timeout
  end

  def track_writes(last_operations, &block)
    last_operations.track_writes(&block)
  end

  # Chooses the database to read from based on the return value of read_from_replicas?
  # last_operations: reference to cache
  # called_from: symbol for call location
  # gtid_result_hash: hash to store gtid query results, can be used for stats outside
  # additional_tags: array of additional tags to include in stats
  def read_from_database(last_operations:, called_from:, gtid_result_hash: {}, additional_tags: [], &block)
    writes = last_operations.last_writes

    GitHub.dogstats.distribution("database_selector.last_operations.size", writes.size, tags: additional_tags + ["called:#{called_from}"])

    primary_clusters = GitHub.dogstats.distribution_time("database_selector.primary_selection.time") do
      ApplicationRecord.clusters.select do |cluster|
        # skip record if you don't have the key for
        next false unless writes.has_key?(cluster.cluster_name)

        replicas_ready, diff_lag = read_from_replicas?(
          cluster, writes[cluster.cluster_name], called_from,
          additional_tags: additional_tags,
          force_replica_read_timeout: force_replica_read_timeout
        )
        gtid_result_hash[cluster.cluster_name] = { gtid_lag: diff_lag, replicas_ready: replicas_ready }
        !replicas_ready
      end
    end

    all_replicas_ready = primary_clusters.empty?
    gtid_result_hash[:replicas_ready] = all_replicas_ready

    if all_replicas_ready
      read_from_replica(last_operations, called_from, additional_tags: additional_tags, &block)
    else
      read_from_selected_primaries(primary_clusters, called_from, additional_tags: additional_tags, &block)
    end
  end

  # Increments the dogstat for reading from the replica, updates
  # the last read timestamp and then reads from the replica.
  def read_from_replica(last_operations, called_from, additional_tags: [], &block)
    GitHub.dogstats.increment("database_selector.#{called_from}", tags: additional_tags + ["action:readonly"])

    ActiveRecord::Base.connected_to(role: :reading, &block)
  end

  # Read from replicas, except for the given clusters, where reads will be made from
  # the primaries.
  def read_from_selected_primaries(primary_clusters, called_from, additional_tags: [], &block)
    primary_clusters.each do |cluster|
      cluster_tag = GitHub::DatadogTagsCache::SQL_CLUSTER_NAMES[cluster.cluster_name] || "cluster:#{cluster.cluster_name}"
      GitHub.dogstats.increment("database_selector.#{called_from}.by_cluster", tags: additional_tags + ["action:readonly_primary", cluster_tag])
    end

    ActiveRecord::Base.connected_to(role: :reading) do
      ActiveRecord::Base.connected_to_many(primary_clusters, role: :writing, prevent_writes: true, &block)
    end
  end

  # Returns whether is OK to read from the replicas based on
  # * the last time we issued a write operation
  # * the replication delay that existed at the time this was invoked
  #
  # Returns true if the last write request was previous to `force_replica_read_timeout`
  # seconds ago.
  # Returns true if the last write request was not previous to `force_replica_read_timeout`
  # seconds ago but the GTID is seen on the replica connection.
  # Returns false otherwise
  #
  def read_from_replicas?(cluster, write, called_from, force_replica_read_timeout: self.force_replica_read_timeout, additional_tags: [])
    default_success_args = { cluster: cluster, called_from: called_from, success: true, additional_tags: additional_tags }

    if write.blank? || write[:time].blank?
      measure_called(**default_success_args, time_diff: force_replica_read_timeout, reason: :missing)
      return true, force_replica_read_timeout
    end

    time_diff = Time.now - Timestamp.to_time(write[:time])

    if time_diff >= force_replica_read_timeout
      measure_called(**default_success_args, time_diff: time_diff, reason: :write_expired)
      return true, time_diff
    end

    if write[:gtid].blank? || cluster.skip_gtid_check?
      if time_diff >= cluster.default_replication_wait / 1000.0
        measure_called(**default_success_args, time_diff: time_diff, reason: :replication_wait_success)
        return true, time_diff
      end
    else
      if replica_contains_gtid?(cluster, write[:gtid])
        measure_called(**default_success_args, time_diff: time_diff, reason: :gtid_success)
        return true, time_diff
      end
    end

    measure_called(
      cluster: cluster, called_from: called_from, time_diff: time_diff,
      reason: :master_read, success: false, additional_tags: additional_tags
    )
    [false, time_diff]
  end

  def replica_contains_gtid?(cluster, gtid)
    ActiveRecord::Base.connected_to(role: :reading) do
      cluster.connection.select_value(Arel.sql(<<-SQL, gtid: gtid)) == 1
        SELECT GTID_SUBSET(:gtid, @@GLOBAL.GTID_EXECUTED)
      SQL
    end
  end

  private

  def measure_called(time_diff:, called_from:, cluster:, reason:, success:, additional_tags: [])
    GitHub.dogstats.distribution("database_selector.called.dist", time_diff,
      tags: additional_tags + [
        "cluster:#{cluster.cluster_name}",
        "called:#{called_from}",
        "reason:#{reason}",
        "success:#{success}",
      ])
  end
end
