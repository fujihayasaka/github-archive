# typed: strict
# frozen_string_literal: true

module Configsd
  module Cache
    class ByTargetStalenessObserver
      extend T::Generic
      extend GitHub::RemoteCache::StalenessObserver

      SourceValueType = type_template { { fixed: T.nilable(Configurations::ResolvedConfigEntries) } }

      sig { override.params(cache_value: SourceValueType, source_value: SourceValueType, context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
      def self.stale?(cache_value, source_value, context)
        serialized_cache_value = cache_value ? Configsd::Cache::ByTargetSerializer.serialize(cache_value) : {}
        serialized_source_value = source_value ? Configsd::Cache::ByTargetSerializer.serialize(source_value) : {}
        diff = Hashdiff.diff(serialized_cache_value, serialized_source_value)
        comparison = GitHub::RemoteCache::Comparison.new(diff)
        emit_staleness_metric(comparison, context)
        comparison.mismatches.present?
      end
    end
  end
end
