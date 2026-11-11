# typed: strict
# frozen_string_literal: true

module Repositories
  class Cache::RepositorySerializer
    extend T::Generic
    extend GitHub::RemoteCache::Serializer
    extend Cache::RepositorySerialization

    SourceValueType = type_template { { fixed: T.nilable(IRepository) } }

    sig { override.params(object: SourceValueType).returns(Object) }
    def self.serialize(object)
      return if object.nil?

      {
        "repository" => object.attributes_before_type_cast,
      }
    end

    sig { override.params(cache_value: Object).returns(SourceValueType) }
    def self.deserialize(cache_value)
      return if cache_value.blank?
      deserialize_repository(cache_value)
    end
  end
end
