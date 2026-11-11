# typed: strict
# frozen_string_literal: true

module Configsd
  module Cache
    class ByTargetSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      SourceValueType = type_template { { fixed: T.nilable(Configurations::ResolvedConfigEntries) } }

      sig { override.params(object: SourceValueType).returns(Object) }
      def self.serialize(object)
        object&.transform_values(&:to_h)
      end

      sig { override.params(cache_value: Object).returns(SourceValueType) }
      def self.deserialize(cache_value)
        T.unsafe(cache_value)&.transform_values { |v| Configs::Entry.new(**v) }
      end
    end
  end
end
