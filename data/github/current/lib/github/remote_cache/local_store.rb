# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    # In-memory, request-scoped cache store that implements Store.
    #
    # Uses `GH.context.remote_cache_registry` (a `Concurrent::Hash` per request)
    # to store cached values. Intended to sit at the front of a Client so
    # that repeated reads within a single request never leave the process.
    #
    # Keys are fully qualified (namespaced by the client layer).
    # TTLs (`expires_in`) are accepted but ignored — the cache lifecycle is tied
    # to the request context, which is cleared automatically at the end of each
    # request.
    class LocalStore
      include GitHub::RemoteCache::Store

      MISSING = T.let(Object.new.freeze, Object)

      sig { void }
      def initialize
      end

      # --- Store attributes ---------------------------------------------------

      sig { override.returns(T::Boolean) }
      def local?
        true
      end

      sig { override.returns(T::Array[String]) }
      def base_metric_tags
        ["redis_cluster:local", "redis_url:local"]
      end

      # --- single-key operations ----------------------------------------------

      sig { override.params(key: String).returns([T.untyped, Symbol, T.nilable(Exception)]) }
      def read(key)
        cache = local_cache
        return [nil, :miss, nil] unless cache

        return [nil, :miss, nil] unless cache.key?(key)

        value = cache[key]

        if value.equal?(MISSING)
          [nil, :local, nil]
        else
          [duplicate_value(value), :local, nil]
        end
      rescue => error
        [nil, :error, error]
      end

      sig { override.params(key: String, value: T.untyped, expires_in: Integer).returns([T::Boolean, Symbol, T.nilable(Exception)]) }
      def write(key, value, expires_in:)
        cache = local_cache
        return [false, :inline, nil] unless cache

        cache[key] = value.nil? ? MISSING : duplicate_value(value)

        [true, :inline, nil]
      rescue => error
        [false, :error, error]
      end

      sig { override.params(key: String).returns([T::Boolean, Symbol, T.nilable(Exception)]) }
      def delete(key)
        cache = local_cache
        return [false, :inline, nil] unless cache

        cache.delete(key)

        [true, :inline, nil]
      rescue => error
        [false, :error, error]
      end

      # --- multi-key operations -----------------------------------------------

      sig { override.params(keys: T::Array[String]).returns(T::Hash[String, [T.untyped, Symbol, T.nilable(Exception)]]) }
      def read_multi(keys)
        results = T.let({}, T::Hash[String, [T.untyped, Symbol, T.nilable(Exception)]])
        keys.each do |key|
          results[key] = read(key)
        end
        results
      end

      sig do
        override.params(
          keys_values: T::Hash[String, T.untyped],
          expires_in: T::Hash[String, Integer],
        ).returns(T::Hash[String, [T::Boolean, Symbol, T.nilable(Exception)]])
      end
      def write_multi(keys_values, expires_in:)
        results = T.let({}, T::Hash[String, [T::Boolean, Symbol, T.nilable(Exception)]])
        keys_values.each do |key, value|
          ttl = expires_in.fetch(key, 0)
          results[key] = write(key, value, expires_in: ttl)
        end
        results
      end

      sig { override.params(keys: T::Array[String]).returns(T::Hash[String, [T::Boolean, Symbol, T.nilable(Exception)]]) }
      def delete_multi(keys)
        results = T.let({}, T::Hash[String, [T::Boolean, Symbol, T.nilable(Exception)]])
        keys.each do |key|
          results[key] = delete(key)
        end
        results
      end

      private

      sig { returns(T.nilable(Concurrent::Hash)) }
      def local_cache
        return unless (registry = GH.context.remote_cache_registry)

        registry[local_cache_key] ||= Concurrent::Hash.new
      rescue
        nil
      end

      sig { returns(String) }
      def local_cache_key
        @local_cache_key ||= T.let(
          "local_store_#{object_id}",
          T.nilable(String),
        )
      end

      sig { params(value: T.untyped).returns(T.untyped) }
      def duplicate_value(value)
        if value.is_a?(String)
          value.dup.freeze
        elsif value.respond_to?(:deep_dup)
          value.deep_dup
        elsif value.respond_to?(:dup)
          value.dup
        else
          value
        end
      end
    end
  end
end
