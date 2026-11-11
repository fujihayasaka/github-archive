# typed: strict
# frozen_string_literal: true

module Copilot
  module Cache
    # Structured serializer for budget request state cache entries.
    # SourceValueType is a hash representing the request state (e.g. "post_request").
    # RemoteCache handles MessagePack encoding; no JSON layer needed.
    class BudgetRequestStateSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      SourceValueType = type_template { { fixed: T.nilable(T::Hash[String, T.untyped]) } } # rubocop:disable Sorbet/ForbidTUntyped

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
