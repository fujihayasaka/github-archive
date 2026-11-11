# typed: strict
# frozen_string_literal: true

require "hashdiff"

module GitHub
  # An interface for observing staleness between cache values and source of truth values.
  # For example implementations, see:
  #   - GitHub::RemoteCache::ApplicationRecordStalenessObserver
  #   - GitHub::RemoteCache::PrimitiveValueStalenessObserver
  module RemoteCache::StalenessObserver
    include Kernel
    extend T::Helpers
    extend T::Generic
    abstract!

    SourceValueType = type_member

    # Determines whether the cache value is stale compared to the source value.
    # Implementations should compare the two values and return true if the cache value is considered stale.
    # Normally, this would be implemented by comparing the two values and determining if there are any differences.
    # If staleness is detected, implementations can call `emit_staleness_metric` to emit a staleness metric. This
    # is not necessary, though, and implementations may choose to emit custom metrics or logs on their own.
    #
    # @param cache_value [SourceValueType] the value retrieved from the remote cache
    # @param source_value [SourceValueType] the current value from the source of truth (e.g. database)
    # @param context [Hash{Symbol => T.untyped}] context information about the cache key being checked,
    #                                            created in the implementation of Preset and enriched by the
    #                                            RemoteCache client
    # @return [Boolean] true if the cache value is stale, false otherwise
    sig { abstract.params(cache_value: SourceValueType, source_value: SourceValueType, context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def stale?(cache_value, source_value, context); end

    # Emits a metric representing staleness, called github.remote_cache.staleness, to Datadog based on:
    # - the fields that were found to be stale in the comparison
    # - the provided context (namespace, cache_key_name)
    # - any extra tags provided
    # - endpoint/job/processor currently executing
    #
    # Call this in implementations of `stale?` when staleness is detected.
    #
    # @param comparison [GitHub::RemoteCache::Comparison] the comparison object containing staleness details
    # @param context [Hash{Symbol => T.untyped}] context information about the cache key being checked,
    #                                            created in the implementation of Preset and enriched by the
    #                                            RemoteCache client
    # @param extra_tags [Array<String>] additional tags to include in the metric
    #
    # @return [void]
    sig { params(comparison: GitHub::RemoteCache::Comparison, context: T::Hash[Symbol, T.untyped], extra_tags: T::Array[String]).void }
    def emit_staleness_metric(comparison, context, extra_tags = [])
      mismatches = comparison.mismatches
      return if !mismatches.present?

      tags = []

      # Pin the host tag to a constant, default value to reduce cardinality and cost of metric.
      # Also, manually add the stamp and site tags since those are often useful.
      tags.push(GitHub::Dogstats::DEFAULT_HOST_TAG, GitHub::TaggingHelper.stamp_tag, GitHub::TaggingHelper.site_tag)

      if GitHub.context[:remote_call_source_datadog_tags]
        tags.concat(GitHub.context[:remote_call_source_datadog_tags])
      end

      tags.concat(mismatches.map { |field| "stale_field:#{field}" })
      tags.concat(extra_tags)

      namespace = T.let(context[:namespace] || "unknown", String)
      cache_key_name = T.let(context[:cache_key_name] || :unknown, Symbol)
      tags.push("namespace:#{namespace}", "cache_key_name:#{cache_key_name}")

      GitHub.dogstats.distribution("github.remote_cache.staleness", 1, tags: tags)
    end
  end
end
