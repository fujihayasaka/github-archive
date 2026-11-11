# typed: strict
# frozen_string_literal: true

module Billing
  module Cache
    # Observes staleness for the alertable budget state cache.
    #
    # The cache value is a JSON-normalized array of budget hashes (string keys
    # and values) while the source-of-truth value is the raw array (which may
    # contain symbol enum values). We normalize the source through the same JSON
    # round-trip before diffing so representation differences alone are never
    # reported as staleness.
    class AlertableBudgetStateStalenessObserver
      extend T::Helpers
      extend T::Generic
      extend GitHub::RemoteCache::StalenessObserver

      SourceValueType = type_template { { fixed: T::Array[T::Hash[T.untyped, T.untyped]] } }

      sig { override.params(cache_value: SourceValueType, source_value: SourceValueType, context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
      def self.stale?(cache_value, source_value, context)
        normalized_source = JSON.parse(source_value.to_json)
        diff = Hashdiff.diff(cache_value, normalized_source)
        comparison = GitHub::RemoteCache::Comparison.new(diff)

        emit_staleness_metric(comparison, context) if comparison.mismatches.present?

        comparison.mismatches.present?
      end
    end
  end
end
