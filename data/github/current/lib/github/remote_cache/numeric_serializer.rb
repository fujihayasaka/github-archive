# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    class NumericSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      CachedType = type_template { { fixed: Numeric } }

      sig { override.params(object: CachedType).returns(Object) }
      def self.serialize(object)
        object
      end

      sig { override.params(cached_value: Object).returns(CachedType) }
      def self.deserialize(cached_value)
        T.cast(cached_value, Numeric)
      end

      sig { override.params(cached_value: CachedType, db_value: CachedType).returns(GitHub::RemoteCache::Comparison) }
      def self.compare(cached_value, db_value)
        equality = cached_value <=> db_value
        diff = equality.zero? ? [] : [[equality]]
        GitHub::RemoteCache::Comparison.new(diff)
      end
    end
  end
end
