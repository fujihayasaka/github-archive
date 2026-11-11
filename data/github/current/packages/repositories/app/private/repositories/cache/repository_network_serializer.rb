# typed: strict
# frozen_string_literal: true

module Repositories
  module Cache
    class RepositoryNetworkSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      SourceValueType = type_template { { fixed: T.nilable(IRepositoryNetwork) } }

      sig { override.params(object: SourceValueType).returns(Object) }
      def self.serialize(object)
        return if object.nil?
        object.attributes_before_type_cast
      end

      sig { override.params(cache_value: Object).returns(SourceValueType) }
      def self.deserialize(cache_value)
        return if cache_value.blank?
        RepositoryNetwork.instantiate(cache_value)
      end
    end
  end
end
