# typed: strict
# frozen_string_literal: true

module Copilot
  module Cache
    # Structured serializer for budget-exhausted cache entries.
    # SourceValueType is an array of hashes representing per-org budget data.
    # RemoteCache handles MessagePack encoding; no JSON layer needed.
    class BudgetExhaustedSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      SourceValueType = type_template { { fixed: T.nilable(T::Array[T::Hash[String, T.untyped]]) } } # rubocop:disable Sorbet/ForbidTUntyped

      sig { override.params(object: SourceValueType).returns(Object) }
      def self.serialize(object)
        object
      end

      sig { override.params(cache_value: Object).returns(SourceValueType) }
      def self.deserialize(cache_value)
        T.cast(cache_value, SourceValueType)
      end
    end
  end
end
