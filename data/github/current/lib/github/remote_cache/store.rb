# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    # Cache store with advanced features
    #
    # ## Key Features
    #
    # - **Go-compatible serialization**: Uses MessagePack format for all values
    # - **Zstd compression**: Automatic compression for large values with binary header format
    # - **Local in-memory memoization**: Context-aware caching that reduces Redis round trips
    # - **Memory-only mode**: Supports local caching only (useful for tests)
    #
    # ## Format
    #
    # All values are serialized with MessagePack and use a binary format with version indicator:
    # 1. First byte: version (0x01 for current version)
    # 2. Second byte: compression flag (0x01 for compressed, 0x00 for uncompressed)
    # 3. Remaining bytes: MessagePack data (compressed with Zstd if flag is set)
    #
    # This format allows Go applications to:
    # - Check version compatibility by reading the first byte
    # - Handle compression by checking the second byte
    # - Parse MessagePack data which is well-supported in Go
    #
    # The store should not be used directly, but instead via `GitHub::RemoteCache::Client` and,
    # more commonly, `GitHub::RemoteCache::Preset`.
    class Store
      # Version 1 format: [version_byte][data...]
      CACHE_FORMAT_VERSION = T.let("\x01".freeze, String)

      # Maximum size for a value stored in the remote cache (bytes).
      MAX_VALUE_BYTES = T.let(1.megabyte, Integer)

      # Internal placeholder object for missing values in local cache
      MISSING = T.let(Object.new.freeze, Object)

      class CacheValueTooLargeForWritingError < StandardError; end
      class CacheValueTooSmallForReadingError < StandardError; end
      class UnexpectedRedisSetResultError < StandardError; end
      class CacheFormatVersionMismatchWhenReadingError < StandardError; end
      class NilCacheValueWhenDecompressingError < StandardError; end
      class NilCacheValueForMultiWriteError < StandardError; end

      sig { returns(String) }
      attr_reader :namespace

      sig { returns(GitHub::RemoteCache::Compressor) }
      attr_reader :compressor

      sig { returns(T.any(::Redis, GitHub::MemoryRedis)) }
      attr_reader :redis

      sig do
        params(
          namespace: String,
          redis: T.any(::Redis, GitHub::MemoryRedis),
          using_test_cluster: T::Boolean,
          compressor: T.nilable(GitHub::RemoteCache::Compressor)
        ).void
      end
      def initialize(namespace:, redis:, using_test_cluster: true, compressor: nil)
        @namespace = T.let(namespace, String)
        @key_prefix = T.let("#{namespace}:".freeze, String)
        @compressor = T.let(
          compressor || GitHub::RemoteCache::MessagePackZstdCompressor,
          GitHub::RemoteCache::Compressor
        )
        @redis = T.let(redis, T.any(::Redis, GitHub::MemoryRedis))
        @using_test_cluster = T.let(using_test_cluster, T::Boolean)

        setup_connection
      end

      sig { returns(String) }
      def redis_cluster
        case @redis
        when nil
          "unknown"
        when ::Redis
          @using_test_cluster ? "dx-test" : "global-cache"
        when GitHub::MemoryRedis
          "memory"
        end
      end

      sig { returns(String) }
      def redis_url
        case @redis
        when nil
          "unknown"
        when ::Redis
          @redis._client&.server_url || "unknown"
        when GitHub::MemoryRedis
          "memory"
        end
      end

      sig do
        type_parameters(:T)
        .params(
          key: String,
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)]
        ).returns([T.nilable(T.type_parameter(:T)), Symbol, T.nilable(Exception)])
      end
      def read(key, serializer:)
        full_key = namespaced_key(key)

        if in_local_cache_present?(full_key)
          return [read_from_local_cache(full_key, serializer), :local, nil]
        end

        raw_value = @redis.get(full_key)

        if raw_value.nil?
          # Cache the miss to avoid repeated Redis lookups
          write_to_local_cache(full_key, nil)
          return [nil, :redis, nil]
        end

        # Ensure the stored value has the version byte and data, then strip version before decompression
        return [nil, :error, CacheValueTooSmallForReadingError.new] if raw_value.bytesize < 2

        version_byte = raw_value.getbyte(0)
        return [nil, :error, CacheFormatVersionMismatchWhenReadingError.new] unless version_byte == CACHE_FORMAT_VERSION.getbyte(0)

        decompressed_value = compressor.decompress(raw_value.byteslice(1..-1))
        return [nil, :error, NilCacheValueWhenDecompressingError.new] unless decompressed_value

        decompressed_value = T.unsafe(decompressed_value).freeze if should_be_frozen?(decompressed_value)
        write_to_local_cache(full_key, decompressed_value)

        value = serializer.deserialize(decompressed_value)
        [value, :redis, nil]
      rescue => e
        [nil, :error, e]
      end

      sig do
        type_parameters(:T)
        .params(
          keys: T::Array[String],
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)]
        ).returns(T::Hash[String, [T.nilable(T.type_parameter(:T)), Symbol, T.nilable(Exception)]])
      end
      def read_multi(keys, serializer:)
        # Create a results hash to store the outcome for each key in "keys" argument
        results = {}

        full_keys = keys.each_with_object({}) { |key, acc| acc[key] = namespaced_key(key) }

        # Attempt to get value for each key from local cache
        keys.each do |key|
          begin
            full_key = full_keys[key]
            if in_local_cache_present?(full_key)
              results[key] = [read_from_local_cache(full_key, serializer), :local, nil]
            end
          rescue => local_cache_read_exception
            # Errors should not happen here, so if they do, we want pass them along as the result for
            # this key instead of ignoring them and proceeding to fetch from Redis
            results[key] = [nil, :error, local_cache_read_exception]
          end
        end

        # If all keys were found in local cache, return early
        return results if keys.size == results.size

        # Determine which keys haven't been found in local cache and still need to be fetched from Redis
        remaining_keys = keys - results.keys

        # Fetch remaining keys from Redis in a single MGET operation
        # Sorbet doesn't like using splat operators, so we have to use T.unsafe: https://srb.help/7019
        remaining_full_keys = T.unsafe(full_keys).values_at(*remaining_keys)

        raw_values = begin
          # Sorbet doesn't like using splat operators, so we have to use T.unsafe: https://srb.help/7019
          T.unsafe(@redis).mget(*remaining_full_keys)
        rescue => mget_exception
          # If MGET fails, return error for all remaining keys and exit early
          error_result = [nil, :error, mget_exception].freeze
          remaining_keys.each do |key|
            results[key] = error_result
          end
          return results
        end

        # Process each returned value from Redis and add to results
        remaining_keys.each.with_index do |key, index|
          begin
            full_key = full_keys[key]
            if (raw_value = raw_values[index]).nil?
              # Cache the miss to avoid repeated Redis lookups
              write_to_local_cache(full_key, nil)
              results[key] = [nil, :redis, nil]
              next
            end

            # Ensure the stored value has the version byte and data, then strip version before decompression
            if raw_value.bytesize < 2
              results[key] = [nil, :error, CacheValueTooSmallForReadingError.new]
              next
            end

            version_byte = raw_value.getbyte(0)
            if version_byte != CACHE_FORMAT_VERSION.getbyte(0)
              results[key] = [nil, :error, CacheFormatVersionMismatchWhenReadingError.new]
              next
            end

            decompressed_value = compressor.decompress(raw_value.byteslice(1..-1))
            if !decompressed_value
              results[key] = [nil, :error, NilCacheValueWhenDecompressingError.new]
              next
            end

            decompressed_value = T.unsafe(decompressed_value).freeze if should_be_frozen?(decompressed_value)
            value = serializer.deserialize(decompressed_value)

            begin
              write_to_local_cache(full_key, decompressed_value)
              results[key] = [value, :redis, nil]
            rescue => e
              results[key] = [value, :redis, e]
            end
          rescue => e
            results[key] = [nil, :error, e]
          end
        end

        results
      rescue => read_multi_exception
        # In case of exceptions not already caught above, return error for all keys
        error_result = [nil, :error, read_multi_exception].freeze
        keys.each_with_object({}) do |key, acc|
          acc[key] = error_result
        end
      end

      sig do
        type_parameters(:T)
        .params(
          keys_values: T::Hash[String, T.type_parameter(:T)],
          expires_in: Integer,
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)]
        ).returns(T::Hash[String, [T::Boolean, T.nilable(Exception)]])
      end
      def write_multi(keys_values, expires_in:, serializer:)
        results = {}
        keys_values_to_write = {}
        full_keys = keys_values.keys.each_with_object({}) { |key, acc| acc[key] = namespaced_key(key) }

        # First, validate and prepare all keys and values for writing to local cache and Redis
        # If any key/value pair fails, it will be recorded in results and not written
        keys_values.each do |key, value|
          begin
            full_key = full_keys[key]

            # Why are we using a case here? Ideally, we'd use `value.nil?` but Sorbet
            # doesn't like that since "value" is a generic https://srb.help/7038
            case value
            when nil
              results[key] = [false, NilCacheValueForMultiWriteError.new]
              next
            end

            # Serialize for remote cache
            serialized_value = serializer.serialize(value)

            compressed_payload = compressor.compress(serialized_value)

            # Prepend version byte
            stored_value = CACHE_FORMAT_VERSION + compressed_payload.to_s

            # Check size limits
            if stored_value.bytesize > MAX_VALUE_BYTES
              GitHub.logger.warn("Cache write size exceeded", { "gh.cache.namespace": namespace, "gh.cache.key": key })
              results[key] = [false, CacheValueTooLargeForWritingError.new]
            else
              # Write to local cache
              write_to_local_cache(full_key, serialized_value)
              keys_values_to_write[key] = stored_value
            end
          rescue => e
            results[key] = [false, e]
          end
        end

        # If there are no valid key/value pairs to write, return early
        return results if keys_values_to_write.empty?

        # Save the list of keys into an array so that we have a stable order for processing pipeline results
        keys_for_writing = keys_values_to_write.keys
        pipeline_results = begin
          @redis.pipelined do |pipeline|
            keys_for_writing.each do |key|
              pipeline.set(full_keys[key], keys_values_to_write[key], ex: expires_in, keepttl: false)
            end
          end
        rescue => pipeline_exception
          # If pipeline fails, return error for all remaining keys and exit early
          error_result = [false, pipeline_exception].freeze
          keys_for_writing.each do |key|
            results[key] = error_result
          end
          return results
        end

        # Process results from Redis pipeline
        keys_for_writing.each_with_index do |key, index|
          pipeline_result = pipeline_results[index]
          results[key] = (pipeline_result != "OK") ? [false, UnexpectedRedisSetResultError.new] : [true, nil]
        end

        results
      rescue => write_multi_exception
        # In case of exceptions not already caught above, return error for all keys
        error_result = [false, write_multi_exception].freeze
        keys_values.keys.each_with_object({}) do |key, acc|
          acc[key] = error_result
        end
      end

      sig do
        type_parameters(:T)
        .params(
          key: String,
          value: T.type_parameter(:T),
          expires_in: Integer,
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)]
        ).returns([T::Boolean, T.nilable(Exception)])
      end
      def write(key, value, expires_in:, serializer:)
        full_key = namespaced_key(key)

        # Serialize for remote cache
        serialized_value = serializer.serialize(value)
        compressed_payload = compressor.compress(serialized_value)

        # Prepend version byte
        stored_value = CACHE_FORMAT_VERSION + compressed_payload.to_s

        # Check size limits
        if stored_value.bytesize > MAX_VALUE_BYTES
          GitHub.logger.warn("Cache write size exceeded", { "gh.cache.namespace": namespace, "gh.cache.key": key })
          return [false, CacheValueTooLargeForWritingError.new]
        end

        write_to_local_cache(full_key, serialized_value)
        result = @redis.set(full_key, stored_value, ex: expires_in, keepttl: false)
        return [false, UnexpectedRedisSetResultError.new] if result != "OK"

        [true, nil]
      rescue => e
        [false, e]
      end

      sig { params(key: String).returns([T::Boolean, T.nilable(Exception)]) }
      def delete(key)
        full_key = namespaced_key(key)

        delete_from_local_cache(full_key)

        [@redis.unlink(full_key) > 0, nil]
      rescue => e
        [false, e]
      end

      private

      # Ensure the Redis connection is healthy by pinging it.
      sig { void }
      def setup_connection
        should_ping = T.let(false, T::Boolean)
        ping_error = T.let(nil, T.nilable(Exception))
        ping_timer = T.let(nil, T.nilable(::Timer))

        should_ping = FeatureFlag.vexi.enabled?(:remote_cache_redis_ping, default: false) ||
          (FeatureFlag.vexi.enabled?(:remote_cache_redis_ping_connected, default: false) && !redis.connected?)

        return if !should_ping

        ping_timer = ::Timer.start
        begin
          redis.ping
        rescue => e
          ping_error = e
        end
        ping_timer.stop

        tags = ["namespace:#{namespace}"]
        tags << "error:#{ping_error.class.name}" if ping_error
        tags << "error_cause:#{ping_error.cause.class.name}" if ping_error&.cause

        GitHub.dogstats.distribution("github.remote_cache.setup_ping", ping_timer.elapsed_ms(5), tags: tags)
      end

      sig { params(key: String).returns(String) }
      def namespaced_key(key)
        @key_prefix + key
      end

      sig { returns(String) }
      def local_cache_key
        @local_cache_key ||= T.let("#{namespace}_local_cache_#{object_id}".gsub(/[\/-]/, "_"), T.nilable(String))
      end

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def local_cache
        # Using `GH.context` here to take advantage of its established lifecycle in requests,
        # jobs, etc where it gets cleaned up automatically.
        # NullContext does not use local cache
        return unless registry = GH.context.remote_cache_registry

        registry[local_cache_key] ||= Concurrent::Hash.new
      rescue
        nil
      end

      sig { params(key: String).returns(T::Boolean) }
      def in_local_cache_present?(key)
        !!local_cache&.key?(key)
      end

      sig do
        type_parameters(:T)
        .params(
          key: String,
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)]
        ).returns(T.nilable(T.type_parameter(:T)))
      end
      def read_from_local_cache(key, serializer)
        cache = local_cache
        value = cache&.dig(key)

        return nil if value.equal?(MISSING)

        serializer.deserialize(duplicate_value(value))
      end

      sig { params(value: T.untyped).returns(T::Boolean) }
      def should_be_frozen?(value)
        T.unsafe(value).is_a?(String)
      end

      sig { params(key: String, value: T.untyped).void }
      def write_to_local_cache(key, value)
        cache = local_cache
        return unless cache

        cache[key] = value.nil? ? MISSING : duplicate_value(value)
      end

      sig { params(key: String).void }
      def delete_from_local_cache(key)
        cache = local_cache
        cache&.delete(key)
      rescue
        # Ignore errors in local caching
      end

      sig { params(value: T.untyped).returns(T.untyped) }
      def duplicate_value(value)
        if should_be_frozen?(value)
          value.freeze
        elsif value&.respond_to?(:deep_dup)
          value.deep_dup
        elsif value&.respond_to?(:dup)
          value.dup
        else
          value
        end
      end
    end
  end
end
