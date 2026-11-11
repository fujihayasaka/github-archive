# typed: true
# frozen_string_literal: true

require "zlib"

module GitHub
  module Cache
    # Do no use this client yet. This is currently only used in Proxima with Azure Managed Redis.
    # Come talk to use in #m2r or #cache-project in Slack before trying this.
    #
    # Redis-based cache client
    #
    # This client provides a drop-in replacement for memcached,
    # using Redis as the backend store with the following features:
    #
    # - **memcached compatibility**: Same interface as GitHub::Cache::Client
    # - **1MB value size limit**: Hard limit matching memcached (raises ValueTooBig)
    # - **MessagePack serialization**: Uses GitHub::Cache::Codec (no compression)
    # - **Opt-in local cache**: Request-scoped memoization using GH.context
    # - **Circuit breaker**: Automatic failure detection and recovery
    class RedisClient
      # Maximum value size - matches memcached's limit (1024 * 1023 bytes)
      # Memcached raises ValueTooBig if exceeded, so we do the same
      MAX_VALUE_SIZE = T.let(1024 * 1023, Integer)

      # Zipping constants (from GitHub::Cache::Zip)
      MAX_ATTEMPT_CACHE_SIZE = T.let(10_000_000, Integer)
      MAX_UNZIPPED_SIZE      = T.let(500_000, Integer)
      ZIP_HEADER             = T.let(:z, Symbol)

      # Sentinel value for cache misses in local cache
      MISSING = T.let(Object.new.freeze, Object)

      class ValueTooBig < StandardError; end

      sig { returns(Symbol) }
      attr_accessor :current_partition

      sig { returns(T.untyped) }
      attr_accessor :logger

      sig { returns(T.nilable(T::Boolean)) }
      attr_accessor :skip

      sig { params(namespace: String, partition: Symbol).void }
      def initialize(namespace:, partition:)
        @namespace = T.let(namespace, String)
        @current_partition = T.let(partition, Symbol)
        @redis = T.let(nil, T.nilable(::Redis::Namespace))
        @disable_write = T.let(false, T::Boolean)
      end

      # Basic cache operations

      def _set(key, value, ttl = nil, raw = false)
        # Debug: TODO remove https://github.com/github/performance-engineering/issues/1776
        instrument_nil_set(key, value, ttl, raw) if value.nil?

        key = normalize_key(key) # Normalize array keys to strings
        return false unless attempt_cache?(value)

        original_value = value # Store the original value for local cache
        encoded_value, raw, success = encode_value(key, value, !!raw)
        return false unless success

        final_options = { expires_in: ttl }

        # Check size limit AFTER serialization - ensures all values are checked regardless of type
        if encoded_value.respond_to?(:bytesize) && encoded_value.bytesize > MAX_VALUE_SIZE
          GitHub.dogstats.increment("github.cache.redis_client.error.value-too-big",
            tags: ["partition:#{@current_partition}", "namespace:#{@namespace}", "controller:#{GitHub.context[:controller]}", "action:#{GitHub.context[:action]}"]
          )
          raise ValueTooBig.new("#{key} serialized size is #{encoded_value.bytesize} bytes (max: #{MAX_VALUE_SIZE})")
        end

        ttl_seconds = extract_ttl(final_options)

        if ttl_seconds && ttl_seconds > 0
          redis.setex(key, ttl_seconds, encoded_value)
        else
          redis.set(key, encoded_value)
        end

        write_to_local_cache(key, original_value)
        true
      end

      sig { params(key: T.untyped, value: T.untyped, ttl: T.nilable(Integer), raw: T.nilable(T::Boolean)).returns(T.untyped) }
      def set(key, value, ttl = nil, raw = false)
        if disable_write
          return value
        end

        instrument("set", key) do
          _set(key, value, ttl, !!raw)
        end
      end

      # Returns true if written, nil if key exists and :unless_exist option is used
      sig { params(key: T.untyped, value: T.untyped, options: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
      def write(key, value, options = {})
        ttl = extract_ttl(options)
        raw = !!options[:raw]

        if options[:unless_exist]
          return add(key, value, ttl, raw)
        end

        set(key, value, ttl, raw)
      end

      sig { params(key: T.untyped, options: T.untyped, block: T.nilable(T.proc.returns(T.untyped))).returns(T.untyped) }
      def fetch(key, options = {}, &block)
        options = { force: !!options } if !options.is_a?(Hash)
        write_cache = options[:force]

        if !write_cache
          # use get_multi so we can differentiate between cache miss and nil value
          cache_result = get_multi([key], !!options[:raw])
          # get_multi returns results with original keys, so use the original key
          cache_value = cache_result[key]
          write_cache = !cache_result.key?(key)
        end

        if write_cache && block_given?
          cache_value = cache_write_on_miss(key, options) { yield }
        end

        cache_value
      end

      def _get(key, raw = false)
        key = normalize_key(key) # Normalize array keys to strings

        if !!skip
          delete(key)
          return nil
        end

        # Check local cache first if enabled
        if in_local_cache?(key)
          cached = read_from_local_cache(key)
          hit_type = cached == MISSING ? "miss" : "hit"

          # Increment local hit count on actual hits (not misses)
          increment_local_hit_count if hit_type == "hit"

          GitHub.dogstats.increment("github.cache.redis_client.local_cache.#{hit_type}",
            tags: ["partition:#{@current_partition}", "controller:#{GitHub.context[:controller]}", "action:#{GitHub.context[:action]}", "namespace:#{@namespace}"]
          )
          return (cached == MISSING ? nil : cached)
        end

        value = redis.get(key)
        # if we got nil from redis, it's a cache miss
        # Set missing and skip decoding
        if value.nil?
          write_to_local_cache(key, MISSING)
          return nil
        end

        # Store in local cache (including misses) and return the final decoded value
        decoded_value = decode_value(key, value, !!raw)
        write_to_local_cache(key, decoded_value)
        decoded_value
      end

      sig { params(key: T.untyped, raw: T.nilable(T::Boolean)).returns(T.untyped) }
      def get(key, raw = false)
        instrument("get", key) do
          _get(key, !!raw)
        end
      end

      sig { params(key: T.untyped, options: T.untyped).returns(T.untyped) }
      def read(key, options = nil)
        get(key, options && !!options[:raw])
      end

      sig { params(key: T.untyped, _raw: T::Boolean).returns(T.untyped) }
      def delete(key, _raw = false)
        key = normalize_key(key) # Normalize array keys to strings

        if disable_write
          return _get(key)
        end

        instrument("delete", key) do
          # raw parameter exists for API compatibility with memcached but is not used
          delete_from_local_cache(key)
          # redis.del returns the number of keys deleted (0 or 1)
          # Convert to boolean to match memcached behavior: true if key existed, false if not
          redis.del(key) > 0
        end
      end

      # Multi-key operations

      sig { params(keys: T.any(String, T::Array[String]), raw: T.nilable(T::Boolean)).returns(T::Hash[String, T.untyped]) }
      def get_multi(keys, raw = false)
        # Convert to array if needed
        keys_array = Array(keys)

        # Create a mapping from normalized keys back to original keys
        # This allows us to return results with the original keys that callers expect
        normalized_to_original = {}
        normalized_keys = keys_array.map do |original_key|
          normalized = normalize_key(original_key)
          normalized_to_original[normalized] = original_key
          normalized
        end

        instrument("get_multi", normalized_keys) do
          if !!skip
            normalized_keys.each { |key| delete(key) }
            next {}
          end

          next {} if normalized_keys.empty?

          # check local cache first, then fetch missing keys from Redis
          hits = {}
          misses = normalized_keys.reject do |normalized_key|
            if in_local_cache?(normalized_key)
              increment_local_hit_count
              cached = read_from_local_cache(normalized_key)
              unless cached.eql?(MISSING)
                # Use the original key in the result hash
                original_key = normalized_to_original[normalized_key]
                hits[original_key] = cached
              end
              true
            end
          end

          if misses.any?
            values = redis.mget(misses)
            misses.each_with_index do |normalized_key, index|
              value = values[index]

              if value.nil?
                write_to_local_cache(normalized_key, MISSING)
              else
                decoded_value = decode_value(normalized_key, value, !!raw)
                original_key = normalized_to_original[normalized_key]
                hits[original_key] = decoded_value
                write_to_local_cache(normalized_key, decoded_value)
              end
            end
          end

          hits
        end
      end

      def read_multi(*keys)
        get_multi(keys)
      end

      # Increment/decrement operations

      # Match Memcached::Rails signature: increment(name, amount = 1, options = nil)
      # This should only be performed on integer values stored raw as strings (to match memcached behavior)
      # Ex: cache.set("counter", "10", ttl = 60, raw = true)
      #     cache.increment("counter", 5) => 15
      sig { params(name: T.untyped, amount: T.untyped, _options: T.untyped).returns(T.untyped) }
      def increment(name, amount = 1, _options = nil)
        name = normalize_key(name) # Normalize array keys to strings
        instrument("increment", name) do
          change_counter(name, amount)
        end
      end

      # Alias for compatibility with memcached interface (incr vs increment)
      sig { params(name: T.untyped, amount: T.untyped).returns(T.untyped) }
      def incr(name, amount = 1)
        increment(name, amount)
      end

      # Match Memcached::Rails signature: decrement(name, amount = 1)
      # This should only be performed on integer values stored raw as strings (to match memcached behavior)
      # Ex: cache.set("counter", "10", ttl = 60, raw = true)
      #     cache.decrement("counter", 5) => 5
      sig { params(name: T.untyped, amount: T.untyped, _options: T.untyped).returns(T.untyped) }
      def decrement(name, amount = 1, _options = nil)
        name = normalize_key(name) # Normalize array keys to strings
        instrument("decrement", name) do
          change_counter(name, -amount)
        end
      end

      # Alias for compatibility with memcached interface (decr vs decrement)
      sig { params(name: T.untyped, amount: T.untyped).returns(T.untyped) }
      def decr(name, amount = 1)
        decrement(name, amount)
      end

      def append(key, value)
        key = normalize_key(key)  # Normalize array keys to strings

        if disable_write
          return nil
        end

        instrument("append", key) do
          existing_value = _get(key, true)
          raise "Key #{key} does not exist for append" if existing_value.nil?

          new_value = existing_value + value
          _set(key, new_value, nil, true)
          nil
        rescue => e
          log_error("append", key, e)
          nil
        end
      end

      def prepend(key, value)
        key = normalize_key(key)  # Normalize array keys to strings

        if disable_write
          return nil
        end

        instrument("prepend", key) do
          existing_value = _get(key, true)
          raise "Key #{key} does not exist for prepend" if existing_value.nil?

          new_value = value + existing_value
          _set(key, new_value, nil, true)
          nil
        rescue => e
          log_error("prepend", key, e)
          nil
        end
      end

      # Redis SET with NX option is equivalent to memcached ADD
      # Returns true if key was added, nil if key already exists (matches memcached behavior)
      sig { params(key: T.untyped, value: T.untyped, ttl: T.nilable(Integer), raw: T::Boolean).returns(T.nilable(TrueClass)) }
      def add(key, value, ttl = nil, raw = false)
        key = normalize_key(key) # Normalize array keys to strings

        if disable_write
          return nil # Match memcached behavior (nil = not added)
        end

        instrument("add", key) do
          next nil unless attempt_cache?(value) # Match memcached behavior (nil = not added)

          original_value = value  # Store the original value for local cache
          encoded_value, raw, success = encode_value(key, value, !!raw)
          next nil unless success # Match memcached behavior (nil = not added)

          # Check size limit AFTER serialization - ensures all values are checked regardless of type
          if encoded_value.respond_to?(:bytesize) && encoded_value.bytesize > MAX_VALUE_SIZE
            GitHub.dogstats.increment("github.cache.redis_client.error.value-too-big",
              tags: ["partition:#{@current_partition}", "namespace:#{@namespace}", "controller:#{GitHub.context[:controller]}", "action:#{GitHub.context[:action]}"]
            )
            raise ValueTooBig.new("#{key} encoded size is #{encoded_value.bytesize} bytes (max: #{MAX_VALUE_SIZE})")
          end

          ttl = extract_ttl(expires_in: ttl)

          # SET with NX returns true if key was set (didn't exist), false otherwise
          result = if ttl && ttl > 0
            redis.set(key, encoded_value, ex: ttl, nx: true)
          else
            redis.set(key, encoded_value, nx: true)
          end

          # Write to local cache if successful
          write_to_local_cache(key, original_value) if result
          # Redis SET NX returns "OK" on success, nil when key already exists
          # Normalize to true or nil to match memcached behavior
          result ? true : nil
        end
      end

      # Redis SET with XX option is equivalent to memcached REPLACE
      # Only sets the value if the key already exists
      sig { params(key: T.untyped, value: T.untyped, ttl: T.nilable(Integer), raw: T::Boolean).returns(T::Boolean) }
      def replace(key, value, ttl = nil, raw = false)
        key = normalize_key(key)  # Normalize array keys to strings

        if disable_write
          return false
        end

        instrument("replace", key) do
          next false unless attempt_cache?(value)

          original_value = value  # Store the original value for local cache
          encoded_value, raw, success = encode_value(key, value, !!raw)
          next false unless success

          # Check size limit AFTER serialization
          if encoded_value.respond_to?(:bytesize) && encoded_value.bytesize > MAX_VALUE_SIZE
            GitHub.dogstats.increment("github.cache.redis_client.error.value-too-big",
              tags: ["partition:#{@current_partition}", "namespace:#{@namespace}", "controller:#{GitHub.context[:controller]}", "action:#{GitHub.context[:action]}"]
            )
            raise ValueTooBig.new("#{key} encoded size is #{encoded_value.bytesize} bytes (max: #{MAX_VALUE_SIZE})")
          end

          ttl = extract_ttl(expires_in: ttl)

          # SET with XX returns true if key was set (key existed), false otherwise
          result = if ttl && ttl > 0
            redis.set(key, encoded_value, ex: ttl, xx: true)
          else
            redis.set(key, encoded_value, xx: true)
          end

          # Write to local cache if successful
          write_to_local_cache(key, original_value) if result
          !!result # Convert to boolean
        end
      end

      sig { params(key: T.untyped, _options: T.untyped).returns(T::Boolean) }
      def exist?(key, _options = nil)
        key = normalize_key(key) # Normalize array keys to strings

        instrument("exist?", key) do
          redis.exists?(key)
        end
      rescue => e
        log_error("exist?", key, e)
        false
      end

      # Metadata methods for compatibility with GitHub::Cache::Client interface

      sig { returns(T::Hash[String, T.untyped]) }
      def stats
        {
          "redis_client" => true,
          "namespace" => @namespace,
          "partition" => @current_partition,
          "connected" => redis_connected?
        }
      rescue
        {
          "redis_client" => true,
          "namespace" => @namespace,
          "partition" => @current_partition,
          "connected" => false
        }
      end

      sig { returns(T::Array[String]) }
      def servers
        # Return the Redis connection info
        ["redis://#{redis._client.host}:#{redis._client.port}"]
      rescue
        ["redis://unknown"]
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def options
        {
          redis_client: true,
          namespace: @namespace,
          partition: @current_partition
        }
      end

      # Methods needed for ICacheConfig interface compatibility
      sig { params(server_structs: T.untyped).void }
      def set_servers(server_structs)
        # No-op for Redis - connection is managed elsewhere
      end

      sig { params(server_structs: T.untyped).void }
      def set_runtime_servers(server_structs)
        # No-op for Redis - connection is managed elsewhere
      end

      sig { params(key: String).returns(T.nilable(String)) }
      def server_by_key(key)
        servers.first
      end

      sig { params(server_structs: T.untyped).void }
      def reset(server_structs = nil)
        # No-op for Redis
      end

      sig { void }
      def clear
        # No-op for compatibility with memcached interface
        # In memcached, clear is a no-op that returns nil
        # We don't actually flush the Redis database here for safety
      end

      alias_method :flush, :clear

      # Local cache accessors for compatibility with memcached client

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def local
        # Use GH.context.remote_cache_registry just like RemoteCache::LocalStore does
        # This is request-scoped and automatically cleaned up
        return unless registry = ::GH.context.remote_cache_registry

        registry[local_cache_key]
      rescue
        nil
      end

      sig { params(value: T.nilable(T::Hash[String, T.untyped])).void }
      def local=(value)
        return unless registry = ::GH.context.remote_cache_registry

        if value.nil?
          registry.delete(local_cache_key)
        else
          registry[local_cache_key] = value
        end
      end

      sig { returns(Integer) }
      def local_hit_count
        # Track local cache hits in the local cache itself
        # Use a special key that won't conflict with user keys
        local&.dig("__local_hit_count__") || 0
      end

      sig { void }
      def enable_local_cache
        self.local = {}
      end

      # Expose redis connection for testing purposes
      sig { returns(::Redis::Namespace) }
      def redis
        @redis ||= build_redis_connection
      end

      def async_get(key, raw = false)
        Promise.resolve.then do
          results = get_multi([key], !!raw)
          value = results[key]
          exists = results.key?(key)
          ::GitHub::Cache::FakeResponse.new(key: key, value: value, exists: exists)
        end
      end

      def async_set(key, value, ttl = 0, raw = false)
        Promise.resolve(value).then do |resolved_value|
          if disable_write
            ::GitHub::Cache::FakeResponse.new(key: key, value: resolved_value, stored: true)
          else
            stored = set(key, resolved_value, ttl, !!raw)
            ::GitHub::Cache::FakeResponse.new(key: key, value: resolved_value, stored: stored)
          end
        end
      end

      def async_get_multi(keys, raw = false)
        Promise.resolve.then do
          get_multi(keys, !!raw)
        end
      end

      def async_add(key, value, ttl = 0, raw = false)
        Promise.resolve(value).then do |resolved_value|
          if disable_write
            ::GitHub::Cache::FakeResponse.new(key: key, value: resolved_value, stored: true)
          else
            stored = !!add(key, resolved_value, ttl, !!raw)
            FakeResponse.new(key: key, value: resolved_value, stored: stored)
          end
        end
      end

      def async_replace(key, value, ttl = 0, raw = false)
        Promise.resolve(value).then do |resolved_value|
          if disable_write
            ::GitHub::Cache::FakeResponse.new(key: key, value: resolved_value, stored: true)
          else
            stored = !!replace(key, resolved_value, ttl, !!raw)
            FakeResponse.new(key: key, value: resolved_value, stored: stored)
          end
        end
      end

      def async_append(key, value)
        Promise.resolve(value).then do |resolved_value|
          if disable_write
            nil
          else
            append(key, resolved_value)
            FakeResponse.new(key: key, value: nil, stored: true)
          end
        end
      end

      def async_prepend(key, value)
        Promise.resolve(value).then do |resolved_value|
          if disable_write
            nil
          else
            prepend(key, resolved_value)
            FakeResponse.new(key: key, value: nil, stored: true)
          end
        end
      end

      def async_incr(key, value = 1)
        if disable_write
          async_get(key).then do |response|
            if response.exist?
              new_value = response.value.to_i + value
              ::GitHub::Cache::FakeResponse.new(key: key, value: new_value, stored: true)
            else
              new_value = 0 + value
              ::GitHub::Cache::FakeResponse.new(key: key, value: new_value, stored: true)
            end
          end
        else
          Promise.resolve.then do
            FakeResponse.new(key: key, value: incr(key, value), stored: true)
          end
        end
      end

      def async_decr(key, value = 1)
        if disable_write
          async_get(key).then do |response|
            if response.exist?
              new_value = response.value.to_i - value
              ::GitHub::Cache::FakeResponse.new(key: key, value: new_value, stored: true)
            else
              new_value = 0 - value
              ::GitHub::Cache::FakeResponse.new(key: key, value: new_value, stored: true)
            end
          end
        else
          Promise.resolve.then do
            FakeResponse.new(key: key, value: decr(key, value), stored: true)
          end
        end
      end

      def async_delete(key, raw = false)
        if disable_write
          async_get(key)
        else
          Promise.resolve.then do
            delete(key)
            FakeResponse.new(key: key, value: nil, stored: true)
          end
        end
      end

      def async_exist?(key, options = nil)
        Promise.resolve.then do
          exist?(key, options)
        end
      end

      def async_get_or_cache(key, options = {}, &block)
        options = { force: !!options } if !options.is_a?(Hash)
        force_write = options[:force]

        existing_value = if force_write
          Promise.resolve(::GitHub::Cache::FakeResponse.new(key: key, value: nil, exists: false))
        else
          async_get(key, !!options[:raw])
        end

        existing_value.then do |response|
          value_promise = if response.exist?
            Promise.resolve(response.value)
          else
            safe_value = Promise.resolve(true).then { block.call }
            safe_value.then do |new_value|
              async_set(key, new_value, (options[:ttl] || 0), !!options[:raw]).then { new_value }
            end
          end

          value_promise.then do |value|
            value
          end
        end
      end

      # Methods used by LazyCache
      def orig_get(key, raw = false)
        get(key, raw)
      end

      def orig_get_multi(keys, raw = false)
        get_multi(keys, raw)
      end

      def orig_set(key, value, ttl = nil, raw = false)
        set(key, value, ttl, raw)
      end

      def orig_add(key, value, ttl = nil, raw = false)
        add(key, value, ttl, raw)
      end

      def orig_incr(*args)
        key = args[0]
        amount = args[1] || 1
        increment(key, amount)
      end

      def orig_decr(*args)
        key = args[0]
        amount = args[1] || 1
        decrement(key, amount)
      end

      def orig_delete(key, options = nil)
        delete(key)
      end

      def orig_exist?(key, options = nil)
        exist?(key)
      end

      # Disable write functionality - allows temporarily disabling cache writes
      # When disabled, write operations simulate success without actually writing to Redis
      #
      # Can be used with a block to temporarily disable: client.disable_write { ... }
      #
      # @param block [Proc] Optional block to execute with writes disabled
      # @return [Boolean] Current disable_write state (or previous state when used with block)
      def disable_write(&block)
        if block_given?
          @disable_write.tap do |old_value|
            @disable_write = true
            begin
              yield
            ensure
              @disable_write = old_value
            end
          end
        else
          @disable_write
        end
      end

      def for_partition(key)
        return GitHub.cache_partitions[:global] if GitHub.single_or_multi_tenant_enterprise?
        if !GitHub.cache_partitions.key? key
          raise ArgumentError, "`#{key}` does not match partitions in `memcached.yml`"
        end
        GitHub.cache_partitions[key]
      end

      # Disable use of a partition by swapping for the global Rails cache client
      # (experimental)
      # Example:
      # ```rb
      # # Disable cache partition for all callers to `GitHub.cache.for_partition(:p)`
      # # if self.respond_to? :current_partition
      # #   p = self.current_partition
      # #   GitHub.cache.disable_partition p
      # # end
      # ```
      def disable_partition(key)
        if !GitHub.cache_partitions.key? key
          logger.warn "disable partition `#{key}` not found in `memcached.yml`" if logger
          return GitHub.cache_partitions[:global]
        end
        GitHub.cache_partitions[key] = GitHub.cache_partitions[:global]
      end

      # Instrumentation
      class << self
        delegate :query_time, :query_time=, :query_count, :query_count=,
                :query_tracing, :query_tracing=, :query_sets, :query_sets=,
                :query_hits, :query_hits=, :query_misses, :query_misses=,
                :query_events, :query_events=, :track_events, :track_events=,
                :distributed_tracing_enabled, :distributed_tracing_enabled=,
          to: :collector
      end

      def self.query_keys
        [query_sets.keys, query_hits.keys, query_misses.keys].flatten.uniq.sort
      end

      def self.collector
        GitHub::DataCollector::CacheInstrumenterCollector.get_instance "redis_cache"
      end

      private

      # Internal: Increment/decrement helper
      #
      # delta - positive to increment, negative to decrement
      # returns new counter value, or nil if key doesn't exist (matching memcached behavior)
      #
      # NOTE: Counters are always stored with raw: true (as plain strings).
      # This matches memcached behavior where incr/decr operations only work
      # on raw string values, not serialized objects.
      def change_counter(key, delta)
        if disable_write
          current = _get(key, true)
          return nil if current.nil?
          return current.to_i + delta
        end

        # Use Lua script to atomically check existence and update counter
        # This prevents race conditions between EXISTS and INCRBY
        new_value = execute_counter_script(key, delta)

        # Memcache stores integers in local cache after incr/decr, not strings
        write_to_local_cache(key, new_value) unless new_value.nil?

        new_value
      end

      # Lua script for atomic counter update, with existence check
      # Returns nil if key doesn't exist, otherwise returns new value after increment/decrement
      COUNTER_SCRIPT = <<-LUA
        if redis.call('exists', KEYS[1]) == 0 then
          return nil
        else
          return redis.call('incrby', KEYS[1], ARGV[1])
        end
      LUA

      COUNTER_SCRIPT_SHA = Digest::SHA1.hexdigest(COUNTER_SCRIPT) # rubocop:disable GitHub/InsecureHashAlgorithm

      # Execute the counter increment Lua script with automatic retry on NOSCRIPT error
      #
      # @param key [String] The cache key
      # @param delta [Integer] The amount to increment (positive) or decrement (negative)
      # @return [Integer, nil] The new value after increment, or nil if key doesn't exist
      def execute_counter_script(key, delta)
        retried = false

        begin
          # Try to execute using evalsha on the underlying Redis client
          result = redis.evalsha(COUNTER_SCRIPT_SHA, [key], [delta])

          # Redis returns false for nil in Lua, convert to Ruby nil
          result == false ? nil : result
        rescue ::Redis::CommandError => e
          # If script not found, load it and retry once
          if e.message.include?("NOSCRIPT") && !retried
            raw_redis(redis).script(:load, COUNTER_SCRIPT)
            retried = true
            retry
          else
            raise
          end
        end
      end

      # Get the raw Redis client from a possibly namespaced client
      def raw_redis(client)
        if client.instance_of?(::Redis::Namespace)
          client.redis
        else
          client
        end
      end

      # Instrument Redis operations with metrics and error handling
      #
      # @param operation [String] The operation name (e.g., "set", "get", "add")
      # @param key [String, Array<String>] The cache key(s) for error logging
      # @yield The block to execute
      # @return The result of the block, or appropriate fallback on error
      sig { params(operation: String, key: T.any(String, T::Array[String]), block: T.proc.returns(T.untyped)).returns(T.untyped) }
      def instrument(operation, key, &block)
        start_time = Time.now
        result = nil
        error_occurred = false
        span = nil

        # Start distributed tracing span if enabled
        if GitHub::Cache::RedisClient.distributed_tracing_enabled
          catalog_service = GitHub.context[:catalog_service] || "unknown"
          span = GitHub.tracer.start_span(operation, kind: :client, attributes: {
            "db.system" => "redis",
            GitHub::TaggingHelper::CATALOG_SERVICE_TAG => catalog_service
          })
        end

        begin
          result = block.call

          final_status = case operation
          when "get"
            result.nil? ? "miss" : "hit"
          when "get_multi"
            calculate_get_multi_status(key, result)
          when "add"
            result ? "success" : "exists"
          else
            "success"
          end

          result
        rescue => e
          error_occurred = true
          final_status = "error"
          log_error(operation, key, e)

          # Return appropriate fallback values based on operation type
          case operation
          when "set", "delete", "exist?"
            false
          when "add"
            nil # Match memcached behavior (nil = not added)
          when "get", "read", "fetch"
            nil
          when "increment", "decrement", "incr", "decr"
            0
          when "get_multi", "read_multi"
            {}
          else
            nil
          end
        ensure
          # Calculate latency
          latency = Time.now - start_time

          # Record query stats for GitHub::Cache::Client compatibility (unless error)
          unless error_occurred
            case operation
            when "set", "add"
              GitHub::Cache::RedisClient.query_sets[key] += 1 if GitHub::Cache::RedisClient.collector.enabled?
            when "get"
              if result.nil?
                GitHub::Cache::RedisClient.query_misses[key] += 1 if GitHub::Cache::RedisClient.collector.enabled?

                # Log cache misses with 1% sampling to investigate key patterns
                if logger && rand < 0.01
                  logger.info({
                    "cache.operation" => "miss",
                    "cache.key" => key.to_s,
                    "cache.key_class" => key.class.name,
                    "cache.namespace" => @namespace,
                    "cache.partition" => @current_partition,
                    "controller" => GitHub.context[:controller],
                    "action" => GitHub.context[:action],
                  })
                end
              else
                GitHub::Cache::RedisClient.query_hits[key] += 1 if GitHub::Cache::RedisClient.collector.enabled?
              end
            when "get_multi"
              # Track hits/misses for each key in get_multi
              if result.is_a?(Hash) && GitHub::Cache::RedisClient.collector.enabled?
                keys = key.is_a?(Array) ? key : key.to_s.split(",")
                keys.each do |k|
                  if result[k]
                    GitHub::Cache::RedisClient.query_hits[k] += 1
                  else
                    GitHub::Cache::RedisClient.query_misses[k] += 1

                    # Log cache misses with 1% sampling to investigate key patterns
                    if logger && rand < 0.01
                      logger.info({
                        "cache.operation" => "get_multi_miss",
                        "cache.key" => k.to_s,
                        "cache.key_class" => k.class.name,
                        "cache.namespace" => @namespace,
                        "cache.partition" => @current_partition,
                        "controller" => GitHub.context[:controller],
                        "action" => GitHub.context[:action],
                      })
                    end
                  end
                end
              end
            end
          end

          # Record query events if tracking is enabled
          if GitHub::Cache::RedisClient.track_events
            key_string = key.is_a?(Array) ? key.first.to_s : key.to_s
            # Skip storing stack traces when operation takes less than 1 ms
            minimum_instrumentation_latency = 1 / 1_000
            event = {
              operation: operation,
              key: key_string,
              latency: latency,
              locations: latency >= minimum_instrumentation_latency ? caller_locations(2) : [],
            }
            GitHub::Cache::RedisClient.query_events.push(event)
          end

          # Update aggregate query tracking
          if GitHub::Cache::RedisClient.collector.enabled?
            GitHub::Cache::RedisClient.query_time += latency
            GitHub::Cache::RedisClient.query_count += 1
          end

          tags = ["operation:#{operation}", "partition:#{@current_partition}", "status:#{final_status}", "controller:#{GitHub.context[:controller]}", "action:#{GitHub.context[:action]}", "namespace:#{@namespace}"]

          # Always emit metrics regardless of success or failure
          GitHub.dogstats.timing_since("github.cache.redis_client.operation.duration",
            start_time,
            tags: tags
          )

          GitHub.dogstats.increment("github.cache.redis_client.operation",
            tags: tags
          )

          # Finish distributed tracing span
          span&.finish
        end
      end

      sig { returns(::Redis::Namespace) }
      def build_redis_connection
        config = GitHub.read_redis_config("config/redis_rails_cache.yml").merge({
          # TODO: tune these settings as needed
          # Circuit breaker is provided by redis-client gem (redis passes config through to redis-client)
          circuit_breaker: {
            error_threshold: 5, # trip circuit after 5 errors in 2 seconds
            error_threshold_timeout: 2,
            error_timeout: 5, # wait 5 seconds before trying again
            success_threshold: 3 # stay in closed state after 3 successful requests
          }
        })
        redis_instance = ::Redis.new(config)

        # Emit connection metric
        GitHub.dogstats.increment("github.cache.redis_client.connection.established",
          tags: ["partition:#{@current_partition}", "namespace:#{@namespace}"]
        )

        # Use Redis::Namespace to handle key prefixing automatically
        ::Redis::Namespace.new("#{@namespace}:#{@current_partition}", redis: redis_instance)
      rescue => e
        # Emit connection failure metric
        GitHub.dogstats.increment("github.cache.redis_client.connection.failed",
          tags: ["partition:#{@current_partition}", "namespace:#{@namespace}", "error_class:#{e.class.name}"]
        )
        raise
      end

      sig { returns(T::Boolean) }
      def redis_connected?
        T.unsafe(redis).redis.connected?
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Integer)) }
      def extract_ttl(options)
        return options[:ttl].to_i if options.key?(:ttl)

        options[:expires_in]&.to_i
      end

      sig { params(key: T.untyped, options: T::Hash[Symbol, T.untyped], block: T.proc.returns(T.untyped)).returns(T.untyped) }
      def cache_write_on_miss(key, options, &block)
        value = block.call
        ttl = extract_ttl(options)
        set(key, value, ttl, !!options[:raw])
        value
      end

      # Local cache methods - per-request caching using GH.context
      # This matches GitHub::Cache::Client's Local mixin behavior
      sig { returns(T.nilable(String)) }
      def local_cache_key
        @local_cache_key ||= T.let("redis_client_#{@namespace}_#{@current_partition}_#{object_id}".gsub(/[\/-]/, "_"), T.nilable(String))
      end

      sig { params(key: String).returns(T::Boolean) }
      def in_local_cache?(key)
        !!local&.key?(key)
      end

      sig { params(key: String).returns(T.untyped) }
      def read_from_local_cache(key)
        local&.dig(key)
      end

      sig { params(key: String, value: T.untyped).void }
      def write_to_local_cache(key, value)
        local&.store(key, value)
      end

      sig { params(key: String).void }
      def delete_from_local_cache(key)
        local&.delete(key)
      end

      sig { void }
      def increment_local_hit_count
        local&.store("__local_hit_count__", local_hit_count + 1)
      end

      sig { params(operation: String, key: T.any(String, T::Array[String]), error: Exception).void }
      def log_error(operation, key, error)
        key_string = normalize_key(key)
        if logger
          logger.error({
            :exception => error,
            "db.system" => "github_cache_redis_client",
            "error.class" => error.class.name,
            "cache.key" => key_string,
            "cache.operation" => operation,
            "cache.namespace" => @namespace,
            "cache.partition" => @current_partition,
            "gh.client" => "github_cache_redis_client",
          })
        end

        Failbot.report(error,
          operation: "github_cache_redis_client_#{operation}",
          key: key,
          namespace: @namespace,
          partition: @current_partition,
          client: "GitHub::Cache::RedisClient"
        )
        GitHub.dogstats.increment("github.cache.redis_client.error",
          tags: [
            "operation:#{operation}",
            "partition:#{@current_partition}",
            "namespace:#{@namespace}",
            "error_class:#{error.class.name}",
            "controller": "#{GitHub.context[:controller]}",
            "action": "#{GitHub.context[:action]}",
          ]
        )
      end

      def instrument_nil_set(key, value, ttl, raw)
        GitHub.dogstats.increment("github.cache.redis_client.error.nil-set",
          tags: [
            "partition:#{@current_partition}",
            "namespace:#{@namespace}",
            "controller": "#{GitHub.context[:controller]}",
            "action": "#{GitHub.context[:action]}",
          ]
        )

        if logger
          logger.error({
            "db.system" => "github_cache_redis_client",
            "cache.key" => key,
            "cache.operation" => "set",
            "cache.namespace" => @namespace,
            "cache.partition" => @current_partition,
            "gh.client" => "github_cache_redis_client",
            "error.message" => "Attempted to set nil value in cache",
          })
        end
      end

      # Zip/unzip methods (from GitHub::Cache::Zip)
      sig { params(key: String, value: T.untyped, raw: T::Boolean).returns([T.untyped, T::Boolean, T::Boolean]) }
      def encode_value(key, value, raw)
        if !raw
          value = GitHub::Cache::Codec.pack(value)

          if value.bytesize > MAX_ATTEMPT_CACHE_SIZE
            return [nil, true, false]
          end

          if value.bytesize > MAX_UNZIPPED_SIZE
            begin
              value = GitHub::Cache::Codec.pack([ZIP_HEADER, Zlib::Deflate.deflate(value)])
            rescue Zlib::DataError => e
              Failbot.report!(e, app: "github-zlib-cache")
              delete(key)
              return [nil, true, false]
            end
          end
        end

        [value, true, true]
      end

      sig { params(key: String, value: T.untyped, raw: T::Boolean).returns(T.untyped) }
      def decode_value(key, value, raw = false)
        return value if value.nil?

        # Handle unpacking first if not raw
        unpacked_value = if raw
          value
        else
          GitHub::Cache::Codec.unpack(value)
        end

        # Then handle decompression if needed
        return unpacked_value unless unpacked_value.is_a?(Array) && unpacked_value[0] == ZIP_HEADER
        begin
          GitHub::Cache::Codec.unpack(Zlib::Inflate.inflate(unpacked_value[1]))
        rescue Zlib::BufError => e
          Failbot.report!(e, app: "github-zlib-cache")
          delete(key)
          nil
        rescue => boom
          raise unless GitHub::Cache.unmarshal_error?(boom)
          delete(key)
          nil
        end
      end

      # Normalizes cache keys to strings, handling arrays from Rails cache helpers
      # Rails' ActionView::Helpers::CacheHelper can pass arrays as cache keys
      # We normalize them by joining with "/" to match ActiveSupport::Cache.expand_cache_key behavior
      sig { params(key: T.untyped).returns(String) }
      def normalize_key(key)
        return key if key.is_a?(String)

        # Use .to_param like Rails does (converts to "/" delimited string)
        # This matches ActiveSupport::Cache.expand_cache_key behavior
        # Example: ["v2:top_languages", true, "org/123"] => "v2:top_languages/true/org/123"
        return key.to_param if key.respond_to?(:to_param)

        # For other types, convert to string directly
        key.to_s
      end

      sig { params(keys: T.any(String, T::Array[String]), result: T::Hash[String, T.untyped]).returns(String) }
      def calculate_get_multi_status(keys, result)
        # Handle both array and comma-separated string keys
        requested_keys = if keys.is_a?(Array)
          keys
        else
          (keys.empty? ? [] : keys.split(","))
        end
        found_keys = result.keys

        return "miss" if found_keys.empty?
        return "hit" if found_keys.size == requested_keys.size
        "partial_hit"
      end

      sig { params(value: T.untyped).returns(T::Boolean) }
      def attempt_cache?(value)
        !value.respond_to?(:bytesize) || value.bytesize < MAX_ATTEMPT_CACHE_SIZE
      end
    end
  end
end
