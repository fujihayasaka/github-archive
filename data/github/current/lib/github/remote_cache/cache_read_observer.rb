# typed: strict
# frozen_string_literal: true

module GitHub
  # An interface for observing cache access events (hits and misses).
  # This observer is invoked after a cache read operation and allows application developers to emit
  # custom metrics or perform custom logic based on the cache hit/miss result.
  #
  # For example, you can use this observer to emit custom metrics tagged with information about
  # the cached resource (e.g., repository type, user type) to better understand cache effectiveness.
  #
  # Example implementation:
  #
  #   class MyCustomCacheReadObserver
  #     extend T::Helpers
  #     extend T::Generic
  #     extend GitHub::RemoteCache::CacheReadObserver
  #
  #     SourceValueType = type_template { { fixed: MyValue } }
  #
  #     def self.observe_cache_read(cache_hit, cache_value, context)
  #       # Extract custom context
  #       repository_id = context[:repository_id]
  #       user_type = context[:user_type]
  #
  #       # Emit custom metric with extra tags
  #       emit_cache_read_metric(
  #         cache_hit,
  #         context,
  #         ["repository_id:#{repository_id}", "user_type:#{user_type}"]
  #       )
  #     end
  #   end
  #
  module RemoteCache
    module CacheReadObserver
      include Kernel
      extend T::Helpers
      extend T::Generic
      abstract!

      SourceValueType = type_member

      # Called after a cache read operation to observe cache hit/miss events.
      #
      # @param cache_hit Boolean whether the cache read resulted in a hit (true) or miss (false)
      # @param cache_value [SourceValueType] the value from cache (nil on miss)
      # @param context [Hash{Symbol => T.untyped}] context information about the cache key being checked,
      #                                            created in the implementation of Preset and enriched by the
      #                                            RemoteCache client. Standard keys include:
      #                                            - :cache_key_name - the cache key name
      #                                            - :cache_key_id - the cache key id
      #                                            - :namespace - the cache namespace
      #                                            - :serializer - the serializer used
      #                                            plus any custom context provided via cache_hit_context
      # @return [void]
      sig do
        abstract.params(
          cache_hit: T.any(T::Boolean, Symbol),
          cache_value: T.nilable(SourceValueType),
          context: T::Hash[Symbol, T.untyped]
        ).void
      end
      def observe_cache_read(cache_hit, cache_value, context); end

      # Emits a metric representing cache hit/miss, called github.remote_cache.cache_read, to Datadog based on:
      # - the cache hit status (hit, miss)
      # - the provided context (namespace, cache_key_name)
      # - any extra tags provided
      # - endpoint/job/processor currently executing
      #
      # Call this in implementations of `observe_cache_read` when you want to emit custom metrics.
      #
      # @param cache_hit Boolean whether the cache read resulted in a hit (true) or miss (false)
      # @param context [Hash{Symbol => T.untyped}] context information about the cache key being checked,
      #                                            created in the implementation of Preset and enriched by the
      #                                            RemoteCache client
      # @param extra_tags [Array<String>] additional tags to include in the metric
      #
      # @return [void]
      sig do
        params(
          cache_hit: T::Boolean,
          context: T::Hash[Symbol, T.untyped],
          extra_tags: T::Array[String]
        ).void
      end
      def emit_cache_read_metric(cache_hit, context, extra_tags = [])
        tags = []

        # Pin the host tag to a constant, default value to reduce cardinality and cost of metric.
        # Also, manually add the stamp, site, and region tags since those are often useful.
        tags.push(GitHub::Dogstats::DEFAULT_HOST_TAG, GitHub::TaggingHelper.stamp_tag, GitHub::TaggingHelper.site_tag, GitHub::TaggingHelper.region_tag)

        if GitHub.context[:remote_call_source_datadog_tags]
          tags.concat(GitHub.context[:remote_call_source_datadog_tags])
        end

        tags.concat(extra_tags)

        namespace = T.let(context[:namespace] || "unknown", String)
        cache_key_name = T.let(context[:cache_key_name] || :unknown, Symbol)
        tags.push("namespace:#{namespace}", "cache_key_name:#{cache_key_name}")

        cache_hit_tag = cache_hit ? "cache_hit:true" : "cache_hit:false"
        tags.push(cache_hit_tag)

        GitHub.dogstats.distribution("github.remote_cache.cache_read", 1, tags: tags)
      end
    end
  end
end
