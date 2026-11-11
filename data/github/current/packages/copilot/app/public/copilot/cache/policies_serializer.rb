# typed: strict
# frozen_string_literal: true

module Copilot
  module Cache
    class PoliciesSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      SourceValueType = type_template { { fixed: T::Hash[Symbol, T.untyped] } } # rubocop:disable Sorbet/ForbidTUntyped

      sig { override.params(object: SourceValueType).returns(Object) }
      def self.serialize(object)
        object
      end

      sig { override.params(cache_value: Object).returns(SourceValueType) }
      def self.deserialize(cache_value)
        T.cast(cache_value, SourceValueType).deep_symbolize_keys
      end
    end
  end
end
