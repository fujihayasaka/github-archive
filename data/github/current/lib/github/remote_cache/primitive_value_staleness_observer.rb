# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    class PrimitiveValueStalenessObserver
      extend T::Helpers
      extend T::Generic
      extend GitHub::RemoteCache::StalenessObserver

      PrimitiveType = T.type_alias { { upper: T.any(String, Symbol, Numeric, T::Boolean, Time, Date) } }
      SourceValueType = type_template do
        { upper: T.any(PrimitiveType, T::Array[PrimitiveType], T::Set[PrimitiveType], T::Hash[PrimitiveType, PrimitiveType]) }
      end

      sig { override.params(cache_value: SourceValueType, source_value: SourceValueType, context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
      def self.stale?(cache_value, source_value, context)
        !cache_value.eql?(source_value)
      end
    end
  end
end
