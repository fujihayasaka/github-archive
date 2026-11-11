# typed: strict
# frozen_string_literal: true

module Configsd
  module Cache
    class ByTargetSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      CachedType = type_template { { fixed: T.nilable(Configurations::ResolvedConfigEntries) } }

      sig { override.params(object: CachedType).returns(Object) }
      def self.serialize(object)
        object&.transform_values(&:to_h)
      end

      sig { override.params(cached_value: Object).returns(CachedType) }
      def self.deserialize(cached_value)
        T.unsafe(cached_value)&.transform_values { |v| Configs::Entry.new(**v) }
      end

      sig { override.params(cached_value: T.nilable(CachedType), db_value: T.nilable(CachedType)).returns(GitHub::RemoteCache::Comparison) }
      def self.compare(cached_value, db_value)
        serialized_cached_value = cached_value ? serialize(cached_value) : {}
        serialized_db_value = db_value ? serialize(db_value) : {}
        diff = Hashdiff.diff(serialized_cached_value, serialized_db_value)
        GitHub::RemoteCache::Comparison.new(diff)
      end
    end
  end
end
