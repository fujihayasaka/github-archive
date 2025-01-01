# typed: false
# frozen_string_literal: true

#
# WaitForReplication encapsulates the algorithm for waiting until information
# written to the primary database has been replicated to all read replicas. This
# waits with sleeps based on the clock and knowledge of how our replication
# delay system works, and does *not* provide strict guarantees that data will be
# present on any given replica.
#
# There are several assumptions this makes:
#
# * The data has already been written to the primary. That is, this code is
#   being invoked after the data has been COMMITed to the database. Its initial
#   use is in a background job triggered by an after_commit hook.
# * You have the timestamp for when the data was written.
# * Replication delay as reported by freno is globally accurate, that is, any
#   specific replica code might be talking to with ActiveRecord::Base.connected_to(role: :reading) will
#   be delayed no further than reported by freno.
# * Clocks themselves are accurate. This is already an assumption built into the
#   replication delay system (it uses NOW() as reported by replica servers to
#   determine replication delay), and this library builds on top of that by
#   assuming application servers are also using accurate clocks.
#
# The replication delay system works by writing heartbeat timestamps every 100ms
# to the primary database, then using the current replicated value to determine
# if a replica is up to date. Freno uses this relicated heartbeat and `NOW()` to
# determine how far behind a replica is, but only with a maximum accuracy of
# 100ms.
#
# This library uses the replication delay values reported by Freno along with
# the time when write operation happened on the master. It asks Freno for the
# replication delay, and calculates if the time since the write operation
# occurred is higher than that replication delay. If that holds true, the data
# is assumed to be there. Otherwise it waits a reasonable amount of time (up to
# max_wait) and repeats the operation.
#
# Due to the way freno samples the replication delay metrics (each 100ms) the
# value reported by the server can be off by 100ms. As the replication delay
# doesn't grow faster then the clock, the value reported by the freno client
# adds a 100ms cushioning factor to ensure that the value we get can be safely
# compared to the time since the last write, and in turn, to determine that the
# data written is on the replicas. Importantly, this means the replication delay
# values reported by the Freno client will always be at least 100ms, and if this
# algorithm is triggered right after the write operation, it will wait at least
# that amount of time.
#
# Because this code introduces arbitrary sleep waits (up to a maximum value) it
# is not appropriate for scenarios where latency is constrained.
#
# Usage example:
#
# Multiple cluster w/ gtid
#
#   last_writes = { "mysql1" => { gtid: ..., time: ... } }
#   WaitForReplication.new(last_writes).wait!
#
#
class WaitForReplication
  attr_accessor :job_name

  class DataUnavailable < StandardError
    attr_reader :store_name
    def initialize(store_name:, wait_required:, max_wait:)
      @store_name = store_name
      super("Cannot wait #{wait_required} seconds for replication to catch up on #{store_name}. Maximum allowed is #{max_wait} seconds.")
    end
  end

  def self.new(timestamp_or_hash, **kwargs)
    if timestamp_or_hash.is_a?(Hash)
      super(timestamp_or_hash, **kwargs)
    else
      store_name = kwargs.delete(:store_name) { :mysql1 }
      hash = { store_name => { gtid: nil, time: timestamp_or_hash } }
      super(hash, **kwargs)
    end
  end

  # How long we've waited for replication delay.
  attr_reader :waited

  def initialize(last_writes, max_wait_seconds: 5, default_wait_time: 1, job_name: nil)
    @clusters = last_writes
    @waited = 0
    @max_wait_seconds = max_wait_seconds
    @default_wait_time = default_wait_time
    self.job_name = job_name
  end

  class Cluster
    attr_reader :name, :gtid, :last_written_at
    def initialize(name, gtid: nil, time:)
      @name = name
      @gtid = gtid
      @last_written_at = time
    end
  end

  # Public: wait for replication delay to catch up.
  #
  # Sleep until the currently measured replication delay is less than the time
  # since the last write, or raise if it's waited too long or if the expected
  # wait is too long to even bother trying.
  #
  # Assuming that replication delay will only recover as fast as the clock,
  # the loop will either sleep the remaining difference, or exit early if
  # the required sleep to catch up exceeds the max_wait value.
  #
  # This may result in unnecessary sleeps in situations where replication delay
  # recovers quickly, but will exit early if replication delay is high and may
  # not recover quickly.
  #
  # Returns the time waited.
  # Raises a DataUnavailable error if the data is or will not be available
  # within the allowed max_wait_time.
  #
  # In case we ask freno for the replication delay and it returns an error
  # we act as if it was a replication delay, sleeping default_wait_time seconds,
  # and we report the error to failbot instead of bubbling up the exception.
  #
  def wait!
    @waited = 0

    return @waited if @clusters.empty?

    waiting_clusters = @clusters.map { |name, values| Cluster.new(name, **values) }

    # Last cluster we waited on, for stats reporting
    waiting_cluster = nil

    now = Time.now

    loop do
      clusters_with_wait_time = waiting_clusters.index_with do |cluster|
        time_since_last_write = now - Timestamp.to_time(cluster.last_written_at)
        store_name = cluster.name

        begin
          replication_delay = replication_wait_for_cluster(store_name)
          # first, check to see if the data is there:
          if replication_delay <= time_since_last_write
            0
          else
            # replication hasn't caught up yet, so we need to wait.
            (replication_delay - time_since_last_write)
          end
        rescue Freno::Error => boom
          Failbot.report!(boom, app: "github-freno") if GitHub.environment.fetch("GH_FRENO_UNAVAILABLE", 0) == 0
          GitHub.dogstats.increment("wait_for_replication.freno_error", tags: dogstats_tags_for_store(store_name))

          @default_wait_time
        end
      end

      # Wait for the slowest cluster
      waiting_cluster, to_wait = clusters_with_wait_time.max_by { |_k, v| v }

      if to_wait <= 0
        break
      end

      # but don't bother waiting if delay is too far behind
      if @waited + to_wait > @max_wait_seconds
        store_name = waiting_cluster.name
        GitHub.dogstats.distribution("wait_for_replication.data_unavailable", @waited + to_wait, tags: dogstats_tags_for_store(store_name))
        raise DataUnavailable.new(store_name: store_name, wait_required: @waited + to_wait, max_wait: @max_wait_seconds)
      end

      sleep to_wait unless Rails.env.test?

      # The actual time elapsed is longer due to processing and the freno check
      # above, but slight pessimism here is fine:
      now += to_wait
      @waited += to_wait
    end

    GitHub.dogstats.distribution("wait_for_replication.waited", @waited, tags: dogstats_tags_for_store(waiting_cluster&.name))

    @waited
  rescue DataUnavailable => e
    # Record waits for optimistic algorithm even if the end result is an error
    if @waited > 0
      GitHub.dogstats.distribution("wait_for_replication.waited", @waited, tags: dogstats_tags_for_store(e.store_name))
    end
    raise
  end

  private

  def dogstats_tags_for_store(store_name)
    [
      "store_name:#{store_name}",
      "job_name:#{self.job_name}",
      ("worker_pool:#{worker_pool}" if worker_pool.present?),
    ].compact
  end

  def replication_wait_for_cluster(cluster_name)
    connection_class = ApplicationRecord.clusters.find { |c| c.cluster_name == cluster_name }
    connection_class&.default_replication_wait!&./(1000.0) || @default_wait_time
  end

  def worker_pool
    Aqueduct::Worker.config.worker_pool || ""
  end
end
