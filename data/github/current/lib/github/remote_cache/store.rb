# typed: strict
# frozen_string_literal: true

require "github/memory_redis"

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

      # Maximum size for a key stored in the remote cache (bytes).
      MAX_KEY_BYTES = T.let(2.kilobytes, Integer)

      # Maximum read timeout for read_multi Redis commands (seconds).
      MAX_READ_MULTI_TIMEOUT_SECONDS = T.let(GitHub.environment.fetch("GLOBAL_CACHE_READ_MULTI_TIMEOUT", "0.06").to_f, Float)

      # Maximum write timeout for pipelined write operations (seconds).
      MAX_WRITE_MULTI_TIMEOUT_SECONDS = T.let(GitHub.environment.fetch("GLOBAL_CACHE_WRITE_MULTI_TIMEOUT", "0.06").to_f, Float)

      # Maximum number of keys/operations per batch for multi-operations
      MULTI_OPERATION_BATCH_SIZE = T.let(1_000, Integer)

      # Maximum total keys/operations allowed in a single multi-operation call
      # Operations exceeding this limit will be truncated and a metric emitted
      MULTI_OPERATION_MAX_KEYS = T.let(10_000, Integer)

      # Internal placeholder object for missing values in local cache
      MISSING = T.let(Object.new.freeze, Object)

      OperationType = T.type_alias { Symbol }

      WriteOperation = T.type_alias do
        {
          type: OperationType,
          key: String,
          full_key: String,
          value: T.nilable(String),
          expires_in: T.nilable(Integer)
        }
      end

      WriteQueueState = T.type_alias do
        { writes: T::Array[WriteOperation], registered: T::Boolean }
      end

      WriteStrategy = T.type_alias { Symbol }

      class CacheKeyTooLargeError < StandardError; end
      class CacheValueTooLargeForWritingError < StandardError; end
      class CacheValueTooSmallForReadingError < StandardError; end
      class CacheFormatVersionMismatchWhenReadingError < StandardError; end
      class NilCacheValueWhenDecompressingError < StandardError; end
      class NilCacheValueForMultiWriteError < StandardError; end
      class UnexpectedRedisSetResultError < StandardError; end
      class UnexpectedRedisUnlinkResultError < StandardError; end

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
          compressor: T.nilable(GitHub::RemoteCache::Compressor)
        ).void
      end
      def initialize(namespace:, redis:, compressor: nil)
        @namespace = T.let(namespace, String)
        @key_prefix = T.let("#{namespace}:".freeze, String)
        @base_metric_tags = T.let(nil, T.nilable(T::Array[String]))
        @metric_tags = T.let(nil, T.nilable(T::Array[String]))
        @compressor = T.let(
          compressor || GitHub::RemoteCache::MessagePackZstdCompressor,
          GitHub::RemoteCache::Compressor
        )
        @redis = T.let(redis, T.any(::Redis, GitHub::MemoryRedis))
        @defer_writes = T.let(nil, T.nilable(T::Boolean))

        setup_connection
      end

      sig { returns(String) }
      def redis_cluster
        case @redis
        when nil
          "unknown"
        when ::Redis
          "global-cache"
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

      sig { returns(T::Array[String]) }
      def base_metric_tags
        @base_metric_tags ||= T.let([
          "namespace:#{namespace}",
          "redis_url:#{redis_url}",
          "redis_cluster:#{redis_cluster}"
        ], T::Array[String]).freeze
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

        return [read_from_local_cache(full_key, serializer), :local, nil] if in_local_cache_present?(full_key)

        raw_value = @redis.get(full_key)

        if raw_value.nil?
          # Cache the miss to avoid repeated Redis lookups
          error = write_to_local_cache(full_key, nil)
          return [nil, :error, error] if error

          return [nil, :redis, nil]
        end

        serialized_value, value, error = deserialize_and_decompress_raw_value(raw_value, serializer: serializer)
        return [nil, :error, error] if error

        error = write_to_local_cache(full_key, serialized_value)
        return [value, :error, error] if error

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
        # Truncate keys if they exceed the maximum limit
        keys = truncate_array(keys, :read)

        # Create a results hash to store the outcome for each key in "keys" argument
        results = T.let(
          Hash.new(capacity: keys.size),
          T::Hash[String, [T.nilable(T.type_parameter(:T)), Symbol, T.nilable(Exception)]]
        )
        remaining_keys = T.let([], T::Array[String])
        remaining_full_keys = T.let([], T::Array[String])

        # Attempt to get value for each key from local cache
        keys.each do |key|
          full_key = namespaced_key(key)

          begin
            if in_local_cache_present?(full_key)
              results[key] = [read_from_local_cache(full_key, serializer), :local, nil]
            else
              remaining_keys << key
              remaining_full_keys << full_key
            end
          rescue => local_cache_read_exception
            # If local cache read fails, record the error and skip Redis fetch for this key
            results[key] = [nil, :error, local_cache_read_exception]
          end
        end

        # If all keys were found in local cache, return early
        return results if remaining_keys.empty?

        raw_values = T.let(nil, T.nilable(T::Array[T.nilable(String)]))
        raw_values = begin
          previous_read_timeout = @redis._client.read_timeout
          @redis._client.read_timeout = MAX_READ_MULTI_TIMEOUT_SECONDS

          if remaining_full_keys.size <= MULTI_OPERATION_BATCH_SIZE
            # Sorbet doesn't like using splat operators, so we have to use T.unsafe: https://srb.help/7019
            T.let(T.unsafe(@redis).mget(*remaining_full_keys), T::Array[T.nilable(String)])
          else
            raw_values_batched = T.let([], T::Array[T.nilable(String)])
            remaining_full_keys.each_slice(MULTI_OPERATION_BATCH_SIZE) do |batch_keys|
              batch_values = T.let(T.unsafe(@redis).mget(*batch_keys), T::Array[T.nilable(String)])
              raw_values_batched.concat(batch_values)
            end
            raw_values_batched
          end
        rescue => mget_exception
          # If MGET fails, return error for all remaining keys and exit early
          error_result = [nil, :error, mget_exception].freeze
          remaining_keys.each do |key|
            results[key] = error_result
          end
          return results
        ensure
          @redis._client.read_timeout = previous_read_timeout
        end

        # Process each returned value from Redis and add to results
        remaining_keys.each_with_index do |key, index|
          full_key = T.must(remaining_full_keys[index])
          begin
            raw_value = raw_values[index]

            if raw_value.nil?
              # Cache the miss to avoid repeated Redis lookups
              error = write_to_local_cache(full_key, nil)
              results[key] = if error
                [nil, :error, error]
              else
                [nil, :redis, nil]
              end

              next
            end

            serialized_value, value, error = deserialize_and_decompress_raw_value(raw_value, serializer: serializer)

            if error
              results[key] = [nil, :error, error]
              next
            end

            error = write_to_local_cache(full_key, serialized_value)

            results[key] = if error
              [value, :error, error]
            else
              [value, :redis, nil]
            end
          rescue => e
            results[key] = [nil, :error, e]
          end
        end

        results
      rescue => read_multi_exception
        # In case of exceptions not already caught above, return error for all keys
        error_result = [nil, :error, read_multi_exception].freeze
        keys.each_with_object(Hash.new(capacity: keys.size)) do |key, acc|
          acc[key] = error_result
        end
      end

      sig do
        type_parameters(:T)
        .params(
          keys_values: T::Hash[String, T.type_parameter(:T)],
          expires_in: T::Hash[String, Integer],
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)]
        ).returns(T::Hash[String, [T::Boolean, WriteStrategy, T.nilable(Exception)]])
      end
      def write_multi(keys_values, expires_in:, serializer:)
        # Truncate keys_values if they exceed the maximum limit
        keys_values = truncate_hash(keys_values, :write)

        results = T.let(Hash.new(capacity: keys_values.size), T::Hash[String, [T::Boolean, WriteStrategy, T.nilable(Exception)]])
        write_operations = T.let([], T::Array[WriteOperation])

        # First, validate and prepare all keys and values for writing to local cache and Redis
        # If any key/value pair fails, it will be recorded in results and not written
        keys_values.each do |key, value|
          full_key = namespaced_key(key)

          begin
            if error = validate_key_size(key)
              results[key] = [false, :inline, error]
              next
            end

            # Why are we using a case here? Ideally, we'd use `value.nil?` but Sorbet
            # doesn't like that since "value" is a generic https://srb.help/7038
            case value
            when nil
              results[key] = [false, :inline, NilCacheValueForMultiWriteError.new]
              next
            end

            serialized_value, compressed_value = serialize_and_compress_value(value, serializer: serializer)

            if error = validate_value_size(compressed_value, key)
              results[key] = [false, :inline, error]
              next
            end

            local_cache_error = write_to_local_cache(full_key, serialized_value)
            results[key] = [false, :error, local_cache_error] if local_cache_error
          rescue => e
            results[key] = [false, :inline, e]
            next
          end

          operation = T.let(
            {
              type: :set,
              key: key,
              full_key: full_key,
              value: compressed_value,
              expires_in: expires_in.fetch(key)
            },
            WriteOperation
          )

          write_operations << operation
        end

        # If there are no valid key/value pairs to write, return early
        return results if write_operations.empty?

        if defer_writes?
          write_operations.each do |operation|
            success, error = enqueue_operation(operation)

            results[operation[:key]] ||= [success, :deferred, error]
          end

          return results
        end

        begin
          pipeline_results = if write_operations.size <= MULTI_OPERATION_BATCH_SIZE
            with_write_multi_timeout do
              @redis.pipelined do |pipeline|
                write_operations.each do |operation|
                  pipeline.set(operation[:full_key], operation[:value], ex: operation[:expires_in], keepttl: false)
                end
              end
            end
          else
            all_pipeline_results = T.let([], T::Array[T.untyped])
            with_write_multi_timeout do
              write_operations.each_slice(MULTI_OPERATION_BATCH_SIZE) do |batch_operations|
                batch_results = @redis.pipelined do |pipeline|
                  batch_operations.each do |operation|
                    pipeline.set(operation[:full_key], operation[:value], ex: operation[:expires_in], keepttl: false)
                  end
                end
                all_pipeline_results.concat(batch_results)
              end
            end
            all_pipeline_results
          end

          write_operations.each_with_index do |operation, index|
            results[operation[:key]] ||= if pipeline_results[index] != "OK"
              [false, :inline, UnexpectedRedisSetResultError.new]
            else
              [true, :inline, nil]
            end
          end
        rescue => pipeline_exception
          error_result = [false, :inline, pipeline_exception].freeze
          write_operations.each do |operation|
            results[operation[:key]] = error_result
          end
          return results
        end

        results
      rescue => write_multi_exception
        # In case of exceptions not already caught above, return error for all keys
        error_result = [false, :inline, write_multi_exception].freeze
        keys_values.keys.each_with_object(Hash.new(capacity: keys_values.size)) do |key, acc|
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
        ).returns([T::Boolean, WriteStrategy, T.nilable(Exception)])
      end
      def write(key, value, expires_in:, serializer:)
        full_key = namespaced_key(key)
        write_strategy = T.let(:inline, WriteStrategy)

        if error = validate_key_size(key)
          return [false, write_strategy, error]
        end

        serialized_value, compressed_value = serialize_and_compress_value(value, serializer: serializer)

        if error = validate_value_size(compressed_value, key)
          return [false, write_strategy, error]
        end

        error = write_to_local_cache(full_key, serialized_value)
        error_result = [false, :error, error] if error

        operation = T.let(
          {
            type: :set,
            key: key,
            full_key: full_key,
            value: compressed_value,
            expires_in: expires_in
          },
          WriteOperation
        )

        if defer_writes?
          write_strategy = :deferred
          success, error = enqueue_operation(operation)
        else
          success, error = perform_operation(operation)
        end

        # If local cache write failed, return that result instead of the Redis write result
        return error_result if error_result

        [success, write_strategy, error]
      rescue => e
        write_strategy ||= :inline
        [false, write_strategy, e]
      end

      sig { params(key: String).returns([T::Boolean, WriteStrategy, T.nilable(Exception)]) }
      def delete(key)
        full_key = namespaced_key(key)
        write_strategy = T.let(:inline, WriteStrategy)

        if error = validate_key_size(key)
          return [false, write_strategy, error]
        end

        error = delete_from_local_cache(full_key)
        error_result = [false, :error, error] if error

        operation = T.let(
          {
            type: :delete,
            key: key,
            full_key: full_key,
            value: nil,
            expires_in: nil
          },
          WriteOperation
        )

        if defer_writes?
          write_strategy = :deferred
          success, error = enqueue_operation(operation)
        else
          success, error = perform_operation(operation)
        end

        # If local cache delete failed, return that result instead of the Redis delete result
        return error_result if error_result

        [success, write_strategy, error]
      rescue => e
        write_strategy ||= :inline
        [false, write_strategy, e]
      end

      sig do
        params(keys: T::Array[String]).returns(T::Hash[String, [T::Boolean, WriteStrategy, T.nilable(Exception)]])
      end
      def delete_multi(keys)
        # Truncate keys if they exceed the maximum limit
        keys = truncate_array(keys, :delete)

        results = T.let(
          Hash.new(capacity: keys.size),
          T::Hash[String, [T::Boolean, WriteStrategy, T.nilable(Exception)]]
        )
        return results if keys.empty?

        write_operations = T.let([], T::Array[WriteOperation])

        keys.each do |key|
          if error = validate_key_size(key)
            results[key] = [false, :inline, error]
            next
          end

          full_key = namespaced_key(key)

          local_cache_error = delete_from_local_cache(full_key)
          results[key] = [false, :error, local_cache_error] if local_cache_error

          operation = T.let(
            {
              type: :delete,
              key: key,
              full_key: full_key,
              value: nil,
              expires_in: nil
            },
            WriteOperation
          )

          write_operations << operation
        end

        return results if write_operations.empty?

        begin
          if defer_writes?
            write_operations.each do |operation|
              success, error = enqueue_operation(operation)
              results[operation[:key]] ||= [success, :deferred, error]
            end
          else
            with_write_multi_timeout do
              batches = write_operations.each_slice(MULTI_OPERATION_BATCH_SIZE).to_a

              pipeline_results = @redis.pipelined do |pipeline|
                batches.each do |batch|
                  batch_keys = batch.map { |op| op[:full_key] }
                  # Sorbet doesn't like using splat operators, so we have to use T.unsafe: https://srb.help/7019
                  T.unsafe(pipeline).unlink(*batch_keys)
                end
              end

              # Process pipeline results and map them back to operations
              batches.each_with_index do |batch, batch_index|
                unlink_result = pipeline_results[batch_index]

                if !unlink_result.is_a?(Integer)
                  batch.each do |operation|
                    key = operation[:key]
                    next if results.key?(key)
                    results[key] = [false, :inline, UnexpectedRedisUnlinkResultError.new]
                  end
                else
                  batch.each do |operation|
                    key = operation[:key]
                    next if results.key?(key)
                    results[key] = [true, :inline, nil]
                  end
                end
              end
            end
          end
        rescue => operation_exception
          error_result = [false, :inline, operation_exception].freeze
          write_operations.each do |operation|
            results[operation[:key]] ||= error_result
          end
        end

        results
      end

      private

      sig { params(operation_type: Symbol).void }
      def emit_truncation_metric(operation_type)
        GitHub.dogstats.increment(
          "github.remote_cache.multi_operation_truncated",
          tags: base_metric_tags + ["operation:#{operation_type}"]
        )
      end

      sig do
        type_parameters(:T)
          .params(array: T::Array[T.type_parameter(:T)], operation_type: Symbol)
          .returns(T::Array[T.type_parameter(:T)])
      end
      def truncate_array(array, operation_type)
        return array if array.size <= MULTI_OPERATION_MAX_KEYS
        emit_truncation_metric(operation_type)
        array.first(MULTI_OPERATION_MAX_KEYS)
      end

      sig do
        type_parameters(:K, :V)
          .params(hash: T::Hash[T.type_parameter(:K), T.type_parameter(:V)], operation_type: Symbol)
          .returns(T::Hash[T.type_parameter(:K), T.type_parameter(:V)])
      end
      def truncate_hash(hash, operation_type)
        return hash if hash.size <= MULTI_OPERATION_MAX_KEYS
        emit_truncation_metric(operation_type)
        hash.take(MULTI_OPERATION_MAX_KEYS).to_h
      end

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

        tags = base_metric_tags.dup
        tags << "error:#{ping_error.class.name}" if ping_error
        tags << "error_cause:#{ping_error.cause.class.name}" if ping_error&.cause

        GitHub.dogstats.distribution("github.remote_cache.setup_ping", ping_timer.elapsed_ms(5), tags: tags)
      end

      sig { params(key: String).returns(String) }
      def namespaced_key(key)
        @key_prefix + key
      end

      sig { params(key: String).returns(T.nilable(CacheKeyTooLargeError)) }
      def validate_key_size(key)
        return nil if key.bytesize < MAX_KEY_BYTES

        GitHub.logger.warn("Cache key size exceeded", { "gh.cache.namespace": namespace, "gh.cache.key": key.byteslice(0, MAX_KEY_BYTES) })
        CacheKeyTooLargeError.new
      end

      sig { params(compressed_value: String, key: String).returns(T.nilable(CacheValueTooLargeForWritingError)) }
      def validate_value_size(compressed_value, key)
        return nil if compressed_value.bytesize < MAX_VALUE_BYTES

        GitHub.logger.warn("Cache write size exceeded", { "gh.cache.namespace": namespace, "gh.cache.key": key })
        CacheValueTooLargeForWritingError.new
      end

      sig { params(operation: WriteOperation).returns([T::Boolean, T.nilable(Exception)]) }
      def perform_operation(operation)
        case operation[:type]
        when :set
          result = @redis.set(operation[:full_key], operation[:value], ex: operation[:expires_in], keepttl: false)
          return [false, UnexpectedRedisSetResultError.new] if result != "OK"

          [true, nil]
        when :delete
          result = @redis.unlink(operation[:full_key])
          return [false, UnexpectedRedisUnlinkResultError.new] unless result.is_a?(Integer)

          [result > 0, nil]
        else
          [false, StandardError.new("Unknown operation type: #{operation[:type]}")]
        end
      rescue => e
        [false, e]
      end

      sig do
        type_parameters(:T)
        .params(
          block: T.proc.returns(T.type_parameter(:T))
        ).returns(T.type_parameter(:T))
      end
      def with_write_multi_timeout(&block)
        previous_read_timeout = @redis._client.read_timeout
        @redis._client.read_timeout = MAX_WRITE_MULTI_TIMEOUT_SECONDS
        block.call
      ensure
        @redis._client.read_timeout = previous_read_timeout
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

      sig { params(key: String, value: T.untyped).returns(T.nilable(Exception)) }
      def write_to_local_cache(key, value)
        cache = local_cache
        return nil unless cache

        cache[key] = value.nil? ? MISSING : duplicate_value(value)
        nil
      rescue => error
        error
      end

      sig { params(key: String).returns(T.nilable(Exception)) }
      def delete_from_local_cache(key)
        cache = local_cache
        cache&.delete(key)

        nil
      rescue => error
        error
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

      sig do
        type_parameters(:T)
        .params(
          value: T.type_parameter(:T),
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)]
        ).returns([T.untyped, String])
      end
      def serialize_and_compress_value(value, serializer:)
        serialized_value = serializer.serialize(value)
        compressed_value = CACHE_FORMAT_VERSION + compressor.compress(serialized_value).to_s

        [serialized_value, compressed_value]
      end

      sig do
        type_parameters(:T)
        .params(
          raw_value: String,
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)]
        ).returns([T.untyped, T.nilable(T.type_parameter(:T)), T.nilable(Exception)])
      end
      def deserialize_and_decompress_raw_value(raw_value, serializer:)
        serialized_value, error = decompress_raw_value(raw_value)
        return [nil, nil, error] if error

        value = serializer.deserialize(serialized_value)
        [serialized_value, value, nil]
      rescue => e
        [nil, nil, e]
      end

      sig { params(raw_value: String).returns([T.untyped, T.nilable(Exception)]) }
      def decompress_raw_value(raw_value)
        return [nil, CacheValueTooSmallForReadingError.new] if raw_value.bytesize < 2

        version_byte = raw_value.getbyte(0)
        return [nil, CacheFormatVersionMismatchWhenReadingError.new] if version_byte != CACHE_FORMAT_VERSION.getbyte(0)

        compressed_value = raw_value.byteslice(1..-1)
        value = compressor.decompress(T.must(compressed_value))
        return [nil, NilCacheValueWhenDecompressingError.new] unless value

        value = T.unsafe(value).freeze if should_be_frozen?(value)
        [value, nil]
      rescue => e
        [nil, e]
      end

      sig { returns(T::Boolean) }
      def defer_writes?
        return @defer_writes if !@defer_writes.nil?

        result = if !GitHub.after_response.enabled?
          false
        elsif !write_queue_state
          false
        elsif GitHub.remote_cache_mode == :memory
          false
        else
          true
        end

        @defer_writes = result
      end

      sig { params(operation: WriteOperation).returns([T::Boolean, T.nilable(Exception)]) }
      def enqueue_operation(operation)
        queue_state = T.must(write_queue_state)

        writes = queue_state[:writes]
        writes << operation

        begin
          register_write_after_response(queue_state)
        rescue => enqueue_error
          writes.pop
          raise enqueue_error
        end

        [true, nil]
      rescue => e
        [false, e]
      end

      sig { params(queue_state: WriteQueueState).void }
      def register_write_after_response(queue_state)
        return if queue_state[:registered]

        queue_state[:registered] = true
        GitHub.after_response.perform(write_after_response_name) do |_after_response|
          flush_write_queue(queue_state)
        end
      rescue => e
        queue_state[:registered] = false
        raise e
      end

      sig { params(queue_state: WriteQueueState).void }
      def flush_write_queue(queue_state)
        operations = T.let(queue_state[:writes], T::Array[WriteOperation])
        return if operations.empty?

        timer = T.let(::Timer.start, T.nilable(::Timer))

        operations.freeze
        queue_state[:writes] = T.let([], T::Array[WriteOperation])
        queue_state[:registered] = false

        operation_count = T.let(operations.size, Integer)
        recorded_error = T.let(nil, T.nilable(Exception))

        operations = truncate_array(operations, :deferred_write)

        begin
          pipeline_results = if operations.size <= MULTI_OPERATION_BATCH_SIZE
            with_write_multi_timeout do
              @redis.pipelined do |pipeline|
                operations.each do |operation|
                  case operation[:type]
                  when :set
                    pipeline.set(operation[:full_key], operation[:value], ex: operation[:expires_in], keepttl: false)
                  when :delete
                    pipeline.unlink(operation[:full_key])
                  end
                end
              end
            end
          else
            all_pipeline_results = T.let([], T::Array[T.untyped])
            with_write_multi_timeout do
              operations.each_slice(MULTI_OPERATION_BATCH_SIZE) do |batch_operations|
                batch_results = @redis.pipelined do |pipeline|
                  batch_operations.each do |operation|
                    case operation[:type]
                    when :set
                      pipeline.set(operation[:full_key], operation[:value], ex: operation[:expires_in], keepttl: false)
                    when :delete
                      pipeline.unlink(operation[:full_key])
                    end
                  end
                end
                all_pipeline_results.concat(batch_results)
              end
            end
            all_pipeline_results
          end

          operations.each_with_index do |operation, index|
            pipeline_result = pipeline_results[index]
            error = case operation[:type]
            when :set
              pipeline_result == "OK" ? nil : UnexpectedRedisSetResultError.new
            when :delete
              pipeline_result.is_a?(Integer) ? nil : UnexpectedRedisUnlinkResultError.new
            else
              StandardError.new("Unknown operation type: #{operation[:type]}")
            end

            next if error.nil?

            recorded_error ||= error
            record_deferred_write_failure(error, key: operation[:full_key], operation_type: operation[:type])
          end
        rescue => pipeline_exception
          recorded_error ||= pipeline_exception
          record_deferred_write_failure(pipeline_exception)
        end

        if registry = GH.context.remote_cache_registry
          registry.delete(write_queue_key)
        end
      rescue => error
        recorded_error ||= error
        record_deferred_write_failure(error)
      ensure
        queue_state[:registered] = false

        if timer
          timer.stop
          record_deferred_write_duration(timer, operation_count, recorded_error)
        end
      end

      sig { returns(T.nilable(WriteQueueState)) }
      def write_queue_state
        registry = GH.context.remote_cache_registry
        return unless registry

        queue_state = registry[write_queue_key]
        if queue_state
          T.cast(queue_state, WriteQueueState)
        else
          new_state = T.let(
            { writes: T.let([], T::Array[WriteOperation]), registered: false },
            WriteQueueState
          )
          registry[write_queue_key] = new_state
          new_state
        end
      rescue
        nil
      end

      sig { returns(String) }
      def write_queue_key
        @write_queue_key ||= T.let("#{namespace}_deferred_writes_#{object_id}".gsub(/[\/-]/, "_"), T.nilable(String))
      end

      sig { returns(String) }
      def write_after_response_name
        @write_after_response_name ||= T.let("remote_cache:writes:#{namespace}:#{object_id}", T.nilable(String))
      end

      sig do
        params(
          error: Exception,
          key: T.nilable(String),
          operation_type: T.nilable(OperationType)
        ).void
      end
      def record_deferred_write_failure(error, key: nil, operation_type: nil)
        metric_tags = base_metric_tags + ["error:#{error.class.name}"]
        metric_tags << "operation:#{operation_type}" if operation_type
        metric_tags << "error_cause:#{error.cause.class.name}" if error.cause
        GitHub.dogstats.increment("github.remote_cache.deferred.write_failures", tags: metric_tags)

        log_data = {
          "gh.cache.namespace": namespace,
          "gh.cache.key": key,
          "error.class": error.class.name,
          "error.message": error.message
        }
        log_data["gh.cache.operation_type"] = operation_type.to_s if operation_type

        GitHub.logger.warn(
          "Deferred cache write failed",
          log_data
        )
      rescue
        # Ignore logging errors
      end

      sig do
        params(
          timer: ::Timer,
          operation_count: Integer,
          error: T.nilable(Exception)
        ).void
      end
      def record_deferred_write_duration(timer, operation_count, error)
        tags = base_metric_tags + ["method:write_queue", "operation_count:#{operation_count}"]
        if error
          tags << "error:#{error.class.name}"
          tags << "error_cause:#{error.cause.class.name}" if error.cause
        end

        # Pin the host tag to a constant, default value to reduce cardinality and cost of metric.
        # Also, manually add the current stamp tag since that was previously auto-added based on
        # the host tag.
        tags.push(GitHub::Dogstats::DEFAULT_HOST_TAG, GitHub::TaggingHelper.stamp_tag)

        GitHub.dogstats.distribution(
          "github.remote_cache.deferred.time",
          timer.elapsed_ms(5),
          tags: tags
        )
      rescue
        # Ignore metric errors
      end
    end
  end
end
