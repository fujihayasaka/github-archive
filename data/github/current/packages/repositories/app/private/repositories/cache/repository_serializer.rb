# typed: strict
# frozen_string_literal: true

module Repositories
  class Cache::RepositorySerializer
    extend T::Generic
    extend GitHub::RemoteCache::Serializer
    extend Cache::RepositorySerialization

    CachedType = type_template { { fixed: T.nilable(IRepository) } }

    sig { override.params(object: CachedType).returns(Object) }
    def self.serialize(object)
      return if object.nil?

      {
        "repository" => object.attributes_before_type_cast,
      }
    end

    sig { override.params(cached_value: Object).returns(CachedType) }
    def self.deserialize(cached_value)
      return if cached_value.blank?
      deserialize_repository(cached_value)
    end

    sig { override.params(cached_value: T.nilable(CachedType), db_value: T.nilable(CachedType)).returns(GitHub::RemoteCache::Comparison) }
    def self.compare(cached_value, db_value)
      cached_attr, db_attr = normalize_repository(cached_value, db_value)
      compare_repository(cached_attr, db_attr)
    end
  end
end
