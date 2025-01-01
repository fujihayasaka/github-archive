# typed: strict
# frozen_string_literal: true

require "hashdiff"

module GitHub
  module RemoteCache
    module Serializer
      extend T::Helpers
      extend T::Generic
      interface!

      CachedType = type_member

      # serialize takes in an application object and formats it for storage in the cache.
      sig { abstract.params(object: CachedType).returns(Object) }
      def serialize(object); end

      # deserialize takes a value from the cache and returns it to a format useable by the application.
      sig { abstract.params(cached_value: Object).returns(CachedType) }
      def deserialize(cached_value); end

      # compare expects two values in the state the application uses them;
      # - application objects should not yet be serialized for caching
      # - cache values should be deserialized back into application objects
      sig { abstract.params(cached_value: CachedType, db_value: CachedType).returns(GitHub::RemoteCache::Comparison) }
      def compare(cached_value, db_value); end
    end
  end
end
