# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    class NumericSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      SourceValueType = type_template { { upper: Numeric } }

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
