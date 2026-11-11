# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    class SymbolSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      SourceValueType = type_template { { fixed: Symbol } }

      sig { override.params(object: SourceValueType).returns(Object) }
      def self.serialize(object)
        object.to_s
      end

      sig { override.params(cache_value: Object).returns(SourceValueType) }
      def self.deserialize(cache_value)
        T.cast(cache_value, String).to_sym
      end
    end
  end
end
