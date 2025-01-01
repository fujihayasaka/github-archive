# typed: strict
# frozen_string_literal: true

module Users
  module Cache
    class UserSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      CachedType = type_template { { fixed: T.nilable(User) } }

      sig { override.params(object: CachedType).returns(Object) }
      def self.serialize(object)
        return if object.nil?
        object.attributes_before_type_cast
      end

      sig { override.params(cached_value: Object).returns(CachedType) }
      def self.deserialize(cached_value)
        return if cached_value.blank?
        User.instantiate(cached_value)
      end

      sig { override.params(cached_value: T.nilable(CachedType), db_value: T.nilable(CachedType)).returns(GitHub::RemoteCache::Comparison) }
      def self.compare(cached_value, db_value)
        serialized_cached_value = serialize(cached_value)
        diff = Hashdiff.diff(serialized_cached_value, serialize(db_value))
        unless diff.blank?
          diff << [0, "cached-type-#{serialized_cached_value&.send(:[], "type")}"]
        end
        GitHub::RemoteCache::Comparison.new(diff)
      end
    end
  end
end
