# typed: strict
# frozen_string_literal: true

module Repositories
  class Cache::RepositoryStalenessObserver
    extend T::Generic
    extend GitHub::RemoteCache::StalenessObserver
    extend Cache::RepositorySerialization

    SourceValueType = type_template { { fixed: T.nilable(IRepository) } }

    sig { override.params(cache_value: SourceValueType, source_value: SourceValueType, context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def self.stale?(cache_value, source_value, context)
      comparison = compare(cache_value, source_value)

      if stale = comparison.mismatches.present?
        emit_staleness_metric(comparison, context)
      end

      stale
    end

    sig { params(cache_value: SourceValueType, source_value: SourceValueType).returns(GitHub::RemoteCache::Comparison) }
    def self.compare(cache_value, source_value)
      cache_attr, source_attr = normalize_repository(cache_value, source_value)
      compare_repository(cache_attr, source_attr)
    end
  end
end
