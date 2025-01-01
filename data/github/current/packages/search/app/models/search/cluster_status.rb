# typed: true
# frozen_string_literal: true

module Search
  class ClusterStatus
    class ClusterHealthStatus < T::Enum
      enums do
        Green = new("green")
        Yellow = new("yellow")
        Red = new("red")
      end
    end

    # Note that this interface is consistent from Elasticsearch 5.x to 8.8 (and possibly beyond).
    class ClusterHealthResponse < T::Struct
      const :cluster_name, String
      const :status, ClusterHealthStatus
      const :timed_out, T::Boolean
      const :number_of_nodes, Integer
      const :number_of_data_nodes, Integer
      const :active_primary_shards, Integer
      const :active_shards, Integer
      const :relocating_shards, Integer
      const :initializing_shards, Integer
      const :unassigned_shards, Integer
      const :unassigned_primary_shards, T.nilable(Integer)
      const :delayed_unassigned_shards, Integer
      const :number_of_pending_tasks, Integer
      const :number_of_in_flight_fetch, Integer
      const :task_max_waiting_in_queue_millis, Integer
      const :active_shards_percent_as_number, Float

      def to_hash
        {
          cluster_name: cluster_name,
          status: status.serialize,
          timed_out: timed_out,
          number_of_nodes: number_of_nodes,
          number_of_data_nodes: number_of_data_nodes,
          active_primary_shards: active_primary_shards,
          active_shards: active_shards,
          relocating_shards: relocating_shards,
          initializing_shards: initializing_shards,
          unassigned_shards: unassigned_shards,
          unassigned_primary_shards: unassigned_primary_shards,
          delayed_unassigned_shards: delayed_unassigned_shards,
          number_of_pending_tasks: number_of_pending_tasks,
          number_of_in_flight_fetch: number_of_in_flight_fetch,
          task_max_waiting_in_queue_millis: task_max_waiting_in_queue_millis,
          active_shards_percent_as_number: active_shards_percent_as_number,
        }.stringify_keys
      end
    end

    class ClusterHealthResponseError < T::Struct
      const :cluster_name, String
      const :status, ClusterHealthStatus
      const :error, String

      def to_hash
        {
          cluster_name: cluster_name,
          status: status.serialize,
          error: error,
        }.stringify_keys
      end
    end

    # Returns `true` if searching of source code is currently enabled. Returns
    # `false` if it has been disabled.
    #
    # Defaults to true if KV is unavailable.
    def self.code_search_enabled?
      1 == GitHub.kv.get(::Search::CODE_SEARCH_ENABLED_KEY).value { 1 }.to_i # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    sig do
      params(
        blk: T.proc
          .params(cluster_health: T::Hash[String, T.untyped])
          .returns(T.untyped)
      )
     .void
    end
    def health_for_each_cluster(&blk)
      Elastomer.router.clusters.each do |name|
        begin
          client = Elastomer.router.client(name)
          next if !client.available?

          yield cluster_health(client.cluster).to_hash
        rescue Errno::ECONNREFUSED
          # ignore
        rescue RuntimeError => error
          yield ClusterHealthResponseError.new(
            cluster_name: name,
            status: ClusterHealthStatus::Red,
            error: error.message
          ).to_hash
          GitHub.logger.error(
            error,
            "code.namespace": self.class.name,
            "code.function": "health_for_each_cluster"
          )
        end
      end
    end

    sig { params(cluster: ElastomerClient::Client::Cluster).returns(ClusterHealthResponse) }
    def cluster_health(cluster)
      health = cluster.health.symbolize_keys
      status = ClusterHealthStatus.deserialize(health[:status])
      ClusterHealthResponse.new(health.merge(status: status))
    end

    # Set the key in Redis to enable source code indexing.
    def enable_code_search_indexing
      GitHub.kv.set(::Search::CODE_SEARCH_INDEXING_KEY, "1") # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    # Set the key in Redis to disable source code indexing.
    def disable_code_search_indexing
      GitHub.kv.set(::Search::CODE_SEARCH_INDEXING_KEY, "0") # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    # Returns `true` if searching of source code is currently enabled. Returns
    # `false` if it has been disabled.
    #
    def code_search_enabled?
      self.class.code_search_enabled?
    end

    # Set the key in Redis to enable source code searching.
    def enable_code_search
      GitHub.kv.set(::Search::CODE_SEARCH_ENABLED_KEY, "1") # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    # Set the key in Redis to disable source code searching.
    def disable_code_search
      GitHub.kv.set(::Search::CODE_SEARCH_ENABLED_KEY, "0") # rubocop:todo GitHub/DoNotUseGlobalKv
    end
  end  #  ClusterStatus
end  #  Search
