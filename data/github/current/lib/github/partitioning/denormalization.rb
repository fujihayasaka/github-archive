# typed: true
# frozen_string_literal: true

module GitHub
  module Partitioning
    module Denormalization
      SERVICE_TO_REDIS_CONN = {
        "pull_requests": {
          "same_network_repos": "config/redis2.yml",
        }
      }

      TTL_SECONDS = 60 * 60 # 1 hour

      class DenormalizedStore
        def initialize(service:, namespace:)
          @service = service
          @namespace = namespace
          @connection_config = SERVICE_TO_REDIS_CONN.dig(service, namespace)
          raise ArgumentError, "Invalid service redis connection. Make sure your service and store are registered." unless @connection_config.present?
        end

        def connection
          @connection ||= ::Redis.new(GitHub.read_redis_config(@connection_config))
        end

        def get(key)
          namespaced_key = cache_key(identifier: key)
          connection.get(namespaced_key)
        end

        def set(key, value, ttl_seconds: TTL_SECONDS)
          namespaced_key = cache_key(identifier: key)
          connection.set(namespaced_key, value, ex: ttl_seconds)
        end

        def fetch(key, ttl_seconds: TTL_SECONDS)
          value = get(key)
          return value if value.present?

          value = yield
          set(key, value, ttl_seconds:)
          value
        end

        private

        def cache_key(identifier:)
          "partitioning:#{@service}:#{@namespace}:#{identifier}"
        end
      end
    end
  end
end
