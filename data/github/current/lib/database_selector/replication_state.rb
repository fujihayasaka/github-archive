# typed: true
# frozen_string_literal: true

class DatabaseSelector
  class ReplicationState
    TEST_MODE_DEFAULT_GTID = ""

    class << self
      # In the test environment we wrap everything in a transaction, so
      # we never observe the gtid changing. Instead we can consider any query
      # which looks like a write (determined by regex) by setting:
      #   DatabaseSelector::ReplicationState.test_mode = true
      attr_accessor :test_mode
    end

    def initialize(last_writes = {}, static: false)
      # latest_writes represents the ongoing consistent state we are tracking
      # for this user: all writes made within their requests.
      @latest_writes = last_writes.deep_dup

      # Whether we want to track writes or keep the last_writes static
      @static = static

      # A set of non-GTID clusters which observed a new write
      @non_gtid_clusters_with_writes = Set.new

      # We want to record the current GTIDs for each cluster at the start of a
      # request (or other track_writes block)
      # This allows us to detect when the GTID changed on the connection
      @last_gtid = ApplicationRecord.clusters.map do |cluster|
        # Switch to writing connection in case initialized while in a reading role.
        current_gtid = cluster.connected_to(role: :writing) do
          cluster.connection.last_gtid
        end
        [cluster.cluster_name, current_gtid]
      end.to_h
    end

    # Public: Observe a query
    # This records the query's new GTID (if it's a GTID cluster) and timestamp
    # if a write has occurred.
    def observe_query!(cluster:, type:)
      return if static?

      # Only consider queries to the :writing role
      return if cluster.current_role != :writing


      record_write(cluster: cluster, type: type)
    end

    def to_hash
      latest_writes = @latest_writes.deep_dup

      now = current_timestamp_ms

      # Convert non-GTID writes to GTID-compatible entries
      non_gtid_clusters_with_writes.each do |cluster_name|
        latest_writes[cluster_name] = { gtid: nil, time: now }
      end

      # Delete all write information that is older than 30 seconds
      latest_writes.delete_if { |_cluster_name, write| now - write[:time] > 30_000 }

      latest_writes
    end

    def self.current
      Thread.current.thread_variable_get(:replication_state)
    end

    def self.current=(val)
      Thread.current.thread_variable_set(:replication_state, val)
    end

    private

    attr_reader :latest_writes, :non_gtid_clusters_with_writes, :static

    def static?
      !!static
    end

    def record_write(cluster:, type:)
      if cluster.gtid_tracking_enabled?
        # We only want the timestamp to be updated if the actual GTID of the connection changed.
        # If the GTID did not change, the query of this event was either a read-only query
        # or was wrapped in a transaction block, where the GTID will only be updated
        # once the transaction was committed.
        # observe_gtid returns the gtid if it was significant
        if current_gtid = observe_gtid(cluster: cluster, type: type)
          data = {
            gtid: current_gtid,
            time: current_timestamp_ms
          }

          cluster.cluster_names.each do |cluster_name|
            @latest_writes[cluster_name] = data
          end
        end
      else
        # For clusters where tracking GTIDs does not make sense (e.g. if we run behind Vitess),
        # we track the fact that at least one write query was executed against this cluster. At the end
        # of the observation period, we use the current time as a timestamp. This should be good enough.
        if type == :write
          non_gtid_clusters_with_writes.merge(cluster.cluster_names)
        end
      end
    end

    # Private: Observe and record the GTID on a cluster
    #
    # Returns the GTID if it indicates that a write has been performed
    def observe_gtid(cluster:, type:)
      if self.class.test_mode
        # In tests we likely never see a GTID update due to a wrapping
        # transaction, so record on anything that looks like a write.
        # This isn't meant to be accurate emulation, just enough to bump the
        # timestamp. (see comment above)
        if type == :write
          # fallback to ensure that we always return something truthy
          return cluster.connection.last_gtid || TEST_MODE_DEFAULT_GTID
        else
          return nil
        end
      end

      cluster_name = cluster.cluster_name
      current_gtid = cluster.connection.last_gtid

      # Check that the GTID has changed since the last one we've seen
      # We want to check that it has changed since the start of the request
      # (via last_gtid), and only record it in latest_writes when that has
      # changed.
      if @last_gtid[cluster_name] == current_gtid
        return nil
      end

      # Record the GTID, so that we don't re-observe it later
      @last_gtid[cluster_name] = current_gtid

      # If the GTID is nil, we can safely ignore it.
      #
      # It can be nil here because our connection hasn't yet seen a GTID (the
      # server is freshly booted and hasn't yet talked to the cluster) or it
      # may mean that we had a reconnect (though currently trilogy-adapter
      # caches the returned GTID value, which should hide this, but the
      # implementation may change).
      #
      # Both of these cases indicate that a write hasn't just occurred on the
      # connection, so we can safely return nil here

      # Return either the newly observed gtid, or nil
      current_gtid
    end

    def current_timestamp_ms
      # FIXME: timecop doesn't understand clock_gettime :(
      # Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
      Timestamp.from_time(Time.now)
    end
  end
end
