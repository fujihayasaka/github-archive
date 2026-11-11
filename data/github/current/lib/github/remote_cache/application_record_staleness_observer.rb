# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    class ApplicationRecordStalenessObserver
      extend T::Helpers
      extend T::Generic
      extend GitHub::RemoteCache::StalenessObserver

      SourceValueType = type_template { { upper: T.nilable(ApplicationRecord::Base) } }

      sig { override.params(cache_value: SourceValueType, source_value: SourceValueType, context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
      def self.stale?(cache_value, source_value, context)
        serialized_cache_value = cache_value&.attributes_before_type_cast
        serialized_source_value = source_value&.attributes_before_type_cast
        diff = Hashdiff.diff(serialized_cache_value, serialized_source_value)
        comparison = GitHub::RemoteCache::Comparison.new(diff)

        if comparison.mismatches.present?
          cache_type = serialized_cache_value&.send(:[], "type") || "unknown"
          emit_staleness_metric(comparison, context, ["cache_type:#{cache_type}"])
        end

        comparison.mismatches.present?
      end
    end
  end
end
