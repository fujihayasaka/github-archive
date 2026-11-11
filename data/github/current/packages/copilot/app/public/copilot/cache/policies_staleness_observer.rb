# typed: strict
# frozen_string_literal: true

module Copilot
  module Cache
    class PoliciesStalenessObserver
      extend T::Helpers
      extend T::Generic
      extend GitHub::RemoteCache::StalenessObserver

      SourceValueType = type_template { { fixed: T::Hash[Symbol, T.untyped] } } # rubocop:disable Sorbet/ForbidTUntyped

      sig { override.params(cache_value: SourceValueType, source_value: SourceValueType, context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) } # rubocop:disable Sorbet/ForbidTUntyped
      def self.stale?(cache_value, source_value, context)
        normalized_cache_value = normalize(cache_value)
        normalized_source_value = normalize(source_value)

        diff = Hashdiff.diff(normalized_cache_value, normalized_source_value)
        comparison = GitHub::RemoteCache::Comparison.new(diff)
        emit_staleness_metric(comparison, context)
        comparison.mismatches.present?
      end

      sig { params(value: SourceValueType).returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
      def self.normalize(value)
        value.deep_dup.tap do |hash|
          hash.delete(:timestamp)
          hash[:model_registry]&.delete(:models_last_checked_at)
        end
      end
    end
  end
end
