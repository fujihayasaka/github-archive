# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    class NumericSetSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      SourceValueType = type_template { { upper: T::Set[Numeric] } }

      sig { override.params(object: SourceValueType).returns(Object) }
      def self.serialize(object)
        object.to_a
      end

      sig { override.params(cache_value: Object).returns(SourceValueType) }
      def self.deserialize(cache_value)
        T.cast(Set.new(T.cast(cache_value, T::Array[Numeric])), SourceValueType)
      end
    end
  end
end
