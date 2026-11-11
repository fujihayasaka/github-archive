# typed: strict
# frozen_string_literal: true

module Billing
  module Cache
    # Serializes the alertable budget state for the remote cache.
    #
    # The cached value is the array of raw budget hashes returned by
    # billing-platform (the same hashes that `Billing::Platform::Api::Budget`
    # wraps). The remote cache store packs values with MessagePack, which does
    # not support Ruby Symbol values, and the raw budget hashes contain symbol
    # enum values (e.g. :CustomerResource). We therefore serialize to a JSON
    # string, which is MessagePack-safe and round-trips cleanly: every
    # `Billing::Platform::Api::Budget` reader coerces values via
    # `to_s`/`to_f`/`dig` over a `with_indifferent_access` hash, so the
    # symbol-vs-string distinction is not observable on the read path.
    class AlertableBudgetStateSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      SourceValueType = type_template { { fixed: T::Array[T::Hash[T.untyped, T.untyped]] } }

      sig { override.params(object: SourceValueType).returns(Object) }
      def self.serialize(object)
        object.to_json
      end

      sig { override.params(cache_value: Object).returns(SourceValueType) }
      def self.deserialize(cache_value)
        T.cast(JSON.parse(T.cast(cache_value, String)), T::Array[T::Hash[T.untyped, T.untyped]])
      end
    end
  end
end
