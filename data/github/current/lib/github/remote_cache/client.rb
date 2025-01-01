# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    class Client
      include GitHub::ResilienceMixin

      class InvalidTtlValueError < StandardError; end

      MAX_TTL = T.let(1.day.seconds, Integer)
      NIL_CACHE_KEY_ID = T.let(String.new.freeze, String)

      sig { params(store: T.nilable(GitHub::RemoteCache::Store)).void }
      def initialize(store)
        @store = T.let(store, T.nilable(GitHub::RemoteCache::Store))
        @base_metric_tags = T.let(nil, T.nilable(T::Array[String]))
      end

      # Fetches a value from the cache or computes it using the provided block, with database
      # error handling and fallback logic.
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
      # The `shadow` parameter, when true, always reads and writes the cache, always reads from the
      # database, returns the database value, and reports a dogstats metric tagged with whether the
      # cache was stale.
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
      #     staleness: ->(cache_value, source_value) { (cache_value - source_value).abs > 10 },
      #     fallback: 0,
      #     shadow: true
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
          enabled: T::Boolean,
          shadow: T::Boolean,
          method: Symbol,
          force_refresh: T::Boolean,
          block: T.proc.returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
      end
      def fetch(
        cache_key_name:, cache_key_id:,
        ttl:, fallback:, resilience_error_types:, serializer:,
        enabled: true, shadow: false, method: :fetch, force_refresh: false,
        &block
      )
        if !store_configured?
          return with_error_fallback(
            fallback: fallback,
            allowed_error_types: resilience_error_types,
            &block
          ).value
        end

        timer = ::Timer.start
        data_source_timer = T.let(nil, T.nilable(::Timer))
        shadow_mode_timer = T.let(nil, T.nilable(::Timer))

        cache_key = build_cache_key(cache_key_name, cache_key_id)
        metric_tags = build_metric_tags(cache_key_name, method: method)

        cache_value = T.let(nil, T.nilable(T.type_parameter(:T)))
        source_value = T.let(nil, T.nilable(T.type_parameter(:T)))
        is_stale = T.let(false, T::Boolean)
        result = T.let(nil, T.nilable(T.type_parameter(:T)))
        used_fallback = T.let(false, T::Boolean)
        expiry = T.let(nil, T.nilable(Numeric))
        mismatches = T.let(nil, T.nilable(T::Array[String]))

        cache_key_id_present = cache_key_id_present?(cache_key_id)

        if !cache_key_id_present || !enabled
          lookup_result = with_error_fallback(
            fallback: fallback,
            allowed_error_types: resilience_error_types,
            &block
          )
          used_fallback = lookup_result.used_fallback?
          return lookup_result.value
        end

        if !force_refresh
          cache_value, cache_source, cache_read_error = read_cache(cache_key, serializer)
          cache_hit = case cache_value
          when nil
            false
          else
            true
          end
        end

        if !cache_hit || shadow
          shadow_mode_timer = ::Timer.start
          data_source_timer = ::Timer.start

          fallthrough_result = with_error_fallback(
            fallback: fallback,
            allowed_error_types: resilience_error_types,
            &block
          )
          data_source_timer.stop
          used_fallback = fallthrough_result.used_fallback?
          source_value = fallthrough_result.value

          if !used_fallback && !cache_hit
            case source_value
            when nil
            else
              expiry, expiry_error = calculate_expiry(ttl, source_value)
              _, cache_write_error = write_cache(cache_key, source_value, serializer, expiry) if expiry
            end
          end

          staleness, staleness_error, mismatches = staleness_compare(serializer, cache_value, source_value) if cache_hit && shadow && !used_fallback

          shadow_mode_timer.stop

          result = source_value
        else
          result = cache_value
        end
      ensure
        if store_configured?
          metric_tags ||= []

          metric_tags << (enabled ? "cache_enabled:true" : "cache_enabled:false")
          metric_tags.push("stale:error", "staleness_error:#{staleness_error.class.name}") if staleness_error
          metric_tags << (staleness ? "stale:true" : "stale:false") if !staleness.nil?
          metric_tags << "store_read_source:#{cache_source}" if cache_source
          metric_tags << (force_refresh ? "force_refresh:true" : "force_refresh:false")

          if cache_read_error
            metric_tags << "store_read_error:#{cache_read_error.class.name}"
            metric_tags << "store_read_error_cause:#{cache_read_error.cause.class.name}" if cache_read_error.cause
          end

          if cache_write_error
            metric_tags << "store_write_error:#{cache_write_error.class.name}"
            metric_tags << "store_write_error_cause:#{cache_write_error.cause.class.name}" if cache_write_error.cause
          end

          metric_tags << (cache_hit ? "cache_hit:true" : "cache_hit:false") if !cache_hit.nil?
          metric_tags << (shadow ? "shadow:true" : "shadow:false")
          metric_tags << (used_fallback ? "fallback:true" : "fallback:false")
          metric_tags << "serializer:#{T.unsafe(serializer).name}"
          metric_tags << (cache_key_id_present ? "cache_key_id_present:true" : "cache_key_id_present:false") if T.unsafe(!cache_key_id_present.nil?)

          expiry, expiry_error = calculate_expiry(ttl, cache_value) if expiry.nil? && cache_hit
          metric_tags << "ttl_error:#{expiry_error.class.name}" if expiry_error
          metric_tags << "cache_ttl:#{expiry}" if expiry

          if mismatches.present?
            GitHub.logger.info("cache mismatches detected: #{mismatches.join(', ')}", { "gh.cache.namespace": namespace, "gh.cache.key": cache_key })
            mismatches.each do |field|
              metric_tags << "stale_field:#{field}"
            end
          end

          timer.stop
          time = timer.elapsed_ms(5)
          cpu_time = timer.elapsed_cpu_ms(5)
          idle_time = timer.elapsed_idle_ms(5)

          # The metric time should represent non-shadow mode to confidently assess the impact of adding
          # cache calls to an existing data access point. In shadow mode, we always read from the
          # database, so we need to deduct the database time in case of a cache hit.

          if shadow
            report_metric("github.remote_cache.data_source_time", data_source_timer.elapsed_ms(5), tags: metric_tags) if data_source_timer

            if cache_hit && shadow_mode_timer
              time -= shadow_mode_timer.elapsed_ms(5)
              cpu_time -= shadow_mode_timer.elapsed_cpu_ms(5)
              idle_time -= shadow_mode_timer.elapsed_idle_ms(5)
            end
          end

          report_metric("github.remote_cache.time", time, tags: metric_tags)
          report_metric("github.remote_cache.cpu_time", cpu_time, tags: metric_tags)
          report_metric("github.remote_cache.idle_time", idle_time, tags: metric_tags)
        end
      end

      # Invalidates a cache entry by its name and id.
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

        cache_key = build_cache_key(cache_key_name, cache_key_id)
        metric_tags = build_metric_tags(cache_key_name, method: :invalidate)
        metric_tags << "event:#{event}" if event

        cache_key_id_present = cache_key_id_present?(cache_key_id)
        return if !cache_key_id_present

        _, cache_delete_error = T.must(@store).delete(cache_key)
      ensure
        if store_configured?
          metric_tags ||= []

          metric_tags << (cache_key_id_present ? "cache_key_id_present:true" : "cache_key_id_present:false") if T.unsafe(!cache_key_id_present.nil?)

          if cache_delete_error
            metric_tags << "store_delete_error:#{cache_delete_error.class.name}"
            metric_tags << "store_delete_error_cause:#{cache_delete_error.cause.class.name}" if cache_delete_error.cause
          end

          timer.stop

          report_metric("github.remote_cache.time", timer.elapsed_ms(5), tags: metric_tags)
        end
      end

      sig { returns(T::Boolean) }
      def store_configured?
        @store != nil
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
        ).returns([T::Boolean, T.nilable(Exception)])
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
          cache_value: T.type_parameter(:T),
          source_value: T.type_parameter(:T)
        ).returns([T::Boolean, T.nilable(StandardError), T::Array[String]])
      end
      def staleness_compare(serializer, cache_value, source_value)
        comparison = serializer.compare(cache_value, source_value)
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

      sig { returns(T::Array[String]) }
      def base_metric_tags
        return @base_metric_tags if @base_metric_tags

        tags = ["namespace:#{namespace}"]
        tags.push("redis_url:#{@store.redis_url}", "redis_cluster:#{@store.redis_cluster}") if @store

        @base_metric_tags = tags.freeze
      end

      sig { params(cache_key_name: T.nilable(Symbol), method: T.nilable(Symbol)).returns(T::Array[String]) }
      def build_metric_tags(cache_key_name, method: nil)
        tags = base_metric_tags.dup
        tags << "cache_key_name:#{cache_key_name}" if cache_key_name
        tags << "method:#{method}" if method

        app_worker_id = GitHub.app_worker_id
        app_worker_actor = GitHub::VexiAppWorker.new(app_worker_id)
        if FeatureFlag.vexi.enabled?(:remote_cache_app_worker_id_tag, app_worker_actor, default: false)
          tags << "app_worker_id:#{app_worker_id}"

          if @store.is_a?(GitHub::RemoteCache::Store) && FeatureFlag.vexi.enabled?(:remote_cache_redis_client_object_id_tag, app_worker_actor, default: false)
            store = T.let(@store, GitHub::RemoteCache::Store)
            # For our custom store, we don't expose the Redis client directly for security
            # Instead, we can use the store's object_id as a proxy metric
            store_object_id = store.object_id
            tags << "store_object_id:#{store_object_id}"
          end
        end

        if FeatureFlag.vexi.enabled?(:remote_cache_controller_tags, app_worker_actor, default: false)
          if GitHub.context[:remote_call_source_datadog_tags]
            tags.concat(GitHub.context[:remote_call_source_datadog_tags])
          end
        end

        tags
      end

      sig { params(metric_name: String, value: Numeric, tags: T::Array[String]).void }
      def report_metric(metric_name, value, tags:)
        GitHub.dogstats.distribution(metric_name, value, tags: tags)
      end
    end
  end
end
