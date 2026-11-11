# typed: strict
# frozen_string_literal: true

module Repositories
  module Cache
    class RepositoryNetworkSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      CachedType = type_template { { fixed: T.nilable(IRepositoryNetwork) } }

      sig { override.params(object: CachedType).returns(Object) }
      def self.serialize(object)
        return if object.nil?
        object.attributes_before_type_cast
      end

      sig { override.params(cached_value: Object).returns(CachedType) }
      def self.deserialize(cached_value)
        return if cached_value.blank?
        RepositoryNetwork.instantiate(cached_value)
      end

      sig { override.params(cached_value: T.nilable(CachedType), db_value: T.nilable(CachedType)).returns(GitHub::RemoteCache::Comparison) }
      def self.compare(cached_value, db_value)
        cached_attr = cached_value&.attributes_before_type_cast || {}
        db_attr = db_value&.attributes_before_type_cast || {}
        GitHub::RemoteCache::Comparison.new(Hashdiff.diff(cached_attr, db_attr))
      end
    end
  end
end
