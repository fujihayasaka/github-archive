# typed: true
# frozen_string_literal: true

module GitHub
  module Partitioning
    module ScatterGatherer
      def self.query_all_shards(client_klass, rpc, req)
        client_connections = async_clients(client_klass)

        results = client_connections.map do |client_connection|
          client_connection[:client].public_send(rpc, req).then do |response| # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
            { shard_key: client_connection[:shard_key], response: response }
          end.rescue do |e|
            { shard_key: client_connection[:shard_key], error: e }
          end
        end

        Promise.all(results).sync.map do |result|
          response = result[:response]
          if result[:error].is_a?(Faraday::TimeoutError) || result[:error].is_a?(Faraday::ConnectionFailed) || result[:error].is_a?(Faraday::ServerError)
            { code: :unavailable, error: result[:error].detailed_message, shard_key: result[:shard_key] }
          elsif response.is_a?(Twirp::ClientResp) && response.error.present?
            { code: T.must(response.error).code, error: T.must(response.error).msg, shard_key: result[:shard_key] }
          else
            { code: :ok, data: response.data.data, shard_key: result[:shard_key] }
          end
        end
      end

      def self.async_clients(client_klass)
        GitHub::Partitioning::CrossPartitionConnections.concurrent_connections.map do |conn|
          {
            shard_key: conn.headers["X-Shard-Key"],
            client: client_klass.new(conn)
          }
        end
      end
    end
  end
end
