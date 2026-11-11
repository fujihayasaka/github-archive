# typed: strict
# frozen_string_literal: true

require "set"

module GitHub
  module RemoteCache
    # Client that orchestrates a stack of cache stores for remote caching.
    #
    # Stores are arranged in a stack (typically `[LocalStore, RedisStore]`).
    # Reads check stores in order (first hit wins, earlier stores are
    # backfilled). Writes and deletes propagate to every store in the stack.
    #
    # The client owns serialization: it calls `Serializer#serialize` before
    # writing and `Serializer#deserialize` after reading.
    class Client
      include GitHub::ResilienceMixin

      @cache_key_name_vexi_actors = T.let({}, T::Hash[Symbol, GitHub::VexiCacheKeyName])
      @dynamic_tags = T.let({}, T::Hash[String, String])

      class UnimplementedStalenessObserverError < StandardError; end
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

      sig { params(cache_key_name: Symbol).returns(GitHub::VexiCacheKeyName) }
      def self.cache_key_name_vexi_actor(cache_key_name)
        @cache_key_name_vexi_actors[cache_key_name] ||= GitHub::VexiCacheKeyName.new(cache_key_name)
      end

      sig { params(tag_string: String).returns(String) }
      def self.dynamic_tag(tag_string)
        @dynamic_tags[tag_string] ||= tag_string.freeze
      end

      # Pre-allocated frozen strings for common boolean tags to avoid allocations
      BOOLEAN_TAG_CACHE = T.let(
        {
          cache_enabled: { true => "cache_enabled:true", false => "cache_enabled:false" },
          force_refresh: { true => "force_refresh:true", false => "force_refresh:false" },
          fallback: { true => "fallback:true", false => "fallback:false" },
        }.freeze,
        T::Hash[Symbol, T::Hash[T::Boolean, String]]
      )

      # Pre-allocated frozen strings for tri-state tags to avoid allocations
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

      # Returns true if the stack has any configured store.
      sig { returns(T::Boolean) }
      def store_configured?
        @store_configured
      end

      # Returns true if the stack contains any store beyond request-local caching.
      sig { returns(T::Boolean) }
      def remote_store_configured?
        @remote_store_configured
      end

      sig { returns(String) }
      def namespace
        @namespace
      end

      sig { returns(T::Array[String]) }
      def base_metric_tags
        return [] if @namespace.empty?

        ["namespace:#{@namespace}"]
      end

      sig do
        params(
          stores: T.nilable(T.any(GitHub::RemoteCache::Store, T::Array[GitHub::RemoteCache::Store])),
          namespace: T.nilable(String),
          force_refresh_all: T::Boolean,
        ).void
      end
      def initialize(stores = nil, namespace: nil, force_refresh_all: false)
        normalized_stores = T.let(
          case stores
          when nil
            []
          when Array
            stores
          else
            [stores]
          end,
          T::Array[GitHub::RemoteCache::Store],
        )

        @stores = T.let(normalized_stores.freeze, T::Array[GitHub::RemoteCache::Store])

        derived_namespace = T.let(namespace, T.nilable(String))
        legacy_key_format = T.let(false, T::Boolean)
        if derived_namespace.nil? && @stores.one?
          store = T.must(@stores.first)
          if T.unsafe(store).respond_to?(:namespace)
            derived_namespace = T.cast(T.unsafe(store).namespace, String)
            legacy_key_format = true
          end
        end

        @namespace = T.let(derived_namespace || "", String)
        @legacy_key_format = T.let(legacy_key_format, T::Boolean)
        @store_configured = T.let(@stores.any?, T::Boolean)
        @remote_store_configured = T.let(@stores.any? { |store| !store.local? }, T::Boolean)
        @force_refresh_all = T.let(force_refresh_all, T::Boolean)
      end

      # Fetches a value from the cache or computes it using the provided block.
      #
      # Reads through the store stack in order. On a hit from a later store,
      # earlier stores are backfilled so subsequent reads within the same request
      # hit the fastest store.
      sig do
        type_parameters(:T).
        params(
          cache_key_name: Symbol,
          cache_key_id: String,
          ttl: T.any(T.proc.params(value: T.type_parameter(:T)).returns(Integer), Integer),
          fallback: T.type_parameter(:T),
          resilience_error_types: T::Array[T.class_of(StandardError)],
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)],
          staleness_observer: T.nilable(GitHub::RemoteCache::StalenessObserver[T.type_parameter(:T)]),
          staleness_context: T.nilable(T::Hash[Symbol, T.untyped]),
          cache_read_observer: T.nilable(GitHub::RemoteCache::CacheReadObserver[T.type_parameter(:T)]),
          cache_read_context: T.nilable(T::Hash[Symbol, T.untyped]),
          enabled: T::Boolean,
          method: Symbol,
          force_refresh: T::Boolean,
          rollout_mode: Client::RolloutMode,
          block: T.proc.returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
      end
      def fetch(
        cache_key_name:, cache_key_id:,
        ttl:, fallback:, resilience_error_types:, serializer:,
        staleness_observer: nil, staleness_context: nil,
        cache_read_observer: nil, cache_read_context: nil,
        enabled: true, method: :fetch, force_refresh: false,
        rollout_mode: Client::RolloutMode::ReturnCacheValueWithBaseTelemetry,
        &block
      )
        if !store_configured?
          return block.call if resilience_error_types.empty? || GitHub::ResilienceMixin.should_reraise_in_non_production?

          return with_error_fallback(
            fallback: fallback,
            allowed_error_types: resilience_error_types,
            &block
          ).value
        end

        timer = ::Timer.start(cpu: true)

        force_refresh = true if @force_refresh_all

        enabled = cache_key_name_enabled?(enabled, cache_key_name)
        cache_key_id_present = cache_key_id_present?(cache_key_id)
        used_fallback = T.let(false, T::Boolean)

        if !cache_key_id_present || !enabled
          return block.call if resilience_error_types.empty? || GitHub::ResilienceMixin.should_reraise_in_non_production?

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
        cache_read_store_tags = T.let(nil, T.nilable(T::Array[String]))
        cache_write_store_tags = T.let(nil, T.nilable(T::Array[String]))
        return_cache_values, extended_telemetry, rollout_mode = determine_rollout_mode(rollout_mode, cache_key_name)

        if !force_refresh
          serialized_value, cache_source, cache_read_error, cache_read_store_tags = read_through_stores(cache_key)

          raise cache_read_error if cache_read_error && GitHub::ResilienceMixin.should_reraise_in_non_production?

          # Deserialize if we got a serialized value back from a store
          if !serialized_value.nil?
            begin
              cache_value = serializer.deserialize(T.unsafe(serialized_value))
            rescue => e
              raise e if GitHub::ResilienceMixin.should_reraise_in_non_production?

              # Corrupt entry — delete from all stores and treat as miss
              delete_from_all_stores(cache_key)
              cache_value = nil
              cache_source = :miss
            end
          end

          cache_hit = case cache_value
          when nil
            false
          else
            true
          end

          # Invoke cache_read_observer after cache read
          if cache_read_observer && extended_telemetry
            cache_read_observer_error = observe_cache_read(cache_read_observer, cache_hit, cache_value, cache_key_name, cache_key_id, serializer, cache_read_context)
          end
        end

        source_value = T.let(nil, T.nilable(T.type_parameter(:T)))
        expiry = T.let(nil, T.nilable(Numeric))
        expiry_error = T.let(nil, T.nilable(StandardError))
        data_source_timer = T.let(nil, T.nilable(::Timer))
        extended_telemetry_overhead_timer = T.let(nil, T.nilable(::Timer))
        extended_telemetry_overhead = extended_telemetry && (!return_cache_values || cache_hit) && !force_refresh

        if !cache_hit || !return_cache_values || extended_telemetry
          extended_telemetry_overhead_timer = ::Timer.start(cpu: true) if extended_telemetry_overhead
          data_source_timer = ::Timer.start(cpu: true)

          if resilience_error_types.empty? || GitHub::ResilienceMixin.should_reraise_in_non_production?
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

              if expiry
                serialized_source = serialize_value(serializer, source_value)
                if serialized_source
                  _, cache_write_strategy, cache_write_error, cache_write_store_tags = write_to_all_stores(cache_key, serialized_source, expiry)

                  raise cache_write_error if cache_write_error && GitHub::ResilienceMixin.should_reraise_in_non_production?
                end
              end
            end
          end

          if cache_hit && extended_telemetry && !used_fallback
            staleness, staleness_error = observe_staleness(
              staleness_observer,
              cache_value, source_value,
              cache_key_name, cache_key_id,
              serializer, staleness_context
            )
          end

          extended_telemetry_overhead_timer&.stop
        end

        return_cache_values && cache_hit ? cache_value : source_value
      ensure
        if store_configured?
          metric_tags = build_metric_tags(cache_key_name, method: method, store_tags: cache_read_store_tags || cache_write_store_tags || [])

          add_boolean_tag(metric_tags, :cache_enabled, enabled)
          if staleness_error
            add_metric_tag(metric_tags, "stale:error")
            add_error_tags(metric_tags, "staleness_error", staleness_error)
          else
            add_tristate_tag(metric_tags, :stale, staleness)
          end
          add_error_tags(metric_tags, "cache_read_observer_error", cache_read_observer_error) if cache_read_observer_error
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

          if expiry
            add_ttl_tag(metric_tags, expiry)
          end
          if expiry_error
            add_error_tags(metric_tags, "ttl_error", expiry_error)
          end

          if extended_telemetry && data_source_timer
            report_metric("github.remote_cache.data_source_time", data_source_timer.elapsed_ms(5), tags: metric_tags)
          end

          subtracted_timer = (extended_telemetry_overhead && extended_telemetry_overhead_timer) ? extended_telemetry_overhead_timer : nil

          timer.stop

          report_timer_metrics(timer, metric_tags, subtract_timer: subtracted_timer)
        end
      end

      # Fetches multiple values from the cache or computes them using the provided block.
      #
      # Reads through the store stack in order for all keys. Hits from later
      # stores are backfilled to earlier stores. The block receives cache key ids
      # for any remaining misses and should return a hash mapping those ids to
      # their computed values.
      sig do
        type_parameters(:T).
        params(
          cache_key_name: Symbol,
          cache_key_ids: T::Array[String],
          ttl: T.any(T.proc.params(value: T.type_parameter(:T)).returns(Integer), Integer),
          fallback: T.type_parameter(:T),
          resilience_error_types: T::Array[T.class_of(StandardError)],
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)],
          staleness_observer: T.nilable(GitHub::RemoteCache::StalenessObserver[T.type_parameter(:T)]),
          staleness_context: T.nilable(T::Hash[Symbol, T.untyped]),
          cache_read_observer: T.nilable(GitHub::RemoteCache::CacheReadObserver[T.type_parameter(:T)]),
          cache_read_context: T.nilable(T::Hash[Symbol, T.untyped]),
          enabled: T::Boolean,
          force_refresh: T::Boolean,
          rollout_mode: Client::RolloutMode,
          block: T.proc.params(cache_key_ids: T::Array[String]).returns(T::Hash[String, T.type_parameter(:T)]),
        ).returns(T::Hash[String, T.nilable(T.type_parameter(:T))])
      end
      def fetch_multi(
        cache_key_name:, cache_key_ids:,
        ttl:, fallback:, resilience_error_types:, serializer:,
        staleness_observer: nil, staleness_context: nil,
        cache_read_observer: nil, cache_read_context: nil,
        enabled: true, force_refresh: false,
        rollout_mode: Client::RolloutMode::ReturnCacheValueWithBaseTelemetry,
        &block
      )
        timer = ::Timer.start(cpu: true)

        force_refresh = true if @force_refresh_all

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
          return block.call(present_cache_key_ids) if resilience_error_types.empty? || GitHub::ResilienceMixin.should_reraise_in_non_production?

          return with_error_fallback(
            fallback: fallback_proc,
            allowed_error_types: resilience_error_types
          ) { block.call(present_cache_key_ids) }.value
        end

        used_fallback = T.let(false, T::Boolean)
        enabled = cache_key_name_enabled?(enabled, cache_key_name)

        # Return early if not enabled
        if !enabled
          return block.call(present_cache_key_ids) if resilience_error_types.empty? || GitHub::ResilienceMixin.should_reraise_in_non_production?

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

        # Fetch from cache (only if force_refresh is disabled)
        cache_key_ids_to_fetch_from_cache = present_cache_key_ids
        cache_key_ids_to_fetch_from_source_of_truth = T.let([], T::Array[String])
        cache_values = T.let(empty_hash.dup, T::Hash[String, T.type_parameter(:T)])
        cache_hits = T.let(empty_hash.dup, T::Hash[String, T::Boolean])
        cache_hit_count = T.let(0, Integer)
        cache_read_store_tags = T.let(empty_hash.dup, T::Hash[String, T::Array[String]])

        if !force_refresh && cache_key_ids_to_fetch_from_cache.any?
          full_cache_keys = cache_key_ids_to_fetch_from_cache.filter_map { |id| cache_keys[id] }
          cache_read_results, cache_read_store_tags = read_multi_through_stores(full_cache_keys)
          cache_read_observer_errors = T.let(empty_hash.dup, T::Hash[String, StandardError])

          cache_key_ids_to_fetch_from_cache.each do |cache_key_id|
            cache_key = cache_keys[cache_key_id]
            next unless cache_key

            serialized_value, source, error = cache_read_results[cache_key]
            raise error if error && GitHub::ResilienceMixin.should_reraise_in_non_production?

            # Deserialize if we got a hit with a present value
            deserialized_value = T.let(nil, T.nilable(T.type_parameter(:T)))
            if !serialized_value.nil?
              begin
                deserialized_value = serializer.deserialize(T.unsafe(serialized_value))
              rescue => e
                raise e if GitHub::ResilienceMixin.should_reraise_in_non_production?

                # Corrupt entry — delete from all stores and treat as miss
                delete_from_all_stores(cache_key)
                deserialized_value = nil
              end
            end

            cache_hit = case deserialized_value
            when nil
              cache_key_ids_to_fetch_from_source_of_truth << cache_key_id
              cache_hits[cache_key_id] = false
              false
            else
              cache_values[cache_key_id] = deserialized_value
              cache_hits[cache_key_id] = true
              cache_hit_count += 1
              true
            end

            # Invoke cache_read_observer after cache read for each key
            if cache_read_observer && extended_telemetry
              cache_read_observer_error = observe_cache_read(cache_read_observer, cache_hit, deserialized_value, cache_key_name, cache_key_id, serializer, cache_read_context)
              cache_read_observer_errors[cache_key_id] = cache_read_observer_error if cache_read_observer_error
            end
          end
        end

        all_cache_hits = cache_hit_count == cache_key_ids.size

        # Fetch from source of truth
        extended_telemetry_overhead_timer = T.let(nil, T.nilable(::Timer))
        extended_telemetry_overhead = extended_telemetry && (!return_cache_values || all_cache_hits) && !force_refresh

        if force_refresh || !return_cache_values || extended_telemetry || cache_key_ids_to_fetch_from_source_of_truth.any?
          source_values = T.let(nil, T.nilable(T::Hash[String, T.type_parameter(:T)]))

          cache_key_ids_to_fetch_from_source_of_truth = present_cache_key_ids if force_refresh || !return_cache_values || extended_telemetry

          extended_telemetry_overhead_timer = ::Timer.start(cpu: true) if extended_telemetry_overhead
          data_source_timer = T.let(::Timer.start(cpu: true), ::Timer)

          fallback_proc = -> do
            frozen_fallback = freeze_fallback_value(fallback, cache_key_name)
            cache_key_ids_to_fetch_from_source_of_truth.each_with_object(empty_hash.dup) do |cache_key_id, hash|
              hash[cache_key_id] = frozen_fallback
            end
          end

          if resilience_error_types.empty? || GitHub::ResilienceMixin.should_reraise_in_non_production?
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

          # Write back to cache for misses
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

              serialized = serialize_value(serializer, value)
              next unless serialized

              expiries[cache_key] = expiry
              values_to_write_to_cache[cache_key] = serialized
            end

            if values_to_write_to_cache.any?
              cache_write_results = write_multi_to_all_stores(values_to_write_to_cache, expires_in: expiries)

              if GitHub::ResilienceMixin.should_reraise_in_non_production?
                cache_write_results.each_value do |_, _, error|
                  raise error if error
                end
              end
            end
          end

          # Compute staleness
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
              staleness_results[cache_key_id] = observe_staleness(staleness_observer, cache_value, source_value, cache_key_name, cache_key_id, serializer, staleness_context)
            end
          end

          extended_telemetry_overhead_timer&.stop
        end

        # Construct final result hash
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
          metric_tags = build_metric_tags(cache_key_name, method: :fetch_multi)

          add_boolean_tag(metric_tags, :cache_enabled, enabled)
          add_boolean_tag(metric_tags, :force_refresh, force_refresh)
          add_rollout_mode_tag(metric_tags, rollout_mode)
          add_boolean_tag(metric_tags, :fallback, T.must(used_fallback))
          add_serializer_tag(metric_tags, serializer)
          add_num_keys_tag(metric_tags, cache_key_ids.size)

          if cache_keys
            cache_key_ids.each do |cache_key_id|
              per_key_metric_tags = metric_tags.dup

              if cache_key_ids_present[cache_key_id]
                add_tristate_tag(per_key_metric_tags, :cache_key_id_present, cache_key_ids_present[cache_key_id])
              end

              cache_key = cache_keys[cache_key_id]
              next unless cache_key

              if !cache_read_results.nil? && cache_hits && cache_read_results[cache_key]
                _, cache_source, cache_read_error = cache_read_results[cache_key]

                # Add store-specific tags for this key
                if key_store_tags = cache_read_store_tags[cache_key]
                  per_key_metric_tags.concat(key_store_tags)
                end

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
                staleness, staleness_error = staleness_results[cache_key_id]
                if staleness_error
                  add_metric_tag(per_key_metric_tags, "stale:error")
                  add_error_tags(per_key_metric_tags, "staleness_error", staleness_error)
                else
                  add_tristate_tag(per_key_metric_tags, :stale, staleness)
                end
              end

              if cache_read_observer_errors && cache_read_observer_errors[cache_key_id]
                cache_read_observer_error = cache_read_observer_errors[cache_key_id]
                if cache_read_observer_error
                  add_error_tags(per_key_metric_tags, "cache_read_observer_error", cache_read_observer_error)
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

          if cache_read_observer_errors && !cache_read_observer_errors.empty?
            first_cache_read_observer_error = cache_read_observer_errors.values.find { |error| error }
            add_error_tags(metric_tags, "cache_read_observer_error", first_cache_read_observer_error) if first_cache_read_observer_error
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

      # Stores a value directly in the cache without requiring a block.
      #
      # Serializes the value and writes to all stores in the stack.
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

        timer = ::Timer.start(cpu: true)
        enabled = cache_key_name_enabled?(enabled, cache_key_name)
        cache_key_id_present = cache_key_id_present?(cache_key_id)

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
        cache_write_store_tags = T.let(nil, T.nilable(T::Array[String]))

        if expiry
          serialized_value = serialize_value(serializer, value)
          if serialized_value
            _, cache_write_strategy, cache_write_error, cache_write_store_tags = write_to_all_stores(cache_key, serialized_value, expiry)
          end
        end

        report_store_metrics(
          timer:,
          cache_key_name:,
          serializer:,
          enabled:,
          cache_key_id_present:,
          store_tags: cache_write_store_tags || [],
          expiry:,
          expiry_error:,
          cache_write_strategy:,
          cache_write_error:,
        )
      end

      # Invalidates a cache entry by deleting it from all stores in the stack.
      sig do
        params(
          cache_key_name: Symbol,
          cache_key_id: String,
          event: T.nilable(String)
        ).void
      end
      def invalidate(cache_key_name:, cache_key_id:, event: nil)
        return if !store_configured?
        timer = ::Timer.start(cpu: true)

        cache_key_name_enabled = cache_key_name_enabled?(true, cache_key_name)
        cache_key_id_present = cache_key_id_present?(cache_key_id)
        return if !cache_key_id_present || !cache_key_name_enabled

        cache_key = build_cache_key(cache_key_name, cache_key_id)
        _cache_delete_success, cache_delete_strategy, cache_delete_error, cache_delete_store_tags = delete_from_all_stores(cache_key)
      ensure
        if store_configured?
          metric_tags = build_metric_tags(cache_key_name, method: :invalidate, store_tags: cache_delete_store_tags || [])

          add_event_tag(metric_tags, event) if event
          add_boolean_tag(metric_tags, :cache_enabled, T.must(cache_key_name_enabled))
          add_tristate_tag(metric_tags, :cache_key_id_present, cache_key_id_present)
          add_strategy_tag(metric_tags, :store_delete_strategy, cache_delete_strategy) if cache_delete_strategy
          add_error_tags(metric_tags, "store_delete_error", cache_delete_error) if cache_delete_error

          timer.stop

          report_timer_metrics(timer, metric_tags)
        end
      end

      # Invalidates multiple cache entries by deleting them from all stores.
      sig do
        params(
          cache_key_name: Symbol,
          cache_key_ids: T::Array[String],
          event: T.nilable(String)
        ).void
      end
      def invalidate_multi(cache_key_name:, cache_key_ids:, event: nil)
        return if !store_configured?
        timer = ::Timer.start(cpu: true)

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
            cache_delete_results = delete_multi_from_all_stores(cache_keys.values)
          rescue => e
            cache_delete_error = e
          end
        end
      ensure
        if store_configured?
          metric_tags = build_metric_tags(cache_key_name, method: :invalidate_multi)

          add_event_tag(metric_tags, event) if event
          add_boolean_tag(metric_tags, :cache_enabled, T.must(cache_key_name_enabled))

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

      private

      # ── Store stack operations ─────────────────────────────────────────────

      # Read through the store stack in order. On a hit from a later store,
      # backfill earlier stores so subsequent reads hit the fastest store.
      # Returns [value, source, error, store_metric_tags].
      sig { params(cache_key: String).returns([T.untyped, Symbol, T.nilable(Exception), T::Array[String]]) }
      def read_through_stores(cache_key)
        @stores.each_with_index do |store, index|
          value, source, error = store.read(cache_key)
          next if source == :miss

          # Backfill earlier stores
          if index > 0
            T.must(@stores[0...index]).each do |earlier_store|
              earlier_store.write(cache_key, value, expires_in: 0)
            end
          end

          return [value, source, error, store.base_metric_tags]
        end

        [nil, :miss, nil, T.must(@stores.last).base_metric_tags]
      end

      # Read multiple keys through the store stack, collecting hits and
      # passing remaining keys to the next store. Backfill earlier stores.
      # Returns [results_hash, store_tags_hash] where store_tags_hash maps
      # keys to the base_metric_tags of the store that served them.
      sig do
        params(cache_keys: T::Array[String]).returns(
          [T::Hash[String, [T.untyped, Symbol, T.nilable(Exception)]], T::Hash[String, T::Array[String]]]
        )
      end
      def read_multi_through_stores(cache_keys)
        results = T.let({}, T::Hash[String, [T.untyped, Symbol, T.nilable(Exception)]])
        store_tags = T.let({}, T::Hash[String, T::Array[String]])
        remaining_keys = T.let(Set.new(cache_keys), T::Set[String])

        @stores.each_with_index do |store, index|
          break if remaining_keys.empty?

          store_results = store.read_multi(remaining_keys.to_a)
          hits_for_backfill = T.let({}, T::Hash[String, T.untyped])
          tags = store.base_metric_tags

          store_results.each do |key, result_tuple|
            _value, source, _error = result_tuple
            if source != :miss
              results[key] = result_tuple
              store_tags[key] = tags
              remaining_keys.delete(key)
              hits_for_backfill[key] = result_tuple[0] if index > 0
            end
          end

          # Backfill earlier stores with hits from this store
          if hits_for_backfill.any? && index > 0
            expires_hash = hits_for_backfill.keys.each_with_object(T.let({}, T::Hash[String, Integer])) { |k, h| h[k] = 0 }
            T.must(@stores[0...index]).each do |earlier_store|
              earlier_store.write_multi(hits_for_backfill, expires_in: expires_hash)
            end
          end
        end

        # Add miss entries for remaining keys
        remaining_keys.each do |key|
          results[key] = [nil, :miss, nil]
        end

        [results, store_tags]
      end

      # Write to every store in the stack. Returns the result from the last
      # (most authoritative) store including its metric tags.
      sig { params(cache_key: String, serialized_value: T.untyped, expires_in: Integer).returns([T::Boolean, Symbol, T.nilable(Exception), T::Array[String]]) }
      def write_to_all_stores(cache_key, serialized_value, expires_in)
        last_result = T.let([false, :inline, nil], [T::Boolean, Symbol, T.nilable(Exception)])
        last_tags = T.let([], T::Array[String])
        @stores.each do |store|
          last_result = store.write(cache_key, serialized_value, expires_in: expires_in)
          last_tags = store.base_metric_tags
        end
        [*last_result, last_tags]
      end

      # Write multiple keys to every store in the stack.
      sig do
        params(
          keys_values: T::Hash[String, T.untyped],
          expires_in: T::Hash[String, Integer]
        ).returns(T::Hash[String, [T::Boolean, Symbol, T.nilable(Exception)]])
      end
      def write_multi_to_all_stores(keys_values, expires_in:)
        last_results = T.let({}, T::Hash[String, [T::Boolean, Symbol, T.nilable(Exception)]])
        @stores.each do |store|
          last_results = store.write_multi(keys_values, expires_in: expires_in)
        end
        last_results
      end

      # Delete from every store in the stack. Returns the result from the last store.
      sig { params(cache_key: String).returns([T::Boolean, Symbol, T.nilable(Exception), T::Array[String]]) }
      def delete_from_all_stores(cache_key)
        last_result = T.let([false, :inline, nil], [T::Boolean, Symbol, T.nilable(Exception)])
        last_tags = T.let([], T::Array[String])
        @stores.each do |store|
          last_result = store.delete(cache_key)
          last_tags = store.base_metric_tags
        end
        [*last_result, last_tags]
      end

      # Delete multiple keys from every store in the stack.
      sig { params(cache_keys: T::Array[String]).returns(T::Hash[String, [T::Boolean, Symbol, T.nilable(Exception)]]) }
      def delete_multi_from_all_stores(cache_keys)
        last_results = T.let({}, T::Hash[String, [T::Boolean, Symbol, T.nilable(Exception)]])
        @stores.each do |store|
          last_results = store.delete_multi(cache_keys)
        end
        last_results
      end

      # ── Serialization helpers ──────────────────────────────────────────────

      # Safely serialize a value, returning nil on failure.
      sig do
        type_parameters(:T)
        .params(
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)],
          value: T.type_parameter(:T)
        ).returns(T.untyped)
      end
      def serialize_value(serializer, value)
        serializer.serialize(T.unsafe(value))
      rescue => e
        raise e if GitHub::ResilienceMixin.should_reraise_in_non_production?

        nil
      end

      # ── Cache key helpers ──────────────────────────────────────────────────

      sig { params(cache_key_id: String).returns(T::Boolean) }
      def cache_key_id_present?(cache_key_id)
        !Client::NIL_CACHE_KEY_ID.equal?(cache_key_id)
      end

      sig { params(cache_key_name: Symbol, cache_key_id: String).returns(String) }
      def build_cache_key(cache_key_name, cache_key_id)
        suffix = "#{cache_key_name}/#{cache_key_id}"
        return suffix if @legacy_key_format || @namespace.empty?

        "#{@namespace}:#{suffix}"
      end

      # ── Feature flag / rollout helpers ─────────────────────────────────────

      sig { params(enabled: T::Boolean, cache_key_name: Symbol).returns(T::Boolean) }
      def cache_key_name_enabled?(enabled, cache_key_name)
        enabled && !FeatureFlag.vexi.enabled?(:remote_cache_disable_for_cache_key_name, self.class.cache_key_name_vexi_actor(cache_key_name), default: false)
      end

      sig { params(rollout_mode: Client::RolloutMode, cache_key_name: Symbol).returns([T::Boolean, T::Boolean, Client::RolloutMode]) }
      def determine_rollout_mode(rollout_mode, cache_key_name)
        effective_rollout_mode = if FeatureFlag.vexi.enabled?(:remote_cache_return_source_value_with_extended_telemetry_for_cache_key_name, self.class.cache_key_name_vexi_actor(cache_key_name), default: false)
          Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
        else
          rollout_mode
        end

        case effective_rollout_mode
        when Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
          return_cache_values = false
          extended_telemetry = true
        when Client::RolloutMode::ReturnCacheValueWithExtendedTelemetry
          return_cache_values = true
          extended_telemetry = true
        when Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
          return_cache_values = true
          extended_telemetry = false
        end

        [return_cache_values, extended_telemetry, effective_rollout_mode]
      end

      # ── TTL / fallback helpers ─────────────────────────────────────────────

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
            raise e if GitHub::ResilienceMixin.should_reraise_in_non_production?

            error = e
            nil
          end
        end

        if expiry && expiry <= 0
          expiry = nil
          error = Client::InvalidTtlValueError.new("Expiry must be greater than 0")
        end

        expiry = expiry && expiry > Client::MAX_TTL ? Client::MAX_TTL : expiry

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
        rescue TypeError
          # Ignore freezing errors for certain types
        end

        value
      end

      # ── Observer helpers ───────────────────────────────────────────────────

      sig do
        type_parameters(:T)
        .params(
          staleness_observer: T.nilable(GitHub::RemoteCache::StalenessObserver[T.type_parameter(:T)]),
          cache_value: T.type_parameter(:T),
          source_value: T.type_parameter(:T),
          cache_key_name: Symbol,
          cache_key_id: String,
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)],
          staleness_context: T.nilable(T::Hash[Symbol, T.untyped])
        ).returns([T::Boolean, T.nilable(StandardError)])
      end
      def observe_staleness(staleness_observer, cache_value, source_value, cache_key_name, cache_key_id, serializer, staleness_context)
        return [false, Client::UnimplementedStalenessObserverError.new] if staleness_observer.nil?
        staleness_context = (staleness_context || {}).merge({ cache_key_name:, cache_key_id:, namespace:, serializer: })
        stale = staleness_observer.stale?(cache_value, source_value, staleness_context)
        [stale, nil]
      rescue => e
        raise e if GitHub::ResilienceMixin.should_reraise_in_non_production?

        [false, e]
      end

      sig do
        type_parameters(:T)
        .params(
          cache_read_observer: T.nilable(GitHub::RemoteCache::CacheReadObserver[T.type_parameter(:T)]),
          cache_hit: T.any(T::Boolean, Symbol),
          cache_value: T.nilable(T.type_parameter(:T)),
          cache_key_name: Symbol,
          cache_key_id: String,
          serializer: GitHub::RemoteCache::Serializer[T.type_parameter(:T)],
          cache_read_context: T.nilable(T::Hash[Symbol, T.untyped])
        ).returns(T.nilable(StandardError))
      end
      def observe_cache_read(cache_read_observer, cache_hit, cache_value, cache_key_name, cache_key_id, serializer, cache_read_context)
        return if cache_read_observer.nil?
        context = (cache_read_context || {}).merge({ cache_key_name:, cache_key_id:, namespace:, serializer: })
        cache_read_observer.observe_cache_read(cache_hit, cache_value, context)
        nil
      rescue => e
        raise e if GitHub::ResilienceMixin.should_reraise_in_non_production?

        e
      end

      # ── Metric helpers ─────────────────────────────────────────────────────

      sig { params(cache_key_name: T.nilable(Symbol), method: T.nilable(Symbol), store_tags: T::Array[String]).returns(T::Array[String]) }
      def build_metric_tags(cache_key_name, method: nil, store_tags: [])
        tags = T.let(["namespace:#{@namespace}"], T::Array[String])
        tags.concat(store_tags) if store_tags.any?
        tags << "cache_key_name:#{cache_key_name}" if cache_key_name
        tags << "remote_cache_method:#{method}" if method

        if GitHub.context[:remote_call_source_datadog_tags]
          tags.concat(GitHub.context[:remote_call_source_datadog_tags])
        end

        tags.push(GitHub::Dogstats::DEFAULT_HOST_TAG, GitHub::TaggingHelper.site_tag, GitHub::TaggingHelper.region_tag, GitHub::TaggingHelper.stamp_tag)

        tags
      end

      sig { params(metric_name: String, value: Numeric, tags: T::Array[String]).void }
      def report_metric(metric_name, value, tags:)
        GitHub.dogstats.distribution(metric_name, value, tags: tags)
      end

      sig do
        params(
          timer: ::Timer,
          cache_key_name: Symbol,
          serializer: GitHub::RemoteCache::Serializer[T.untyped],
          enabled: T::Boolean,
          cache_key_id_present: T::Boolean,
          store_tags: T::Array[String],
          expiry: T.nilable(Numeric),
          expiry_error: T.nilable(StandardError),
          cache_write_strategy: T.nilable(Symbol),
          cache_write_error: T.nilable(Exception)
        ).void
      end
      def report_store_metrics(
        timer:, cache_key_name:, serializer:, enabled:, cache_key_id_present:,
        store_tags: [], expiry: nil, expiry_error: nil, cache_write_strategy: nil, cache_write_error: nil
      )
        metric_tags = build_metric_tags(cache_key_name, method: :store, store_tags:)

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

      sig { params(metric_tags: T::Array[String], rollout_mode: Client::RolloutMode).void }
      def add_rollout_mode_tag(metric_tags, rollout_mode)
        metric_tags << case rollout_mode
        when Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
          "rollout_mode:return_source_value_with_extended_telemetry"
        when Client::RolloutMode::ReturnCacheValueWithExtendedTelemetry
          "rollout_mode:return_cache_value_with_extended_telemetry"
        when Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
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
