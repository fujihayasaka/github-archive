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
          begin
            connection.get(namespaced_key)
          rescue => e
            GitHub.logger.error("Error in GitHub::Partitioning::Denormalization::DenormalizedStore#get", {
              "code.namespace": "GitHub::Partitioning::Denormalization::DenormalizedStore",
              "code.function": "get",
              "gh.denormalized_store.service": @service,
              "gh.denormalized_store.namespace": @namespace,
              "exception.type": e.class.to_s,
              "exception.message": e.message,
            })
            nil
          end
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

        def add_to_sorted_array(key, value, ttl_seconds: TTL_SECONDS)
          current = get(key)
          array = current.present? ? JSON.parse(current) : []
          array << value
          set(key, array.uniq.sort.to_json, ttl_seconds: ttl_seconds)
        end

        def delete_from_array(key, value)
          current = get(key)
          return unless current.present?

          array = JSON.parse(current)
          array.delete(value)
          set(key, array.to_json)
        end

        private

        def cache_key(identifier:)
          "partitioning:#{@service}:#{@namespace}:#{identifier}"
        end
      end
    end
  end
end
