# typed: true
# frozen_string_literal: true

module GitHub
  module Cache
    # DualClient wraps both a Redis client and a Memcached client, routing operations
    # to one or the other based on a feature flag check performed once per request.
    #
    # This allows for gradual rollout of Redis as a replacement for Memcached in Proxima,
    # with per-request granularity but without the performance penalty of checking the
    # feature flag on every cache operation.
    #
    # The routing decision is memoized in request-scoped storage (GitHub.context)
    # and reused for all cache operations within that request.
    #
    # This class delegates ALL method calls to the chosen backend, so it supports
    # the full API of both RedisClient and the memcached Client.
    class DualClient
      attr_reader :redis_client, :memcached_client

      def initialize(redis_client, memcached_client, partition)
        @redis_client = redis_client
        @memcached_client = memcached_client
        @current_partition = partition
        @context_key = :"proxima_cache_backend_#{partition}"
        @clients = { redis: @redis_client, memcached: @memcached_client }
      end

      # Explicitly delegate common methods for performance
      # (avoids method_missing overhead from delegate_missing_to)

      # Basic cache operations
      def set(key, value, ttl = nil, raw = false)
        if validation_enabled?
          validate_set_operation(key, value, ttl, raw)
        else
          chosen_client.set(key, value, ttl, raw)
        end
      end

      def get(key, raw = false)
        if validation_enabled?
          validate_get_operation(key, raw)
        else
          chosen_client.get(key, raw)
        end
      end

      def delete(key)
        chosen_client.delete(key)
      end

      def add(key, value, ttl = nil, raw = false)
        chosen_client.add(key, value, ttl, raw)
      end

      def replace(key, value, ttl = nil, raw = false)
        chosen_client.replace(key, value, ttl, raw)
      end

      def exist?(key, options = nil)
        chosen_client.exist?(key, options)
      end

      def append(key, value)
        chosen_client.append(key, value)
      end

      def prepend(key, value)
        chosen_client.prepend(key, value)
      end

      # Multi-key operations
      def get_multi(keys, raw = false)
        if validation_enabled?
          validate_get_multi_operation(keys, raw)
        else
          chosen_client.get_multi(keys, raw)
        end
      end

      def read_multi(*keys)
        chosen_client.read_multi(*keys)
      end

      # Increment/decrement operations
      def increment(name, amount = 1, options = nil)
        chosen_client.increment(name, amount, options)
      end

      def decrement(name, amount = 1, options = nil)
        chosen_client.decrement(name, amount, options)
      end

      def incr(name, amount = 1)
        chosen_client.incr(name, amount)
      end

      def decr(name, amount = 1)
        chosen_client.decr(name, amount)
      end

      # Aliases for set/get (ActiveSupport::Cache interface)
      def write(key, value, options = {})
        if validation_enabled?
          validate_write_operation(key, value, options)
        else
          chosen_client.write(key, value, options)
        end
      end

      def read(key, options = nil)
        if validation_enabled?
          validate_read_operation(key, options)
        else
          chosen_client.read(key, options)
        end
      end

      def fetch(key, options = {}, &block)
        if validation_enabled?
          validate_fetch_operation(key, options, &block)
        else
          chosen_client.fetch(key, options, &block)
        end
      end

      # Metadata and inspection
      def stats
        chosen_client.stats
      end

      def servers
        chosen_client.servers
      end

      def options
        chosen_client.options
      end

      def set_servers(server_structs)
        chosen_client.set_servers(server_structs)
      end

      def set_runtime_servers(server_structs)
        chosen_client.set_runtime_servers(server_structs)
      end

      def server_by_key(key)
        chosen_client.server_by_key(key)
      end

      def reset(server_structs = nil)
        chosen_client.reset(server_structs)
      end

      def clear
        chosen_client.clear
      end

      alias_method :flush, :clear

      # Local cache accessors
      def local
        chosen_client.local
      end

      def local=(value)
        @redis_client.local = value
        @memcached_client.local = value
      end

      def local_hit_count
        chosen_client.local_hit_count
      end

      def enable_local_cache
        @redis_client.enable_local_cache
        @memcached_client.enable_local_cache
      end

      # Disable write functionality
      def disable_write(&block)
        @redis_client.disable_write(&block)
        @memcached_client.disable_write(&block)
      end

      # Skip functionality
      def skip
        chosen_client.skip
      end

      def skip=(value)
        @redis_client.skip = value
        @memcached_client.skip = value
      end

      # Partition management
      def current_partition=(value)
        @redis_client.current_partition = value
        @memcached_client.current_partition = value
      end

      def current_partition
        chosen_client.current_partition
      end

      def for_partition(key)
        chosen_client.for_partition(key)
      end

      def disable_partition(key)
        chosen_client.disable_partition(key)
      end

      # Logging
      def logger
        chosen_client.logger
      end

      def logger=(value)
        @redis_client.logger = value
        @memcached_client.logger = value
      end

      # Async operations
      def async_get(key, raw = false)
        chosen_client.async_get(key, raw)
      end

      def async_set(key, value, ttl = 0, raw = false)
        chosen_client.async_set(key, value, ttl, raw)
      end

      def async_get_multi(keys, raw = false)
        chosen_client.async_get_multi(keys, raw)
      end

      def async_add(key, value, ttl = 0, raw = false)
        chosen_client.async_add(key, value, ttl, raw)
      end

      def async_replace(key, value, ttl = 0, raw = false)
        chosen_client.async_replace(key, value, ttl, raw)
      end

      def async_append(key, value)
        chosen_client.async_append(key, value)
      end

      def async_prepend(key, value)
        chosen_client.async_prepend(key, value)
      end

      def async_incr(key, value = 1)
        chosen_client.async_incr(key, value)
      end

      def async_decr(key, value = 1)
        chosen_client.async_decr(key, value)
      end

      def async_delete(key)
        chosen_client.async_delete(key)
      end

      def async_exist?(key, options = nil)
        chosen_client.async_exist?(key, options)
      end

      def async_get_or_cache(key, options = {}, &block)
        chosen_client.async_get_or_cache(key, options, &block)
      end

      # Methods used by LazyCache
      def orig_get(key, raw = false)
        chosen_client.orig_get(key, raw)
      end

      def orig_get_multi(keys, raw = false)
        chosen_client.orig_get_multi(keys, raw)
      end

      def orig_set(key, value, ttl = nil, raw = false)
        chosen_client.orig_set(key, value, ttl, raw)
      end

      def orig_add(key, value, ttl = nil, raw = false)
        chosen_client.orig_add(key, value, ttl, raw)
      end

      def orig_incr(*args)
        chosen_client.orig_incr(*args)
      end

      def orig_decr(*args)
        chosen_client.orig_decr(*args)
      end

      def orig_delete(key, options = nil)
        chosen_client.orig_delete(key, options)
      end

      def orig_exist?(key, options = nil)
        chosen_client.orig_exist?(key, options)
      end

      private

      def chosen_client
        # Check once per request and memoize in request-scoped storage
        cached_choice = GitHub.context[@context_key]
        return @clients[cached_choice] if cached_choice && @clients.key?(cached_choice)

        # Make routing decision (only happens once per request per partition)
        # Default to memcached if we can't check the feature flag (e.g., during startup)
        use_redis = begin
          FeatureFlag.vexi.enabled?(:proxima_redis_cache, default: false)
        rescue => e
          GitHub.dogstats.increment("github.cache.dual_client.feature_flag_error",
            tags: ["error_class:#{e.class.name}", "partition:#{@current_partition}"]
          )
          false
        end

        client_key = use_redis ? :redis : :memcached
        client = @clients[client_key]

        # Emit routing metric (only once per request per partition)
        GitHub.dogstats.increment("github.cache.dual_client.routing",
          tags: [
            "backend:#{client_key}",
            "partition:#{@current_partition}"
          ]
        )

        # Store the decision in context for the duration of the request
        GitHub.context.push(@context_key => client_key)
        client
      end

      # Data validation methods
      def validation_enabled?
        # Check once per request and memoize in request-scoped storage
        validation_key = :"proxima_validation_enabled_#{@current_partition}"
        cached_decision = GitHub.context[validation_key]
        return cached_decision unless cached_decision.nil?

        enabled = begin
          FeatureFlag.vexi.enabled?(:proxima_dual_client_data_validation, default: false)
        rescue => e
          GitHub.dogstats.increment("github.cache.dual_client.validation_flag_error",
            tags: ["error_class:#{e.class.name}", "partition:#{@current_partition}"]
          )
          false
        end

        # Store the decision in context for the duration of the request
        GitHub.context.push(validation_key => enabled)
        enabled
      end

      def validate_get_operation(key, raw)
        # Perform the "real" operation with memcached
        memcached_result = @memcached_client.get(key, raw)

        # Validate with redis
        begin
          # Set in redis to ensure key exists for comparison
          @redis_client.set(key, memcached_result, nil, raw) unless memcached_result.nil?

          redis_result = @redis_client.get(key, raw)
          compare_results("get", key, memcached_result, redis_result, raw: raw)
        rescue => e
          log_validation_error("get", key, e)
        end

        # Always return memcached result
        memcached_result
      end

      def validate_set_operation(key, value, ttl, raw)
        # Perform the "real" operation with memcached
        memcached_result = @memcached_client.set(key, value, ttl, raw)

        # Validate with redis
        begin
          # Set in redis
          @redis_client.set(key, value, ttl, raw)

          # Retrieve from both to validate
          memcached_retrieved = @memcached_client.get(key, raw)
          redis_retrieved = @redis_client.get(key, raw)

          compare_results("set", key, memcached_retrieved, redis_retrieved, raw: raw, original_value: value)
        rescue => e
          log_validation_error("set", key, e)
        end

        # Always return memcached result
        memcached_result
      end

      def validate_read_operation(key, options)
        # Perform the "real" operation with memcached
        memcached_result = @memcached_client.read(key, options)

        # Validate with redis
        begin
          @redis_client.write(key, memcached_result, options)
          redis_result = @redis_client.read(key, options)

          raw = options && !!options[:raw]
          compare_results("read", key, memcached_result, redis_result, raw: raw)
        rescue => e
          log_validation_error("read", key, e)
        end

        # Always return memcached result
        memcached_result
      end

      def validate_write_operation(key, value, options)
        # Perform the "real" operation with memcached
        memcached_result = @memcached_client.write(key, value, options)

        # Validate with redis
        begin
          # Write to redis
          @redis_client.write(key, value, options)

          # Retrieve from both to validate
          memcached_retrieved = @memcached_client.read(key, options)
          redis_retrieved = @redis_client.read(key, options)

          raw = options && !!options[:raw]
          compare_results("write", key, memcached_retrieved, redis_retrieved, raw: raw, original_value: value)
        rescue => e
          log_validation_error("write", key, e)
        end

        # Always return memcached result
        memcached_result
      end

      def validate_fetch_operation(key, options, &block)
        # Perform the "real" operation with memcached
        memcached_result = @memcached_client.fetch(key, options, &block)

        # Validate with redis
        begin
          @redis_client.write(key, memcached_result, options) unless memcached_result.nil?

          redis_result = @redis_client.fetch(key, options) do
            memcached_result
          end

          raw = options && !!options[:raw]
          compare_results("fetch", key, memcached_result, redis_result, raw: raw)
        rescue => e
          log_validation_error("fetch", key, e)
        end

        # Always return memcached result
        memcached_result
      end

      def validate_get_multi_operation(keys, raw)
        # Perform the "real" operation with memcached
        memcached_result = @memcached_client.get_multi(keys, raw)

        # Validate with redis
        begin
          # Write all memcached results to redis
          memcached_result.each do |key, value|
            @redis_client.set(key, value, nil, raw)
          end

          redis_result = @redis_client.get_multi(keys, raw)

          keys.each do |key|
            memcached_value = memcached_result[key]
            redis_value = redis_result[key]
            compare_results("get_multi", key, memcached_value, redis_value, raw: raw)
          end
        rescue => e
          log_validation_error("get_multi", keys, e)
        end

        # Always return memcached result
        memcached_result
      end

      def compare_results(operation, key, memcached_value, redis_value, raw: false, original_value: nil)
        if memcached_value == redis_value
          GitHub.dogstats.increment("github.cache.dual_client.validation.match",
            tags: ["operation:#{operation}", "partition:#{@current_partition}", "raw:#{raw}"]
          )
        else
          GitHub.dogstats.increment("github.cache.dual_client.validation.mismatch",
            tags: ["operation:#{operation}", "partition:#{@current_partition}", "raw:#{raw}"]
          )

          # Log detailed information about the mismatch
          GitHub.logger.warn(
            "Cache validation mismatch",
            operation: operation,
            key: key,
            partition: @current_partition,
            memcached_value: safe_inspect(memcached_value),
            redis_value: safe_inspect(redis_value),
            original_value: safe_inspect(original_value),
            raw: raw
          )
        end
      end

      def log_validation_error(operation, key, error)
        GitHub.dogstats.increment("github.cache.dual_client.validation.error",
          tags: [
            "operation:#{operation}",
            "error_class:#{error.class.name}",
            "partition:#{@current_partition}"
          ]
        )

        GitHub.logger.error(
          "Cache validation error",
          operation: operation,
          key: key,
          partition: @current_partition,
          error_class: error.class.name,
          error_message: error.message
        )
      end

      def safe_inspect(value)
        return "nil" if value.nil?
        # Truncate large values to avoid bloating logs
        inspected = value.inspect
        inspected.length > 1000 ? "#{inspected[0..1000]}... (truncated)" : inspected
      rescue => e
        "<error inspecting value: #{e.message}>"
      end
    end
  end
end
