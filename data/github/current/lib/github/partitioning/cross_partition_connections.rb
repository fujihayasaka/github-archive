# typed: true
# frozen_string_literal: true

module GitHub
  module Partitioning
    module CrossPartitionConnections
      def self.configure_concurrent_connections
        # In a real implementation, the shard key would be based on configurations we set in the environment
        [1, 2, 3].map do |shard_key|
          ConcurrentFaraday.new(url: GitHub.cross_partition_query_connection_url) do |conn|
            conn.use GitHub::FaradayMiddleware::RequestID
            conn.use ::GitHub::FaradayMiddleware::RaiseError
            conn.use GitHub::FaradayMiddleware::DatadogAsync, stats: GitHub.dogstats, service_name: "partitioning"
            conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.partitioning_hmac_key

            conn.options[:open_timeout] = GitHub.cross_partition_query_open_timeout # connection open timeout in seconds.
            conn.options[:timeout] = GitHub.cross_partition_query_read_timeout  # read timeout in seconds.

            conn.headers["X-Shard-Key"] = shard_key

            conn.adapter :concurrent_adapter, persistent: true
          end
        end
      end

      def self.concurrent_connections
        @concurrent_connections ||= configure_concurrent_connections
      end
    end
  end
end
