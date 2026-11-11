# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    # Low-level client for interacting with the remote cache.
    #
    # NOTE: In most cases, you should use `GitHub::RemoteCache::Preset` instead of instantiating
    # this class directly. Presets provide a higher-level, more convenient interface with
    # pre-configured settings for common caching patterns.
    #
    # To create clients for use with presets, use `GitHub::RemoteCache::ClientFactory` to set up
    # a cache module that vends client instances.
    #
    # See `GitHub::RemoteCache::Preset` for the recommended way to use remote caching.
    # See `GitHub::RemoteCache::ClientFactory` for creating cache client modules.
    class Client
      include GitHub::ResilienceMixin

      @cache_key_name_vexi_actors = T.let({}, T::Hash[Symbol, GitHub::VexiCacheKeyName])
      @dynamic_tags = T.let({}, T::Hash[String, String])

      class InvalidTtlValueError < StandardError; end

      class RolloutMode < T::Enum
        enums do
          ReturnSourceValueWithExtendedTelemetry = new
          ReturnCacheValueWithExtendedTelemetry = new
          ReturnCacheValueWithBaseTelemetry = new
        end
      end

      MAX_TTL = T.let(1.day.seconds, Integer)
      NIL_CACHE_KEY_ID = T.let(String.new.freeze, String)

      # Pre-allocated frozen strings for common boolean tags to avoid allocations
      BOOLEAN_TAG_CACHE = T.let(
        {
          cache_enabled: { true => "cache_enabled:true", false => "cache_enabled:false" },
          force_refresh: { true => "force_refresh:true", false => "force_refresh:false" },
          fallback: { true => "fallback:true", false => "fallback:false" },
        }.freeze,
        T::Hash[Symbol, T::Hash[T::Boolean, String]]
      )

      # Pre-allocated frozen strings for tri-state tags (true/false/partial) to avoid allocations
      TRISTATE_TAG_CACHE = T.let(
        {
          cache_key_id_present: {
            true => "cache_key_id_present:true",
            false => "cache_key_id_present:false",
            :partial => "cache_key_id_present:partial",
          },
          cache_hit: {
            true => "cache_hit:true",
            false => "cache_hit:false",
            :partial => "cache_hit:partial",
          },
          stale: {
            true => "stale:true",
            false => "stale:false",
            :partial => "stale:partial",
          },
          cache_delete_success: {
            true => "cache_delete_success:true",
            false => "cache_delete_success:false",
            :partial => "cache_delete_success:partial",
          },
        }.freeze,
        T::Hash[Symbol, T::Hash[T.any(T::Boolean, Symbol), String]]
      )

      # Pre-allocated frozen strings for strategy tags to avoid allocations
      STRATEGY_TAG_CACHE = T.let(
        {
          store_write_strategy: {
            inline: "store_write_strategy:inline",
            deferred: "store_write_strategy:deferred",
            error: "store_write_strategy:error",
          },
          store_delete_strategy: {
            inline: "store_delete_strategy:inline",
            deferred: "store_delete_strategy:deferred",
            error: "store_delete_strategy:error",
          },
        }.freeze,
        T::Hash[Symbol, T::Hash[Symbol, String]]
      )

      sig { params(store: T.nilable(GitHub::RemoteCache::Store)).void }
      def initialize(store)
        @store = T.let(store, T.nilable(GitHub::RemoteCache::Store))
        @base_metric_tags = T.let(nil, T.nilable(T::Array[String]))
      end

      # Fetches a value from the cache or computes it using the provided block, with database
      # error handling and fallback logic.
      #
      # NOTE: Consider using `GitHub::RemoteCache::Preset` for a more convenient interface
      # instead of calling this method directly.
      #
      # This method attempts to fetch a value from the cache using the given key name, id and namespace
      # (provided when building the remote cache instance). The cache key name is a static value used to
      # identify the cache calls in metrics. The cache key id is the dynamic part. The cache key is
      # constructed as `<namespace>/<cache_key_name>/<cache_key_id>`.
      #
      # If the cache value is not present or expired, it executes the provided block to compute the value
      # (typically a database calculation), and stores the result in the cache. If the database calculation
      # fails, it falls back to the provided static fallback value.
      #
      # The `fallback`` value is returned if both the database and cache are unavailable.
      #
      # The `enabled` parameter allows conditional caching. If false, the block is executed
      # without using the cache.
      #
      # The `ttl` parameter can be an integer for a fixed TTL, a proc that computes the TTL based on
      # the computed value.
      #
      # The `staleness_observer` parameter is an optional proc that receives the staleness comparison. Normally,
      # this would be used through the Preset's staleness_observer method to have access to object used for
      # cache key construction, and then emit custom metrics/logs to help understand cause of staleness.
      #
      # The `rollout_mode` parameter, with three possible values:
      # - `ReturnSourceValueWithExtendedTelemetry`: reads from both the cache and source of truth,
      #    returns the source of truth value, and reports extended dogstats metrics including staleness information.
      # - `ReturnCacheValueWithExtendedTelemetry`: reads from both the cache and source of truth,
      #    returns the cache value, and reports extended dogstats metrics including staleness information.
      # - `ReturnCacheValueWithBaseTelemetry`: (default) reads only from the cache unless a miss occurs,
      #    returns the cache value, and reports basic dogstats metrics without staleness information.
      #
      # The method uses a circuit breaker to handle Redis connection issues gracefully, preventing
      # cascading failures in the application.
      #
      # Example usages:
      #
      #   remote_cache.fetch(cache_key_name: :my_key, cache_key_id: "123", ttl: 5.minutes) do
      #     MyModel.where(condition: true).count
      #   end
      #
      #   remote_cache.fetch(
      #     cache_key_name: :my_key,
      #     cache_key_id: "123",
      #     enabled: -> true,
      #     ttl: ->(value) { value > 100 ? 10.minutes : 1.minute },
      #     fallback: 0,
      #     rollout_mode: RolloutMode::ReturnCacheValueWithBaseTelemetry
      #   ) do
      #     MyModel.where(condition: true).count
      #   end
      #

      sig do
        type_parameters(:T).
        params(
          cache_key_name: Symbol,
          cache_key_id: String,
          ttl: T.any(T.proc.params(value: T.type_parameter(:T)).returns(Integer), Integer),
          fallback: T.type_parameter(:T),
          resilience_error_types: T::Array[T.class_of(StandardError)],
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)],
          staleness_observer: T.nilable(T.proc.params(comparison: GitHub::RemoteCache::Comparison).void),
          enabled: T::Boolean,
          method: Symbol,
          force_refresh: T::Boolean,
          rollout_mode: RolloutMode,
          block: T.proc.returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
      end
      def fetch(
        cache_key_name:, cache_key_id:,
        ttl:, fallback:, resilience_error_types:, serializer:,
        staleness_observer: nil,
        enabled: true, method: :fetch, force_refresh: false,
        rollout_mode: RolloutMode::ReturnCacheValueWithBaseTelemetry,
        &block
      )
        if !store_configured?
          return block.call if resilience_error_types.empty?

          return with_error_fallback(
            fallback: fallback,
            allowed_error_types: resilience_error_types,
            &block
          ).value
        end

        timer = ::Timer.start

        enabled = cache_key_name_enabled?(enabled, cache_key_name) && GitHub.caching_enabled?
        cache_key_id_present = cache_key_id_present?(cache_key_id)
        used_fallback = T.let(false, T::Boolean)

        if !cache_key_id_present || !enabled
          return block.call if resilience_error_types.empty?

          lookup_result = with_error_fallback(
            fallback: fallback,
            allowed_error_types: resilience_error_types,
            &block
          )
          used_fallback = lookup_result.used_fallback?
          return lookup_result.value
        end

        cache_key = build_cache_key(cache_key_name, cache_key_id)
        cache_value = T.let(nil, T.nilable(T.type_parameter(:T)))

        if !force_refresh
          cache_value, cache_source, cache_read_error = read_cache(cache_key, serializer)
          cache_hit = case cache_value
          when nil
            false
          else
            true
          end
        end

        source_value = T.let(nil, T.nilable(T.type_parameter(:T)))
        result = T.let(nil, T.nilable(T.type_parameter(:T)))
        expiry = T.let(nil, T.nilable(Numeric))
        expiry_error = T.let(nil, T.nilable(StandardError))
        data_source_timer = T.let(nil, T.nilable(::Timer))
        extended_telemetry_overhead_timer = T.let(nil, T.nilable(::Timer))
        mismatches = T.let(nil, T.nilable(T::Array[String]))
        return_cache_values, extended_telemetry, rollout_mode = determine_rollout_mode(rollout_mode, cache_key_name)
        extended_telemetry_overhead = extended_telemetry && (!return_cache_values || cache_hit) && !force_refresh

        if !cache_hit || !return_cache_values || extended_telemetry
          extended_telemetry_overhead_timer = ::Timer.start if extended_telemetry_overhead
          data_source_timer = ::Timer.start

          if resilience_error_types.empty?
            source_value = block.call
            used_fallback = false
          else
            fallthrough_result = with_error_fallback(
              fallback: fallback,
              allowed_error_types: resilience_error_types,
              &block
            )
            used_fallback = fallthrough_result.used_fallback?
            source_value = fallthrough_result.value
          end

          data_source_timer.stop

          if !used_fallback && !cache_hit
            case source_value
            when nil
            else
              expiry, expiry_error = calculate_expiry(ttl, source_value)
              _, cache_write_strategy, cache_write_error = write_cache(cache_key, source_value, serializer, expiry) if expiry
            end
          end

          staleness, staleness_error, mismatches = staleness_compare(serializer, staleness_observer, cache_value, source_value) if cache_hit && extended_telemetry && !used_fallback

          extended_telemetry_overhead_timer&.stop
        end

        return_cache_values && cache_hit ? cache_value : source_value
      ensure
        if store_configured?
          metric_tags = build_metric_tags(cache_key_name, method: method)

          add_boolean_tag(metric_tags, :cache_enabled, enabled)
          if staleness_error
            add_metric_tag(metric_tags, "stale:error")
            add_error_tags(metric_tags, "staleness_error", staleness_error)
          end
          add_tristate_tag(metric_tags, :stale, staleness)
          add_source_tag(metric_tags, cache_source)
          add_boolean_tag(metric_tags, :force_refresh, force_refresh)

          add_error_tags(metric_tags, "store_read_error", cache_read_error) if cache_read_error
          add_error_tags(metric_tags, "store_write_error", cache_write_error) if cache_write_error
          add_strategy_tag(metric_tags, :store_write_strategy, cache_write_strategy) if cache_write_strategy
          add_tristate_tag(metric_tags, :cache_hit, cache_hit)
          add_rollout_mode_tag(metric_tags, rollout_mode)
          add_boolean_tag(metric_tags, :fallback, T.must(used_fallback))
          add_serializer_tag(metric_tags, serializer)
          add_tristate_tag(metric_tags, :cache_key_id_present, cache_key_id_present)

          # Only emit TTL metrics when we actually computed an expiry (i.e., miss/write path)
          if expiry
            add_ttl_tag(metric_tags, expiry)
          end
          if expiry_error
            add_error_tags(metric_tags, "ttl_error", expiry_error)
          end

          if mismatches.present?
            GitHub.logger.info("cache mismatches detected: #{mismatches.join(', ')}", { "gh.cache.namespace": namespace, "gh.cache.key": cache_key })
            mismatches.each do |field|
              add_stale_field_tag(metric_tags, field)
            end
          end

          if extended_telemetry && data_source_timer
            report_metric("github.remote_cache.data_source_time", data_source_timer.elapsed_ms(5), tags: metric_tags)
          end

          subtracted_timer = (extended_telemetry_overhead && extended_telemetry_overhead_timer) ? extended_telemetry_overhead_timer : nil

          timer.stop

          report_timer_metrics(timer, metric_tags, subtract_timer: subtracted_timer)
        end
      end

      # Fetches multiple values from the cache or computes them using the provided block, with database
      # error handling and fallback logic.
      #
      # NOTE: Consider using `GitHub::RemoteCache::Preset` for a more convenient interface
      # instead of calling this method directly.
      #
      # This method attempts to fetch multiple values from the cache using the given key name, ids and namespace
      # (provided when building the remote cache instance). The cache key name is a static value used to
      # identify the cache calls in metrics. The cache key ids are the dynamic parts. Each cache key is
      # constructed as `<namespace>/<cache_key_name>/<cache_key_id>`.
      #
      # If cache values are not present or expired, it executes the provided block with the missing cache key ids
      # to compute the values (typically a database query), and stores the results in the cache. The block receives
      # an array of cache key ids that need to be computed and should return a hash mapping cache key ids to their
      # computed values. If the database calculation fails, it falls back to the provided static fallback value
      # for each missing key.
      #
      # The `fallback` value is returned for each key if both the database and cache are unavailable.
      #
      # The `enabled` parameter allows conditional caching. If false, the block is executed
      # without using the cache.
      #
      # The `ttl` parameter can be an integer for a fixed TTL, or a proc that computes the TTL based on
      # the computed value.
      #
      # The `staleness_observer` parameter is an optional proc that receives the staleness comparison. Normally,
      # this would be used through the Preset's staleness_observer method to have access to object used for
      # cache key construction, and then emit custom metrics/logs to help understand cause of staleness.
      #
      # The `rollout_mode` parameter controls the behavior of the cache:
      # - ReturnCacheValueWithBaseTelemetry: Returns cache values when available, reports basic metrics
      # - ReturnCacheValueWithExtendedTelemetry: Returns cache values, always reads from database, reports extended metrics including staleness
      # - ReturnSourceValueWithExtendedTelemetry: Returns database values, always reads from database and cache, reports extended metrics including staleness
      #
      # The method uses a circuit breaker to handle Redis connection issues gracefully, preventing
      # cascading failures in the application.
      #
      # Returns a hash mapping cache key ids to their values (either from cache or computed). Keys with
      # non-present cache key ids will have nil values.
      #
      # Example usages:
      #
      #   remote_cache.fetch_multi(
      #     cache_key_name: :my_key,
      #     cache_key_ids: ["123", "456", "789"],
      #     ttl: 5.minutes,
      #     fallback: 0,
      #     resilience_error_types: [ActiveRecord::RecordNotFound],
      #     serializer: GitHub::RemoteCache::NumericSerializer
      #   ) do |cache_key_ids|
      #     MyModel.where(id: cache_key_ids).pluck(:id, :value).to_h
      #   end
      #
      #   remote_cache.fetch_multi(
      #     cache_key_name: :my_key,
      #     cache_key_ids: ["123", "456", "789"],
      #     ttl: ->(value) { value > 100 ? 10.minutes : 1.minute },
      #     fallback: 0,
      #     resilience_error_types: [],
      #     serializer: GitHub::RemoteCache::NumericSerializer,
      #     enabled: true,
      #     rollout_mode: RolloutMode::ReturnSourceValueWithExtendedTelemetry,
      #     force_refresh: false
      #   ) do |cache_key_ids|
      #     MyModel.where(id: cache_key_ids).pluck(:id, :value).to_h
      #   end
      sig do
        type_parameters(:T).
        params(
          cache_key_name: Symbol,
          cache_key_ids: T::Array[String],
          ttl: T.any(T.proc.params(value: T.type_parameter(:T)).returns(Integer), Integer),
          fallback: T.type_parameter(:T),
          resilience_error_types: T::Array[T.class_of(StandardError)],
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)],
          staleness_observer: T.nilable(T.proc.params(comparison: GitHub::RemoteCache::Comparison).void),
          enabled: T::Boolean,
          force_refresh: T::Boolean,
          rollout_mode: RolloutMode,
          block: T.proc.params(cache_key_ids: T::Array[String]).returns(T::Hash[String, T.type_parameter(:T)]),
        ).returns(T::Hash[String, T.nilable(T.type_parameter(:T))])
      end
      def fetch_multi(
        cache_key_name:, cache_key_ids:,
        ttl:, fallback:, resilience_error_types:, serializer:,
        staleness_observer: nil,
        enabled: true, force_refresh: false,
        rollout_mode: RolloutMode::ReturnCacheValueWithBaseTelemetry,
        &block
      )
        timer = ::Timer.start

        empty_hash = Hash.new(capacity: cache_key_ids.size)
        return empty_hash if cache_key_ids.empty?

        # Check which cache key ids are present
        present_cache_key_ids = T.let([], T::Array[String])
        cache_key_ids_present = T.let(empty_hash.dup, T::Hash[String, T::Boolean])
        cache_key_ids.each do |cache_key_id|
          if cache_key_id_present?(cache_key_id)
            present_cache_key_ids << cache_key_id
            cache_key_ids_present[cache_key_id] = true
          else
            cache_key_ids_present[cache_key_id] = false
          end
        end

        # Construct fallback hash
        fallback_proc = -> do
          frozen_fallback = freeze_fallback_value(fallback, cache_key_name)
          present_cache_key_ids.each_with_object(empty_hash.dup) do |key, hash|
            hash[key] = frozen_fallback
          end
        end

        # Return source of truth values early if store is not configured
        if !store_configured?
          return block.call(present_cache_key_ids) if resilience_error_types.empty?

          return with_error_fallback(
            fallback: fallback_proc,
            allowed_error_types: resilience_error_types
          ) { block.call(present_cache_key_ids) }.value
        end

        store = T.must(@store)
        used_fallback = T.let(false, T::Boolean)
        enabled = cache_key_name_enabled?(enabled, cache_key_name) && GitHub.caching_enabled?

        # Return early if not enabled
        if !enabled
          return block.call(present_cache_key_ids) if resilience_error_types.empty?

          fallthrough_result = with_error_fallback(
            fallback: fallback_proc,
            allowed_error_types: resilience_error_types
          ) { block.call(present_cache_key_ids) }
          used_fallback = fallthrough_result.used_fallback?
          return fallthrough_result.value
        end

        # Construct full cache keys
        cache_keys = T.let(empty_hash.dup, T::Hash[String, String])
        present_cache_key_ids.each do |cache_key_id|
          cache_keys[cache_key_id] = build_cache_key(cache_key_name, cache_key_id)
        end

        return_cache_values, extended_telemetry, rollout_mode = determine_rollout_mode(rollout_mode, cache_key_name)

        # Fetch from cache
        #
        # Only if:
        # - force_refresh is disabled
        #
        # And only for keys where:
        # - cache key id is present
        cache_key_ids_to_fetch_from_cache = present_cache_key_ids
        cache_key_ids_to_fetch_from_source_of_truth = T.let([], T::Array[String])
        cache_values = T.let(empty_hash.dup, T::Hash[String, T.type_parameter(:T)])
        cache_hits = T.let(empty_hash.dup, T::Hash[String, T::Boolean])
        cache_hit_count = T.let(0, Integer)

        if !force_refresh && cache_key_ids_to_fetch_from_cache.any?
          cache_read_results = store.read_multi(T.unsafe(cache_keys).values_at(*cache_key_ids_to_fetch_from_cache), serializer: serializer)

          cache_key_ids_to_fetch_from_cache.each do |cache_key_id|
            cache_key = cache_keys[cache_key_id]
            next unless cache_key

            value, source, error = cache_read_results[cache_key]

            case value
            when nil
              cache_key_ids_to_fetch_from_source_of_truth << cache_key_id
              cache_hits[cache_key_id] = false
            else
              cache_values[cache_key_id] = value
              cache_hits[cache_key_id] = true
              cache_hit_count += 1
            end
          end
        end

        all_cache_hits = cache_hit_count == cache_key_ids.size

        # Fetch from source of truth
        #
        # Only for keys where:
        # - missing cache key id
        # - OR it was a cache miss
        # - OR extended telemetry is enabled
        # - OR return_cache_values is disabled
        # - OR force_refresh is enabled
        extended_telemetry_overhead_timer = T.let(nil, T.nilable(::Timer))
        extended_telemetry_overhead = extended_telemetry && (!return_cache_values || all_cache_hits) && !force_refresh

        if force_refresh || !return_cache_values || extended_telemetry || cache_key_ids_to_fetch_from_source_of_truth.any?
          source_values = T.let(nil, T.nilable(T::Hash[String, T.type_parameter(:T)]))

          # If force_refresh is enabled, or extended telemetry is enabled, or we're returning source values
          # instead of cache values (i.e., !return_cache_values), we fetch the source of truth for all keys
          cache_key_ids_to_fetch_from_source_of_truth = present_cache_key_ids if force_refresh || !return_cache_values || extended_telemetry

          extended_telemetry_overhead_timer = ::Timer.start if extended_telemetry_overhead
          data_source_timer = T.let(::Timer.start, ::Timer)

          fallback_proc = -> do
            frozen_fallback = freeze_fallback_value(fallback, cache_key_name)
            cache_key_ids_to_fetch_from_source_of_truth.each_with_object(empty_hash.dup) do |cache_key_id, hash|
              hash[cache_key_id] = frozen_fallback
            end
          end

          if resilience_error_types.empty?
            source_values = block.call(cache_key_ids_to_fetch_from_source_of_truth)
            used_fallback = false
          else
            fallthrough_result = with_error_fallback(
              fallback: fallback_proc,
              allowed_error_types: resilience_error_types
            ) { block.call(cache_key_ids_to_fetch_from_source_of_truth) }
            used_fallback = fallthrough_result.used_fallback?
            source_values = fallthrough_result.value
          end

          data_source_timer.stop

          # Write back to cache
          #
          # Only if:
          # - we didn't trigger a fallback
          #
          # And only for keys where:
          # - it was a cache miss
          # - AND the value from the source of truth is not nil
          # - AND we can calculate a valid expiry
          if !used_fallback
            expiries = T.let(empty_hash.dup, T::Hash[String, Integer])
            expiry_results = T.let(empty_hash.dup, T::Hash[String, [T.nilable(Numeric), T.nilable(StandardError)]])
            values_to_write_to_cache = empty_hash.dup

            present_cache_key_ids.each do |cache_key_id|
              cache_hit = cache_hits[cache_key_id]
              next if cache_hit && !force_refresh

              value = source_values[cache_key_id]
              next if T.unsafe(value).nil?

              expiry, _ = expiry_results[cache_key_id] = calculate_expiry(ttl, value)
              next if expiry.nil?

              cache_key = cache_keys[cache_key_id]
              next unless cache_key

              expiries[cache_key] = expiry
              values_to_write_to_cache[cache_key] = value
            end

            if values_to_write_to_cache.any?
              cache_write_results = store.write_multi(values_to_write_to_cache, serializer: serializer, expires_in: expiries)
            end
          end

          # Compute staleness
          #
          # Only if:
          # - extended_telemetry is enabled
          # - AND we didn't trigger a fallback
          #
          # And only for keys where:
          # - we had a cache hit (i.e. we have something to compare against)
          if extended_telemetry && !used_fallback
            staleness_results = empty_hash.dup
            cache_hits.each do |cache_key_id, cache_hit|
              next if !cache_hit

              case cache_value = cache_values[cache_key_id]
              when nil
                next
              end

              case source_value = source_values[cache_key_id]
              when nil
                next
              end
              staleness_results[cache_key_id] = staleness_compare(serializer, staleness_observer, cache_value, source_value)
            end
          end

          extended_telemetry_overhead_timer&.stop
        end

        # Construct final result hash
        #
        # For each input key:
        # - If source of truth value was available, use it.
        # - Else, use cache value if available.
        # - Else, use nil. This would happen when cache key ID is not present.
        result = T.let(empty_hash.dup, T::Hash[String, T.nilable(T.type_parameter(:T))])
        present_cache_key_ids.each do |cache_key_id|
          if cache_values.key?(cache_key_id) && return_cache_values
            result[cache_key_id] = cache_values[cache_key_id]
          elsif source_values && source_values.key?(cache_key_id)
            result[cache_key_id] = source_values[cache_key_id]
          else
            result[cache_key_id] = nil
          end
        end

        result
      ensure
        if store_configured?
          # Compute and emit per-call metrics
          metric_tags = build_metric_tags(cache_key_name, method: :fetch_multi)

          add_boolean_tag(metric_tags, :cache_enabled, enabled)
          add_boolean_tag(metric_tags, :force_refresh, force_refresh)
          add_rollout_mode_tag(metric_tags, rollout_mode)
          add_boolean_tag(metric_tags, :fallback, T.must(used_fallback))
          add_serializer_tag(metric_tags, serializer)
          add_num_keys_tag(metric_tags, cache_key_ids.size)

          if cache_keys
            # Compute and emit per-key metrics
            cache_key_ids.each do |cache_key_id|
              per_key_metric_tags = metric_tags.dup

              if cache_key_ids_present[cache_key_id]
                add_tristate_tag(per_key_metric_tags, :cache_key_id_present, cache_key_ids_present[cache_key_id])
              end

              cache_key = cache_keys[cache_key_id]
              next unless cache_key

              if !cache_read_results.nil? && cache_hits && cache_read_results[cache_key]
                _, cache_source, cache_read_error = cache_read_results[cache_key]

                add_tristate_tag(per_key_metric_tags, :cache_hit, cache_hits[cache_key_id])
                add_source_tag(per_key_metric_tags, cache_source)
                add_error_tags(per_key_metric_tags, "store_read_error", cache_read_error) if cache_read_error
              end

              if !expiry_results.nil? && expiry_results[cache_key_id]
                expiry, expiry_error = expiry_results[cache_key_id]
                add_error_tags(per_key_metric_tags, "ttl_error", expiry_error) if expiry_error
                add_ttl_tag(per_key_metric_tags, expiry) if expiry
              end

              if cache_write_results && cache_write_results[cache_key]
                _, cache_write_strategy, cache_write_error = cache_write_results[cache_key]

                add_strategy_tag(per_key_metric_tags, :store_write_strategy, cache_write_strategy) if cache_write_strategy
                add_error_tags(per_key_metric_tags, "store_write_error", cache_write_error) if cache_write_error
              end

              if staleness_results && staleness_results[cache_key_id]
                staleness, staleness_error, mismatches = staleness_results[cache_key_id]
                if staleness_error
                  add_metric_tag(per_key_metric_tags, "stale:error")
                  add_error_tags(per_key_metric_tags, "staleness_error", staleness_error)
                end
                add_tristate_tag(per_key_metric_tags, :stale, staleness)

                if mismatches.present?
                  mismatches.each do |field|
                    add_stale_field_tag(per_key_metric_tags, field)
                  end
                end
              end

              GitHub.dogstats.increment("github.remote_cache.per_key.count", tags: per_key_metric_tags)
            end
          end

          if !cache_read_results.nil? && !cache_read_results.empty?
            sources = cache_read_results.values.lazy.filter_map { |(_, source, _)| source }.uniq.first(2)
            add_source_tag(metric_tags, sources.one? ? sources.first : :mixed)
          end

          if !cache_key_ids_present.nil? && !cache_key_ids_present.empty?
            present_count = cache_key_ids_present.count { |_, present| present }
            if present_count == 0
              add_tristate_tag(metric_tags, :cache_key_id_present, false)
            elsif present_count == cache_key_ids_present.size
              add_tristate_tag(metric_tags, :cache_key_id_present, true)
            else
              add_tristate_tag(metric_tags, :cache_key_id_present, :partial)
            end
          end

          if expiry_results && !expiry_results.empty?
            ttls = expiry_results.values.lazy.filter_map { |(expiry, _)| expiry }.uniq.first(2)
            if ttls.one?
              add_ttl_tag(metric_tags, ttls.first)
            elsif ttls.any?
              add_metric_tag(metric_tags, "cache_ttl:mixed")
            end
          end

          if expiry_results && !expiry_results.empty?
            first_ttl_error = expiry_results.values.find { |(_, error)| error }&.last
            add_error_tags(metric_tags, "ttl_error", first_ttl_error) if first_ttl_error
          end

          if cache_read_results && !cache_read_results.empty?
            first_read_error = cache_read_results.values.find { |(_, _, error)| error }&.last
            add_error_tags(metric_tags, "store_read_error", first_read_error) if first_read_error
          end

          if cache_write_results && !cache_write_results.empty?
            first_write_error = cache_write_results.values.find { |(_, _, error)| error }&.last
            add_error_tags(metric_tags, "store_write_error", first_write_error) if first_write_error
          end

          if staleness_results && !staleness_results.empty?
            first_staleness_error = staleness_results.values.find { |(_, error, _)| error }&.second
            add_error_tags(metric_tags, "stale_error", first_staleness_error) if first_staleness_error
          end

          if staleness_results && !staleness_results.empty?
            stale_count = staleness_results.count { |_, (stale, _, _)| stale }
            if stale_count == 0
              add_tristate_tag(metric_tags, :stale, false)
            elsif stale_count == staleness_results.size
              add_tristate_tag(metric_tags, :stale, true)
            else
              add_tristate_tag(metric_tags, :stale, :partial)
            end
          end

          if cache_key_ids_to_fetch_from_cache && !cache_key_ids_to_fetch_from_cache.empty?
            if cache_hit_count == 0
              add_tristate_tag(metric_tags, :cache_hit, false)
            elsif cache_hit_count == cache_key_ids_to_fetch_from_cache.size
              add_tristate_tag(metric_tags, :cache_hit, true)
            else
              add_tristate_tag(metric_tags, :cache_hit, :partial)
            end
          end


          if extended_telemetry && data_source_timer
            report_metric("github.remote_cache.data_source_time", data_source_timer.elapsed_ms(5), tags: metric_tags)
          end

          subtracted_timer = (extended_telemetry_overhead && extended_telemetry_overhead_timer) ? extended_telemetry_overhead_timer : nil

          timer.stop

          report_timer_metrics(timer, metric_tags, subtract_timer: subtracted_timer)
        end
      end

      # Stores a value in the cache without requiring a block.
      #
      # NOTE: Consider using `GitHub::RemoteCache::Preset` for a more convenient interface
      # instead of calling this method directly.
      #
      # This method writes a value directly to the cache using the given key name, id, and namespace.
      # Unlike `fetch`, this method does not compute values or use rollout modes — it simply writes
      # the provided value to the cache with the specified TTL.
      #
      # The `ttl` parameter can be an integer for a fixed TTL, or a proc that computes the TTL based on
      # the value.
      #
      # Example usage:
      #
      #   remote_cache.store(
      #     cache_key_name: :my_key,
      #     cache_key_id: "123",
      #     value: 42,
      #     ttl: 5.minutes,
      #     serializer: GitHub::RemoteCache::NumericSerializer
      #   )
      #
      sig do
        type_parameters(:T).
        params(
          cache_key_name: Symbol,
          cache_key_id: String,
          value: T.type_parameter(:T),
          ttl: T.any(T.proc.params(value: T.type_parameter(:T)).returns(Integer), Integer),
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)],
          enabled: T::Boolean
        ).void
      end
      def store(
        cache_key_name:, cache_key_id:, value:,
        ttl:, serializer:, enabled: true
      )
        return if !store_configured?

        timer = ::Timer.start
        enabled = cache_key_name_enabled?(enabled, cache_key_name) && GitHub.caching_enabled?
        cache_key_id_present = cache_key_id_present?(cache_key_id)

        # Early return for nil values - we don't store nil in cache
        is_nil_value = case value
        when nil
          true
        else
          false
        end

        if !cache_key_id_present || !enabled || is_nil_value
          report_store_metrics(
            timer: timer,
            cache_key_name: cache_key_name,
            serializer: serializer,
            enabled: enabled,
            cache_key_id_present: cache_key_id_present
          )
          return
        end

        cache_key = build_cache_key(cache_key_name, cache_key_id)
        expiry, expiry_error = calculate_expiry(ttl, value)

        cache_write_strategy = T.let(nil, T.nilable(Symbol))
        cache_write_error = T.let(nil, T.nilable(Exception))

        if expiry
          _, cache_write_strategy, cache_write_error = write_cache(cache_key, value, serializer, expiry)
        end

        report_store_metrics(
          timer: timer,
          cache_key_name: cache_key_name,
          serializer: serializer,
          enabled: enabled,
          cache_key_id_present: cache_key_id_present,
          expiry: expiry,
          expiry_error: expiry_error,
          cache_write_strategy: cache_write_strategy,
          cache_write_error: cache_write_error
        )
      end

      # Invalidates a cache entry by its name and id.
      #
      # NOTE: Consider using `GitHub::RemoteCache::Preset` for a more convenient interface
      # instead of calling this method directly.
      #
      # This method constructs a cache key using the provided `cache_key_name` and `cache_key_id`
      # (`<namespace>/<cache_key_name>/<cache_key_id>`), and deletes the corresponding entry from
      # the cache.
      #
      # Example usage:
      #
      #   remote_cache.invalidate(cache_key_name: :my_key, cache_key_id: "123")
      #
      sig do
        params(
          cache_key_name: Symbol,
          cache_key_id: String,
          event: T.nilable(String)
        ).void
      end
      def invalidate(cache_key_name:, cache_key_id:, event: nil)
        return if !store_configured?
        timer = ::Timer.start

        cache_key_name_enabled = cache_key_name_enabled?(true, cache_key_name)
        cache_key_id_present = cache_key_id_present?(cache_key_id)
        return if !cache_key_id_present || !cache_key_name_enabled

        cache_key = build_cache_key(cache_key_name, cache_key_id)
        _cache_delete_success, cache_delete_strategy, cache_delete_error = T.must(@store).delete(cache_key)
      ensure
        if store_configured?
          metric_tags = build_metric_tags(cache_key_name, method: :invalidate)

          add_event_tag(metric_tags, event) if event
          add_boolean_tag(metric_tags, :cache_enabled, T.must(cache_key_name_enabled))
          add_tristate_tag(metric_tags, :cache_key_id_present, cache_key_id_present)
          add_strategy_tag(metric_tags, :store_delete_strategy, cache_delete_strategy) if cache_delete_strategy
          add_error_tags(metric_tags, "store_delete_error", cache_delete_error) if cache_delete_error

          timer.stop

          report_timer_metrics(timer, metric_tags)
        end
      end

      # Invalidates multiple cache entries for a cache key name.
      #
      # NOTE: Consider using `GitHub::RemoteCache::Preset` for a more convenient interface
      # instead of calling this method directly.
      #
      # This method constructs cache keys using the provided `cache_key_name` and `cache_key_ids`
      # (`<namespace>/<cache_key_name>/<cache_key_id>`), issuing a single delete call to the cache
      # store when possible.
      #
      # Example usage:
      #
      #   remote_cache.invalidate_multi(cache_key_name: :my_key, cache_key_ids: ["123", "456"])
      #
      sig do
        params(
          cache_key_name: Symbol,
          cache_key_ids: T::Array[String],
          event: T.nilable(String)
        ).void
      end
      def invalidate_multi(cache_key_name:, cache_key_ids:, event: nil)
        return if !store_configured?
        timer = ::Timer.start

        return if cache_key_ids.empty?
        cache_key_name_enabled = cache_key_name_enabled?(true, cache_key_name)
        return if !cache_key_name_enabled

        empty_hash = Hash.new(capacity: cache_key_ids.size)
        cache_keys = T.let(empty_hash.dup, T::Hash[String, String])
        cache_delete_results = T.let(
          empty_hash.dup,
          T.nilable(T::Hash[String, [T::Boolean, Symbol, T.nilable(Exception)]])
        )

        cache_key_ids.each do |cache_key_id|
          next unless cache_key_id_present?(cache_key_id)

          cache_keys[cache_key_id] = build_cache_key(cache_key_name, cache_key_id)
        end
        cache_delete_error = T.let(nil, T.nilable(Exception))

        if cache_keys.any?
          begin
            cache_delete_results = T.must(@store).delete_multi(cache_keys.values)
          rescue => e
            cache_delete_error = e
          end
        end
      ensure
        if store_configured?
          metric_tags = build_metric_tags(cache_key_name, method: :invalidate_multi)

          add_event_tag(metric_tags, event) if event
          add_boolean_tag(metric_tags, :cache_enabled, T.must(cache_key_name_enabled))

          # All operations in a single delete_multi call have the same strategy (either all :inline
          # or all :deferred) since defer_writes? is checked once for the entire batch at the store level.
          first_result = cache_delete_results.values.first if cache_delete_results
          first_strategy = T.let(first_result ? first_result[1] : nil, T.nilable(Symbol))
          is_deferred = first_strategy == :deferred

          if cache_keys
            if cache_keys.size == cache_key_ids.size
              add_tristate_tag(metric_tags, :cache_key_id_present, true)
            elsif cache_keys.size == 0
              add_tristate_tag(metric_tags, :cache_key_id_present, false)
            elsif cache_keys.size > 0
              add_tristate_tag(metric_tags, :cache_key_id_present, :partial)
            end
          end

          add_num_keys_tag(metric_tags, cache_key_ids.size)
          add_strategy_tag(metric_tags, :store_delete_strategy, first_strategy) if first_strategy

          # Skip error and success reporting for deferred writes since they represent
          # enqueue status rather than actual deletion status
          if !is_deferred && cache_keys && cache_delete_results
            successes = T.let(0, Integer)
            result_errors = T.let([], T::Array[Exception])

            if cache_keys.any?
              cache_keys.each_value do |cache_key|
                result = cache_delete_results[cache_key]
                next unless result

                success, _, error = result
                successes += 1 if success
                result_errors << error if error
              end
            end

            first_error = cache_delete_error || result_errors.first

            if cache_keys.any?
              key_count = cache_keys.size
              if cache_delete_error
                add_tristate_tag(metric_tags, :cache_delete_success, :partial)
              elsif successes == 0
                add_tristate_tag(metric_tags, :cache_delete_success, false)
              elsif successes == key_count
                add_tristate_tag(metric_tags, :cache_delete_success, true)
              else
                add_tristate_tag(metric_tags, :cache_delete_success, :partial)
              end
            end

            add_error_tags(metric_tags, "store_delete_error", first_error) if first_error
          end

          timer.stop

          report_timer_metrics(timer, metric_tags)
        end
      end

      # Returns true if a store is configured for this client.
      #
      # When no store is configured, cache operations will be skipped and the client
      # will fall through to computing values directly.
      sig { returns(T::Boolean) }
      def store_configured?
        @store != nil
      end

      sig { params(cache_key_name: Symbol).returns(GitHub::VexiCacheKeyName) }
      def self.cache_key_name_vexi_actor(cache_key_name)
        @cache_key_name_vexi_actors[cache_key_name] ||= GitHub::VexiCacheKeyName.new(cache_key_name)
      end

      sig { params(tag_string: String).returns(String) }
      def self.dynamic_tag(tag_string)
        @dynamic_tags[tag_string] ||= tag_string.freeze
      end

      private

      sig { params(cache_key_id: String).returns(T::Boolean) }
      def cache_key_id_present?(cache_key_id)
        !NIL_CACHE_KEY_ID.equal?(cache_key_id)
      end

      sig do
        type_parameters(:T)
        .params(
          cache_key: String,
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)]
        ).returns([T.nilable(T.type_parameter(:T)), Symbol, T.nilable(Exception)])
      end
      def read_cache(cache_key, serializer)
        T.must(@store).read(cache_key, serializer: serializer)
      end

      sig do
        type_parameters(:T)
        .params(
          cache_key: String,
          value: T.type_parameter(:T),
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)],
          expires_in: Integer
        ).returns([
          T::Boolean,
          GitHub::RemoteCache::Store::WriteStrategy,
          T.nilable(Exception)
        ])
      end
      def write_cache(cache_key, value, serializer, expires_in)
        T.must(@store).write(cache_key, value, serializer: serializer, expires_in: expires_in)
      end

      sig { params(cache_key_name: Symbol, cache_key_id: String).returns(String) }
      def build_cache_key(cache_key_name, cache_key_id)
        "#{cache_key_name}/#{cache_key_id}"
      end

      sig { returns(String) }
      def namespace
        T.must(@store).namespace
      end

      sig do
        type_parameters(:T)
        .params(
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)],
          staleness_observer: T.nilable(T.proc.params(comparison: GitHub::RemoteCache::Comparison).void),
          cache_value: T.type_parameter(:T),
          source_value: T.type_parameter(:T)
        ).returns([T::Boolean, T.nilable(StandardError), T::Array[String]])
      end
      def staleness_compare(serializer, staleness_observer, cache_value, source_value)
        comparison = serializer.compare(cache_value, source_value)
        staleness_observer&.call(comparison)
        [!comparison.identical?, nil, comparison.mismatches]
      rescue => e
        [false, e, []]
      end

      sig do
        params(
          ttl: T.any(T.proc.params(value: T.untyped).returns(Integer), Integer),
          value: T.untyped
        ).returns([T.nilable(Integer), T.nilable(StandardError)])
      end
      def calculate_expiry(ttl, value)
        error = nil

        expiry = if ttl.is_a?(Integer)
          ttl
        else
          begin
            ttl.call(value)
          rescue => e
            error = e
            nil
          end
        end

        if expiry && expiry <= 0
          expiry = nil
          error = InvalidTtlValueError.new("Expiry must be greater than 0")
        end

        expiry = expiry && expiry > MAX_TTL ? MAX_TTL : expiry

        [expiry, error]
      end

      sig do
        type_parameters(:Fallback)
        .params(value: T.type_parameter(:Fallback), cache_key_name: Symbol)
        .returns(T.type_parameter(:Fallback))
      end
      def freeze_fallback_value(value, cache_key_name)
        case value
        when NilClass
          return value
        end

        unsafe_value = T.unsafe(value)

        begin
          unsafe_value.freeze
        rescue TypeError => error
          # Ignore freezing errors for certain types
        end

        value
      end

      sig { returns(T::Array[String]) }
      def base_metric_tags
        return @base_metric_tags if @base_metric_tags

        tags = T.let([], T::Array[String])
        tags.concat(@store.base_metric_tags) if @store

        @base_metric_tags = tags.freeze
      end

      sig { params(cache_key_name: T.nilable(Symbol), method: T.nilable(Symbol)).returns(T::Array[String]) }
      def build_metric_tags(cache_key_name, method: nil)
        tags = base_metric_tags.dup
        tags << "cache_key_name:#{cache_key_name}" if cache_key_name
        tags << "method:#{method}" if method

        if GitHub.context[:remote_call_source_datadog_tags]
          tags.concat(GitHub.context[:remote_call_source_datadog_tags])
        end

        # Pin the host tag to a constant, default value to reduce cardinality and cost of metric.
        # Also, manually add the current stamp tag since that was previously auto-added based on
        # the host tag.
        tags.push(GitHub::Dogstats::DEFAULT_HOST_TAG, GitHub::TaggingHelper.stamp_tag)

        tags
      end

      sig { params(metric_name: String, value: Numeric, tags: T::Array[String]).void }
      def report_metric(metric_name, value, tags:)
        GitHub.dogstats.distribution(metric_name, value, tags: tags)
      end

      sig { params(rollout_mode: RolloutMode, cache_key_name: Symbol).returns([T::Boolean, T::Boolean, RolloutMode]) }
      def determine_rollout_mode(rollout_mode, cache_key_name)
        effective_rollout_mode = if FeatureFlag.vexi.enabled?(:remote_cache_return_source_value_with_extended_telemetry_for_cache_key_name, self.class.cache_key_name_vexi_actor(cache_key_name), default: false)
          RolloutMode::ReturnSourceValueWithExtendedTelemetry
        else
          rollout_mode
        end

        case effective_rollout_mode
        when RolloutMode::ReturnSourceValueWithExtendedTelemetry
          return_cache_values = false
          extended_telemetry = true
        when RolloutMode::ReturnCacheValueWithExtendedTelemetry
          return_cache_values = true
          extended_telemetry = true
        when RolloutMode::ReturnCacheValueWithBaseTelemetry
          return_cache_values = true
          extended_telemetry = false
        end

        [return_cache_values, extended_telemetry, effective_rollout_mode]
      end

      sig { params(enabled: T::Boolean, cache_key_name: Symbol).returns(T::Boolean) }
      def cache_key_name_enabled?(enabled, cache_key_name)
        enabled && !FeatureFlag.vexi.enabled?(:remote_cache_disable_for_cache_key_name, self.class.cache_key_name_vexi_actor(cache_key_name), default: false)
      end

      sig do
        params(
          timer: ::Timer,
          cache_key_name: Symbol,
          serializer: GitHub::RemoteCache::Serializer[T.untyped],
          enabled: T::Boolean,
          cache_key_id_present: T::Boolean,
          expiry: T.nilable(Numeric),
          expiry_error: T.nilable(StandardError),
          cache_write_strategy: T.nilable(Symbol),
          cache_write_error: T.nilable(Exception)
        ).void
      end
      def report_store_metrics(
        timer:, cache_key_name:, serializer:, enabled:, cache_key_id_present:,
        expiry: nil, expiry_error: nil, cache_write_strategy: nil, cache_write_error: nil
      )
        metric_tags = build_metric_tags(cache_key_name, method: :store)

        add_boolean_tag(metric_tags, :cache_enabled, enabled)
        add_tristate_tag(metric_tags, :cache_key_id_present, cache_key_id_present)
        add_serializer_tag(metric_tags, serializer)
        add_ttl_tag(metric_tags, expiry) if expiry
        add_error_tags(metric_tags, "ttl_error", expiry_error) if expiry_error
        add_strategy_tag(metric_tags, :store_write_strategy, cache_write_strategy) if cache_write_strategy
        add_error_tags(metric_tags, "store_write_error", cache_write_error) if cache_write_error

        timer.stop

        report_timer_metrics(timer, metric_tags)
      end

      sig { params(metric_tags: T::Array[String], tag_name: Symbol, value: T::Boolean).void }
      def add_boolean_tag(metric_tags, tag_name, value)
        cached_tags = BOOLEAN_TAG_CACHE[tag_name]
        if cached_tags
          metric_tags << T.must(cached_tags[value])
        else
          # Fallback for tags not in cache (shouldn't happen in normal usage)
          metric_tags << "#{tag_name}:#{value ? 'true' : 'false'}"
        end
      end

      sig { params(metric_tags: T::Array[String], tag_name: Symbol, state: T.nilable(T.any(T::Boolean, Symbol))).void }
      def add_tristate_tag(metric_tags, tag_name, state)
        return if state.nil?

        cached_tags = TRISTATE_TAG_CACHE[tag_name]

        if cached_tags
          cached_value = cached_tags[state]
          if cached_value
            metric_tags << cached_value
          else
            metric_tags << "#{tag_name}:#{state}"
          end
        else
          metric_tags << "#{tag_name}:#{state}"
        end
      end

      sig { params(metric_tags: T::Array[String], tag_name: Symbol, strategy: T.nilable(Symbol)).void }
      def add_strategy_tag(metric_tags, tag_name, strategy)
        return if strategy.nil?

        cached_tags = STRATEGY_TAG_CACHE[tag_name]

        if cached_tags
          cached_value = cached_tags[strategy]
          if cached_value
            metric_tags << cached_value
          else
            metric_tags << "#{tag_name}:#{strategy}"
          end
        else
          metric_tags << "#{tag_name}:#{strategy}"
        end
      end

      sig { params(metric_tags: T::Array[String], source: T.nilable(Symbol)).void }
      def add_source_tag(metric_tags, source)
        return if source.nil?

        metric_tags << case source
        when :local
          "store_read_source:local"
        when :redis
          "store_read_source:redis"
        when :error
          "store_read_source:error"
        when :mixed
          "store_read_source:mixed"
        else
          "store_read_source:#{source}"
        end
      end

      sig { params(metric_tags: T::Array[String], tag: String).void }
      def add_metric_tag(metric_tags, tag)
        metric_tags << tag
      end

      sig { params(metric_tags: T::Array[String], serializer: GitHub::RemoteCache::Serializer[T.untyped]).void }
      def add_serializer_tag(metric_tags, serializer)
        metric_tags << self.class.dynamic_tag("serializer:#{T.unsafe(serializer).name}")
      end

      sig { params(metric_tags: T::Array[String], rollout_mode: RolloutMode).void }
      def add_rollout_mode_tag(metric_tags, rollout_mode)
        metric_tags << case rollout_mode
        when RolloutMode::ReturnSourceValueWithExtendedTelemetry
          "rollout_mode:return_source_value_with_extended_telemetry"
        when RolloutMode::ReturnCacheValueWithExtendedTelemetry
          "rollout_mode:return_cache_value_with_extended_telemetry"
        when RolloutMode::ReturnCacheValueWithBaseTelemetry
          "rollout_mode:return_cache_value_with_base_telemetry"
        end
      end

      sig { params(metric_tags: T::Array[String], ttl: Numeric).void }
      def add_ttl_tag(metric_tags, ttl)
        metric_tags << self.class.dynamic_tag("cache_ttl:#{ttl}")
      end

      sig { params(metric_tags: T::Array[String], event: String).void }
      def add_event_tag(metric_tags, event)
        metric_tags << self.class.dynamic_tag("event:#{event}")
      end

      sig { params(metric_tags: T::Array[String], field: String).void }
      def add_stale_field_tag(metric_tags, field)
        metric_tags << self.class.dynamic_tag("stale_field:#{field}")
      end

      sig { params(metric_tags: T::Array[String], num_keys: Integer).void }
      def add_num_keys_tag(metric_tags, num_keys)
        metric_tags << case num_keys
        when 1
          "num_keys:1"
        when 2..10
          "num_keys:2-10"
        when 11..40
          "num_keys:11-40"
        when 41..100
          "num_keys:41-100"
        else
          "num_keys:100+"
        end
      end

      sig { params(metric_tags: T::Array[String], tag_prefix: String, error: Exception).void }
      def add_error_tags(metric_tags, tag_prefix, error)
        metric_tags << "#{tag_prefix}:#{error.class.name}"
        metric_tags << "#{tag_prefix}_cause:#{error.cause.class.name}" if error.cause
      end

      sig do
        params(
          timer: ::Timer,
          metric_tags: T::Array[String],
          subtract_timer: T.nilable(::Timer)
        ).void
      end
      def report_timer_metrics(timer, metric_tags, subtract_timer: nil)
        time = timer.elapsed_ms(5)
        cpu_time = timer.elapsed_cpu_ms(5)
        idle_time = timer.elapsed_idle_ms(5)

        if subtract_timer
          # The metric time should represent the ReturnCacheValueWithBaseTelemetry rollout mode to
          # confidently assess the impact of adding cache calls to an existing data access point.
          # In other rollout modes, we always read from the database, so we need to deduct the database
          # time in case of a cache hit or all cache hits.

          subtract_time = subtract_timer.elapsed_ms(5)
          subtract_cpu_time = subtract_timer.elapsed_cpu_ms(5)
          subtract_idle_time = subtract_timer.elapsed_idle_ms(5)

          time -= subtract_time
          cpu_time -= subtract_cpu_time
          idle_time -= subtract_idle_time
        end

        report_metric("github.remote_cache.time", time, tags: metric_tags)
        report_metric("github.remote_cache.cpu_time", cpu_time, tags: metric_tags)
        report_metric("github.remote_cache.idle_time", idle_time, tags: metric_tags)
      end
    end
  end
end
