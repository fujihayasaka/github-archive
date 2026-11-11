# typed: strict
# frozen_string_literal: true

module Users
  module Cache
    class UserSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      SourceValueType = type_template { { fixed: T.nilable(User) } }

      sig { override.params(object: SourceValueType).returns(Object) }
      def self.serialize(object)
        return if object.nil?
        object.attributes_before_type_cast
      end

      sig { override.params(cache_value: Object).returns(SourceValueType) }
      def self.deserialize(cache_value)
        return if cache_value.blank?
        User.instantiate(cache_value)
      end
    end
  end
end
