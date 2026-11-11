# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    # Abstract interface for cache stores used by `GitHub::RemoteCache::Client`.
    #
    # Stores are arranged in a stack by the Client. Reads check stores in order
    # (first hit wins, earlier stores are backfilled). Writes and deletes propagate
    # to every store in the stack.
    #
    # All values passed through the interface are **pre-serialized** Ruby objects
    # (the output of `Serializer#serialize`). Stores must not call serializers
    # themselves — that responsibility belongs to the client layer.
    #
    # Implementors must define all abstract methods. The return-tuple shapes are
    # kept consistent so that Client telemetry works uniformly regardless of
    # the concrete store type.
    module Store
      extend T::Helpers
      interface!

      # --- attributes ---------------------------------------------------------

      sig { abstract.returns(T::Boolean) }
      def local?; end

      sig { abstract.returns(T::Array[String]) }
      def base_metric_tags; end

      # --- single-key operations ----------------------------------------------

      # Read a pre-serialized value by key.
      #
      # @param key [String] fully-qualified cache key (pre-namespaced by the client layer)
      # @return [(serialized_value_or_nil, source_symbol, error_or_nil)]
      sig { abstract.params(key: String).returns([T.untyped, Symbol, T.nilable(Exception)]) }
      def read(key); end

      # Write a pre-serialized value.
      #
      # @param key   [String]  cache key
      # @param value [Object]  already-serialized value (output of Serializer#serialize)
      # @param expires_in [Integer] TTL in seconds (stores may ignore if not applicable)
      # @return [(success, strategy_symbol, error_or_nil)]
      sig { abstract.params(key: String, value: T.untyped, expires_in: Integer).returns([T::Boolean, Symbol, T.nilable(Exception)]) }
      def write(key, value, expires_in:); end

      # Delete a cache entry.
      #
      # @return [(success, strategy_symbol, error_or_nil)]
      sig { abstract.params(key: String).returns([T::Boolean, Symbol, T.nilable(Exception)]) }
      def delete(key); end

      # --- multi-key operations -----------------------------------------------

      # Read multiple pre-serialized values.
      #
      # @return Hash mapping each requested key to [serialized_value_or_nil, source_symbol, error_or_nil]
      sig do
        abstract.params(
          keys: T::Array[String]
        ).returns(T::Hash[String, [T.untyped, Symbol, T.nilable(Exception)]])
      end
      def read_multi(keys); end

      # Write multiple pre-serialized values.
      #
      # @return Hash mapping each key to [success, strategy_symbol, error_or_nil]
      sig do
        abstract.params(
          keys_values: T::Hash[String, T.untyped],
          expires_in: T::Hash[String, Integer]
        ).returns(T::Hash[String, [T::Boolean, Symbol, T.nilable(Exception)]])
      end
      def write_multi(keys_values, expires_in:); end

      # Delete multiple cache entries.
      #
      # @return Hash mapping each key to [success, strategy_symbol, error_or_nil]
      sig do
        abstract.params(
          keys: T::Array[String]
        ).returns(T::Hash[String, [T::Boolean, Symbol, T.nilable(Exception)]])
      end
      def delete_multi(keys); end
    end
  end
end
