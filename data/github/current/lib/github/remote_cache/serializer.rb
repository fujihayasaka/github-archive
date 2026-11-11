# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    module Serializer
      extend T::Helpers
      extend T::Generic
      interface!

      SourceValueType = type_member

      # Serialize takes in an application object and formats it for storage in the cache.
      # This could involve converting it to a string, a hash, or any other format suitable for caching.
      #
      # @param object [SourceValueType] The object to be serialized for caching.
      # @return [Object] The serialized representation of the object, suitable for storage in the cache.
      #
      # For examples, see:
      # - Users::Cache::UserSerializer
      # - GitHub::RemoteCache::NumericSerializer
      # - GitHub::RemoteCache::NumericSetSerializer
      sig { abstract.params(object: SourceValueType).returns(Object) }
      def serialize(object); end

      # Deserialize takes a value from the cache and returns it to a format useable by the application.
      #
      # @param cache_value [Object] The cache value to be deserialized.
      # @return [SourceValueType] The deserialized object, ready for use in the application.
      sig { abstract.params(cache_value: Object).returns(SourceValueType) }
      def deserialize(cache_value); end
    end
  end
end
