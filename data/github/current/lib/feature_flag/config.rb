# typed: strict
# frozen_string_literal: true

require "active_support/notifications"
require "feature_management/current_user"
require "feature_management/start_time"
require "feature_flags_common/custom_gates"
require "vexi"
require "vexi/adapters/file_adapter"
require "vexi/adapters/in_memory_adapter"
require "vexi/adapters/monolith_optimized_feature_flag_data_adapter"
require "feature_flag/cache/memcached"
require "feature_flag/cache/test"
require "vexi/caches/in_memory"
require "vexi/custom_gates_evaluators/serial_gate_and_actor_evaluator"
require_relative "./all_features"
require_relative "./i_feature_target"
require_relative "./cache"

module FeatureFlag
  SLOW_PRELOAD_THRESHOLD_MS = 100

  class Config
    extend T::Helpers

    DEFAULT_OPEN_TIMEOUT = 0.1 # 100ms
    DEFAULT_REQUEST_TIMEOUT = 0.1 # 100ms; per request
    DEFAULT_TIMEOUT = 0.5 # 500ms; across all retries and backoff
    DEFAULT_ISTIO_OPEN_TIMEOUT = 0.025 # 25ms
    DEFAULT_ISTIO_REQUEST_TIMEOUT = 0.025 # 25ms; per request
    DEFAULT_ISTIO_TIMEOUT = 0.125 # 125ms; across all retries and backoff
    DEFAULT_MAX_RETRIES = 2 # Retry attempts after the initial request
    TELEMETRY_PREFIX = "gh.vexi"

    ADAPTER_DEFAULT_DISABLED = "disabled_by_default"
    ADAPTER_DEFAULT_ENABLED = "enabled_by_default"
    ADAPTER_EXCLUSION_LIST_DISABLED = "disabled"
    ADAPTER_EXCLUSION_LIST_ENABLED = "enabled"

    CACHE_FEATURE_FLAG_KEY_PREFIX = "vexi:ff:"
    CACHE_SEGMENT_KEY_PREFIX = "vexi:sg:"

    sig { returns(T.nilable(Vexi::Adapters::InMemoryAdapter)) }
    attr_reader :vexi_test_adapter

    sig { returns(T.nilable(FeatureFlag::Cache::IMemcachedClient)) }
    attr_reader :cache_client

    sig { void }
    def initialize
      @adapter = T.let(Vexi::Adapters::InMemoryAdapter.new(Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault), Vexi::Adapter)
      @adapter_circuit_breaker_config = T.let(nil, T.nilable(Vexi::CircuitBreakerConfig))
      @cache_client = T.let(nil, T.nilable(FeatureFlag::Cache::IMemcachedClient))
      @cache = T.let(nil, T.nilable(Vexi::Cache))
      @cache_ttl = T.let(30, Integer)
      @cache_not_found_ttl = T.let(30, Integer)
      @vexi_test_adapter = T.let(nil, T.nilable(Vexi::Adapters::InMemoryAdapter))

      @logger = T.let(GitHub::Telemetry::Logs.logger("Vexi"), SemanticLogger::Logger)
      @logging_context = T.let({}, T::Hash[String, String])

      configure_observability
      configure_adapter

      Vexi.configure do |builder|
        builder.adapter.custom(@adapter)
        builder.custom_gates_evaluator.serial_gate_and_actor_evaluator(custom_gates)

        if ENV["DISABLE_VEXI_ADAPTER_BREAKER"] != "1"
          builder.circuit_breaker.with_adapter_circuit_breaker(@adapter_circuit_breaker_config)
        end

        if @cache != nil
          builder.cache.custom(@cache, @cache_ttl, @cache_not_found_ttl, CACHE_FEATURE_FLAG_KEY_PREFIX, CACHE_SEGMENT_KEY_PREFIX)
        end
      end

      GitHub.logger.info("Vexi Configured", @logging_context.merge({
        "#{TELEMETRY_PREFIX}.adapter" => vexi_instance.configuration_context[:adapter],
        "#{TELEMETRY_PREFIX}.cache" => vexi_instance.configuration_context[:cache],
        "#{TELEMETRY_PREFIX}.custom_gate_evaluator" => vexi_instance.configuration_context[:custom_gate_evaluator],
        "#{TELEMETRY_PREFIX}.version" => vexi_instance.configuration_context[:version],
      }))
    end

    sig { returns(Vexi::Client) }
    def vexi_instance
      Vexi.instance
    end

    sig { returns(T::Hash[String, T.proc.params(feature_name: String, actor: T.any(String, Vexi::Actor)).returns(T::Boolean)]) }
    def custom_gates
      if GitHub.enterprise? && !GitHub.multi_tenant_enterprise?
        return {}
      end

      wrapped_gates = T.let({}, T::Hash[String, T.proc.params(feature_name: String, actor: T.any(String, Vexi::Actor)).returns(T::Boolean)])
      if !GitHub.multi_tenant_enterprise? && !GitHub.enterprise?
        FeatureFlagsCommon::CustomGates::CUSTOM_GATES.each do |custom_gate, gate_proc|
          wrapped_gates[custom_gate] = proc do |feature_name, actor|
            if actor.is_a?(String)
              actor = GitHub::VexiActor.from_vexi_id(actor)
            end
            gate_proc.call(actor, feature_name)
          end
        end
      end

      wrapped_gates
    end

    private

    sig { void }
    def configure_adapter
      if GitHub::AppEnvironment.development?
        configure_development
      elsif GitHub::AppEnvironment.test?
        configure_test
      elsif ENV["GITHUB_CI"]
        configure_ci
      elsif GitHub.employee_unicorn? || GitHub.review_lab? || GitHub.staff_host?
        configure_review_lab
      elsif GitHub.enterprise? && !GitHub.multi_tenant_enterprise?
        configure_ghes
      else
        configure_production
      end
    end

    sig { void }
    def configure_development
      if ENV["VEXI_E2E_ENABLED"] == "1"
        url = GitHub.feature_management_feature_flag_data_url
        ffd_con = connection(url, GitHub.feature_management_feature_flag_data_checks_hmac_shared_key, "feature_flag_data")
        @adapter = Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(ffd_con)
        @cache_client = FeatureFlag::Cache::MemcachedClientWithFailover.new
        # Note: This has to be configured after the client is constructed, as this logger is incompatible with the info call done in the
        # constructor of ::Memcached::Rails. Setting it after similar to how it is done for GitHub.cache (although there they use a separate initializer).
        @cache_client.logger = GitHub::Logger
        @cache = FeatureFlag::Cache::Memcached.new(@cache_client)
        @cache_ttl = 30
        @cache_not_found_ttl = 30

        @logging_context = {
          "#{TELEMETRY_PREFIX}.configured_mode" => "development-e2e",
          "#{TELEMETRY_PREFIX}.adapter.feature_flag_data_url" => url,
        }
      elsif ENV["FM_LITE"]
        # Local development (fm-lite service)
        url = GitHub.feature_management_feature_flag_data_url
        conn = connection(url, "", "feature_management_lite")
        @adapter = Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(conn)
        @cache_client = FeatureFlag::Cache::MemcachedClientWithFailover.new
        # Note: This has to be configured after the client is constructed, as this logger is incompatible with the info call done in the
        # constructor of ::Memcached::Rails. Setting it after similar to how it is done for GitHub.cache (although there they use a separate initializer).
        @cache_client.logger = GitHub::Logger
        @cache = FeatureFlag::Cache::Memcached.new(@cache_client)
        @cache_ttl = 10
        @cache_not_found_ttl = 10

        @logging_context = {
          "#{TELEMETRY_PREFIX}.configured_mode" => "development-fm-lite",
          "#{TELEMETRY_PREFIX}.adapter.feature_flag_data_url" => url,
        }
      else
        # Local development (in memory adapter)
        @adapter = Vexi::Adapters::InMemoryAdapter.new(Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault)

        @logging_context = {
          "#{TELEMETRY_PREFIX}.configured_mode" => "development-in-memory",
          "#{TELEMETRY_PREFIX}.adapter.mode" => ADAPTER_DEFAULT_DISABLED,
        }
      end
    end

    sig { void }
    def configure_test
      # The minitest tests run their fixtures before the setup step happens. The file /workspaces/github/lib/github/goomba/warp_pipe.rb
      # preloads flags and is used when creating fixtures. Since memoization is configured in the setup step for tests,
      # it won't be configured for the fixtures. This causes lots of test failures. So, we are configure a cache that
      # will not cause state bleed between tests to prevent failures with preloads when used with fixtures.
      @cache = FeatureFlag::Cache::Test.new
      if ENV["FM_LITE_SYNC_ENABLED"] == "1"
        # Local development (fm-lite service)
        url = GitHub.feature_management_feature_flag_data_url
        conn = connection(url, "", "feature_management_lite")
        @adapter = Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(conn)

        @logging_context = {
          "#{TELEMETRY_PREFIX}.configured_mode" => "test-fm-lite",
          "#{TELEMETRY_PREFIX}.adapter.feature_flag_data_url" => url,
        }
      elsif ENV["TEST_ALL_FEATURES"] && !ENV["TEST_TIMERD"]
        # All features CI (constant adapter in all enabled mode)
        exception_list = T.let(FeatureFlag::AllFeatures.exclusion_list.map { |f| f.to_s }, T::Array[String])
        @adapter = Vexi::Adapters::InMemoryAdapter.new(Vexi::Adapters::InMemoryAdapterMode::EnabledByDefault, exception_feature_flags: exception_list)

        @logging_context = {
          "#{TELEMETRY_PREFIX}.configured_mode" => "all_enabled_unit_tests",
          "#{TELEMETRY_PREFIX}.adapter.mode" => ADAPTER_DEFAULT_ENABLED,
          "#{TELEMETRY_PREFIX}.adapter.exclusion_list" => ADAPTER_EXCLUSION_LIST_ENABLED,
        }
      else
        # Unit tests (constant adapter in all disabled mode)
        @adapter = Vexi::Adapters::InMemoryAdapter.new(Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault)

        @logging_context = {
          "#{TELEMETRY_PREFIX}.configured_mode" => "all_disabled_unit_tests",
          "#{TELEMETRY_PREFIX}.adapter.mode" => ADAPTER_DEFAULT_DISABLED,
          "#{TELEMETRY_PREFIX}.adapter.exclusion_list" => ADAPTER_EXCLUSION_LIST_DISABLED,
        }
      end
      @vexi_test_adapter = @adapter
    end

    sig { void }
    def configure_ci
      # The minitest tests run their fixtures before the setup step happens. The file /workspaces/github/lib/github/goomba/warp_pipe.rb
      # preloads flags and is used when creating fixtures. Since memoization is configured in the setup step for tests,
      # it won't be configured for the fixtures. This causes lots of test failures. So, we are configure a cache that
      # will not cause state bleed between tests to prevent failures with preloads when used with fixtures.
      @cache = FeatureFlag::Cache::Test.new
      if ENV["TEST_ALL_FEATURES"] && !ENV["TEST_TIMERD"]
        # All features CI (constant adapter in all enabled mode)
        exception_list = T.let(FeatureFlag::AllFeatures.exclusion_list.map { |f| f.to_s }, T::Array[String])
        @adapter = Vexi::Adapters::InMemoryAdapter.new(Vexi::Adapters::InMemoryAdapterMode::EnabledByDefault, exception_feature_flags: exception_list)

        @logging_context = {
          "#{TELEMETRY_PREFIX}.configured_mode" => "all_enabled_ci",
          "#{TELEMETRY_PREFIX}.adapter.mode" => ADAPTER_DEFAULT_ENABLED,
          "#{TELEMETRY_PREFIX}.adapter.exclusion_list" => ADAPTER_EXCLUSION_LIST_ENABLED,
        }
      else
        # Unit tests / CI (constant adapter in all disabled mode)
        @adapter = Vexi::Adapters::InMemoryAdapter.new(Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault)

        @logging_context = {
          "#{TELEMETRY_PREFIX}.configured_mode" => "all_disabled_ci",
          "#{TELEMETRY_PREFIX}.adapter.mode" => ADAPTER_DEFAULT_DISABLED,
          "#{TELEMETRY_PREFIX}.adapter.exclusion_list" => ADAPTER_EXCLUSION_LIST_DISABLED,
        }
      end
      @vexi_test_adapter = @adapter
    end

    sig { void }
    def configure_review_lab
      # Review lab (monolith optimized feature flag data hub adapter with caching and circuit breakers)
      url = GitHub.feature_management_feature_flag_data_url
      ffd_con = connection(url, GitHub.feature_management_feature_flag_data_checks_hmac_shared_key, "feature_flag_data")
      @adapter = Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(ffd_con)
      @cache_client = FeatureFlag::Cache::MemcachedClientWithFailover.new
      # Note: This has to be configured after the client is constructed, as this logger is incompatible with the info call done in the
      # constructor of ::Memcached::Rails. Setting it after similar to how it is done for GitHub.cache (although there they use a separate initializer).
      @cache_client.logger = GitHub::Logger
      @cache = FeatureFlag::Cache::Memcached.new(@cache_client)
      @cache_ttl = 120
      @cache_not_found_ttl = 120

      @logging_context = {
        "#{TELEMETRY_PREFIX}.configured_mode" => "review_lab",
        "#{TELEMETRY_PREFIX}.adapter.feature_flag_data_url" => url,
      }

      @adapter_circuit_breaker_config = Vexi::CircuitBreakerConfig.new(
        error_threshold_percentage: 20,
        request_volume_threshold: 10,
        window_size_in_seconds: 30,
        bucket_size_in_seconds: 3,
        sleep_window_seconds: 5
      )
    end

    sig { void }
    def configure_production
      # Production (monolith optimized feature flag data adapter with caching and circuit breakers)
      url = GitHub.feature_management_feature_flag_data_url
      ffd_con = connection(url, GitHub.feature_management_feature_flag_data_checks_hmac_shared_key, "feature_flag_data")
      @adapter = Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(ffd_con)
      @cache_client = FeatureFlag::Cache::MemcachedClientWithFailover.new
      # Note: This has to be configured after the client is constructed, as this logger is incompatible with the info call done in the
      # constructor of ::Memcached::Rails. Setting it after similar to how it is done for GitHub.cache (although there they use a separate initializer).
      @cache_client.logger = GitHub::Logger
      @cache = FeatureFlag::Cache::Memcached.new(@cache_client)
      @cache_ttl = 0 # Never expire
      @cache_not_found_ttl = 604800

      @logging_context = {
        "#{TELEMETRY_PREFIX}.configured_mode" => "production",
        "#{TELEMETRY_PREFIX}.adapter.feature_flag_data_url" => url,
      }

      @adapter_circuit_breaker_config = Vexi::CircuitBreakerConfig.new(
        error_threshold_percentage: 10,
        request_volume_threshold: 50,
        window_size_in_seconds: 30,
        bucket_size_in_seconds: 3,
        sleep_window_seconds: 5
      )
    end

    sig { void }
    def configure_ghes
      @adapter = Vexi::Adapters::InMemoryAdapter.new(Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault)

      @logging_context = {
        "#{TELEMETRY_PREFIX}.configured_mode" => "ghes",
        "#{TELEMETRY_PREFIX}.adapter.mode" => ADAPTER_DEFAULT_DISABLED,
        "#{TELEMETRY_PREFIX}.adapter.exclusion_list" => ADAPTER_EXCLUSION_LIST_DISABLED,
      }
    end

    sig { void }
    def configure_observability
      # Vexi enabled? durations
      ActiveSupport::Notifications.subscribe("vexi.is_enabled.duration") do |event|
        payload = event.payload
        operation = payload[:operation]
        feature_flag_name = payload[:feature_flag_name]
        caching_enabled = payload.dig(:config, :caching_enabled)
        memoization_enabled = payload.dig(:config, :memoization_enabled)
        vexi_version = payload.dig(:config, :vexi_version)

        measured_duration_with_custom_gates_ms = (payload[:measured_finish].to_f - payload[:measured_start].to_f) * 1000
        custom_gates_duration_ms = (payload.dig(:custom_gates, :measured_finish).to_f - payload.dig(:custom_gates, :measured_start).to_f) * 1000
        measured_duration_ms = measured_duration_with_custom_gates_ms - custom_gates_duration_ms

        custom_gates_evaluator_executed = payload.has_key?(:"custom_gates")
        fallback_evaluator_executed = payload.has_key?(:"fallback_evaluator")
        feature_flag_adapter_error_present = payload.has_key?(:"feature_flag.adapter.error")
        segment_adapter_error_present = payload.has_key?(:"segment.adapter.error")
        custom_gate_evaluator_error_present = payload.has_key?(:"custom_gate_evaluator.error")

        feature_flag_cache_get_error_present = payload.has_key?(:"feature_flag.cache.fetch.error")
        feature_flag_cache_set_error_present = payload.has_key?(:"feature_flag.cache.set.error")

        feature_flag_adapter_get_circuit_breaker_open = payload.has_key?(:"feature_flag.adapter.fetch.circuit_breaker_open")

        # Right now is_enabled only fetches one feature flag at a time
        feature_flags_count = 1
        feature_flag_memoization_hit_count = payload.dig(:"feature_flag.memoization.fetch", :entities_count).to_i
        feature_flag_memoization_miss_count = feature_flags_count - feature_flag_memoization_hit_count
        feature_flag_cache_hit_count = payload.dig(:"feature_flag.cache.fetch", :entities_count).to_i
        feature_flag_cache_miss_count = feature_flags_count - feature_flag_memoization_hit_count - feature_flag_cache_hit_count
        feature_flag_adapter_hit_count = payload.dig(:"feature_flag.adapter.fetch", :entities_count).to_i

        nil_actors = payload.has_key?(:"nil_actor_indices")
        invalid_actors = payload.has_key?(:"invalid_actor_type_indices")

        feature_flag_source = if feature_flag_memoization_hit_count >= 1
          "memoization"
        elsif feature_flag_cache_hit_count >= 1
          "cache"
        else
          "adapter"
        end

        # Ignore segments since we currently don't have any segments right now.

        operation_duration_tags = [
          "result:#{payload[:result]}",
          "feature_flag.name:#{feature_flag_name}",
          "number_of_actors_being_checked:#{bucketed_actors_count(payload[:number_of_actors_being_checked])}",

          "config.memoization.enabled:#{memoization_enabled}",
          "config.caching.enabled:#{caching_enabled}",
          "config.vexi_version:#{vexi_version}",

          "feature_flag.source:#{feature_flag_source}",
          "feature_flag.memoization.hit:#{feature_flag_memoization_hit_count >= 1}",
          "feature_flag.cache.hit:#{feature_flag_cache_hit_count >= 1}",
          "feature_flag.adapter.hit:#{feature_flag_adapter_hit_count >= 1}",

          "custom_gates_evaluator.executed:#{custom_gates_evaluator_executed}",
          "fallback_evaluator.executed:#{fallback_evaluator_executed}",

          "feature_flag.adapter.error:#{feature_flag_adapter_error_present}",
          "segment.adapter.error:#{segment_adapter_error_present}",

          "feature_flag.cache.get.error:#{feature_flag_cache_get_error_present}",
          "feature_flag.cache.set.error:#{feature_flag_cache_set_error_present}",

          "feature_flag.adapter.get.circuit_breaker_open:#{feature_flag_adapter_get_circuit_breaker_open}",

          "custom_gate.error:#{custom_gate_evaluator_error_present}",

          "called_with_nil_actors:#{nil_actors}",
          "called_with_invalid_actors:#{invalid_actors}",
        ]

        GitHub.dogstats.distribution("#{TELEMETRY_PREFIX}.#{operation}.duration", measured_duration_ms, tags: operation_duration_tags)
        GitHub.dogstats.distribution("#{TELEMETRY_PREFIX}.is_enabled_including_custom_gates.duration", measured_duration_with_custom_gates_ms, tags: operation_duration_tags)

        if caching_enabled
          # Note that in case of a memoization hit  payload[:"feature_flag.cache.fetch"] will be nil and emit_stage_duration returns early
          emit_stage_duration_unless_payload_nil(vexi_version, "feature_flag", "cache", operation, payload[:"feature_flag.cache.fetch"], feature_flag_cache_get_error_present)
        end

        # Note that in case of a memoization hit or cache hit payload[:"feature_flag.adapter.fetch"] will be nil and emit_stage_duration returns early
        # Not passing the feature_flag_cache_set_error_present here since it's not related the the adapter fetch. We should in the future also subtract cache set duration from the adapter fetch duration which we aren't doing today
        # since we don't have the cache set duration instrumented. Cache set duration should be a separate stage altogether. We also are not capturing adapter duration in case of an exception.
        emit_stage_duration_unless_payload_nil(vexi_version, "feature_flag", "adapter", operation, payload[:"feature_flag.adapter.fetch"], feature_flag_adapter_error_present)

        if feature_flag_cache_get_error_present
          Failbot.report(payload[:"feature_flag.cache.fetch.error"][:error], feature: feature_flag_name, "code.function": operation, "exception.message": payload[:"feature_flag.cache.fetch.error"][:message])
        end

        if feature_flag_cache_set_error_present
          Failbot.report(payload[:"feature_flag.cache.set.error"][:error], feature: feature_flag_name, "code.function": operation, "exception.message": payload[:"feature_flag.cache.set.error"][:message])
        end

        if feature_flag_adapter_error = payload[:"feature_flag.adapter.error"]
          Failbot.report(feature_flag_adapter_error[:error], feature: feature_flag_name, "code.function": operation, "exception.message": feature_flag_adapter_error[:message])
        end

        if segment_adapter_error = payload[:"segment.adapter.error"]
          Failbot.report(segment_adapter_error[:error], feature: feature_flag_name, "code.function": operation, "exception.message": segment_adapter_error[:message])
        end

        if custom_gate_error = payload[:"custom_gate_evaluator.error"]
          Failbot.report(custom_gate_error[:error], feature: feature_flag_name, "code.function": operation, "exception.message": custom_gate_error[:message])
        end
      rescue => ex
        # If development, test or CI re-raise the exception.
        if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test? || ENV["GITHUB_CI"]
          raise ex
        end

        # Otherwise, report the exception to failbot and continue.
        Failbot.report(ex)
      end

      # Vexi preload durations
      ActiveSupport::Notifications.subscribe("vexi.preload.duration") do |event|
        payload = event.payload
        operation = payload[:operation]
        caching_enabled = payload.dig(:config, :caching_enabled)
        memoization_enabled = payload.dig(:config, :memoization_enabled)
        vexi_version = payload.dig(:config, :vexi_version)

        operation_duration_ms = (payload[:measured_finish].to_f - payload[:measured_start].to_f) * 1000

        feature_flag_names = payload.fetch(:feature_flag_names, [])
        feature_flags_count = feature_flag_names.count
        feature_flag_fetch_directly_from_adapter = payload.fetch(:"feature_flag.fetch_directly_from_adapter", false)
        feature_flag_memoization_hit_count = payload.dig(:"feature_flag.memoization.fetch", :entities_count).to_i
        feature_flag_memoization_miss_count = feature_flags_count - feature_flag_memoization_hit_count
        feature_flag_cache_hit_count = payload.dig(:"feature_flag.cache.fetch", :entities_count).to_i
        feature_flag_cache_miss_count = feature_flags_count - feature_flag_memoization_hit_count - feature_flag_cache_hit_count
        feature_flag_adapter_hit_count = payload.dig(:"feature_flag.adapter.fetch", :entities_count).to_i

        segment_cache_hit_count = payload.dig(:"segment.cache.fetch", :entities_count).to_i
        segment_adapter_hit_count = payload.dig(:"segment.adapter.fetch", :entities_count).to_i

        feature_flag_adapter_error_present = payload.has_key?(:"feature_flag.adapter.error")

        feature_flag_cache_get_error_present = payload.has_key?(:"feature_flag.cache.fetch.error")
        feature_flag_cache_set_error_present = payload.has_key?(:"feature_flag.cache.set.error")

        feature_flag_adapter_get_circuit_breaker_open = payload.has_key?(:"feature_flag.adapter.fetch.circuit_breaker_open")

        operation_duration_tags = [
          "config.memoization.enabled:#{memoization_enabled}",
          "config.caching.enabled:#{caching_enabled}",
          "config.vexi_version:#{vexi_version}",

          "feature_flag.fetch_directly_from_adapter:#{feature_flag_fetch_directly_from_adapter}",
          "feature_flag.adapter.error:#{feature_flag_adapter_error_present}",

          "feature_flag.cache.get.error:#{feature_flag_cache_get_error_present}",
          "feature_flag.cache.set.error:#{feature_flag_cache_set_error_present}",

          "feature_flag.adapter.get.circuit_breaker_open:#{feature_flag_adapter_get_circuit_breaker_open}",

          "feature_flag.count:#{bucketed_entity_count(feature_flags_count)}",
        ]

        if payload[:"code.namespace"]
          operation_duration_tags << "code.namespace:#{payload[:"code.namespace"]}"
        end

        GitHub.dogstats.distribution("#{TELEMETRY_PREFIX}.#{operation}.duration", operation_duration_ms, tags: operation_duration_tags)

        if memoization_enabled
          emit_preload_hit_count_unless_zero(vexi_version, "feature_flag", "memoization", feature_flag_memoization_hit_count)
        end

        if caching_enabled
          emit_preload_hit_count_unless_zero(vexi_version, "feature_flag", "cache", feature_flag_cache_hit_count)
          emit_stage_duration_unless_payload_nil(vexi_version, "feature_flag", "cache", operation, payload[:"feature_flag.cache.fetch"], feature_flag_cache_get_error_present)

          emit_preload_hit_count_unless_zero(vexi_version, "segment", "cache", segment_cache_hit_count)
        end

        if feature_flag_adapter_error_present
          Failbot.report(payload[:"feature_flag.adapter.error"][:error], "code.function": operation, "exception.message": payload[:"feature_flag.adapter.error"][:message])
        end

        if feature_flag_cache_get_error_present
          Failbot.report(payload[:"feature_flag.cache.fetch.error"][:error], "code.function": operation, "exception.message": payload[:"feature_flag.cache.fetch.error"][:message])
        end

        if feature_flag_cache_set_error_present
          Failbot.report(payload[:"feature_flag.cache.set.error"][:error], "code.function": operation, "exception.message": payload[:"feature_flag.cache.set.error"][:message])
        end

        emit_preload_hit_count_unless_zero(vexi_version, "feature_flag", "adapter", feature_flag_adapter_hit_count)
        emit_preload_hit_count_unless_zero(vexi_version, "segment", "adapter", segment_adapter_hit_count)

        # Note that in case of a memoization hit or cache hit payload[:"feature_flag.adapter.fetch"] will be nil and emit_stage_duration returns early
        # Not passing the feature_flag_cache_set_error_present here since it's not related the the adapter fetch. We should in the future also subtract cache set duration from the adapter fetch duration which we aren't doing today
        # since we don't have the cache set duration instrumented. Cache set duration should be a separate stage altogether. We also are not capturing adapter duration in case of an exception.
        emit_stage_duration_unless_payload_nil(vexi_version, "feature_flag", "adapter", operation, payload[:"feature_flag.adapter.fetch"], feature_flag_adapter_error_present)

        if GitHub.environment.fetch("FEATURE_FLAG_DISABLE_SLOW_PRELOAD_LOG", "0") == "0" && operation_duration_ms >= SLOW_PRELOAD_THRESHOLD_MS
          ff_cache_fetch_payload = payload.fetch(:"feature_flag.cache.fetch", {})
          ff_cache_fetch_entity_count = ff_cache_fetch_payload.fetch(:entities_count, 0)
          ff_cache_fetch_duration = (ff_cache_fetch_payload[:measured_finish].to_f - ff_cache_fetch_payload[:measured_start].to_f) * 1000

          ff_adapter_fetch_payload = payload.fetch(:"feature_flag.adapter.fetch", {})
          ff_adapter_fetch_entity_count = ff_adapter_fetch_payload.fetch(:entities_count, 0)
          ff_adapter_fetch_duration = (ff_adapter_fetch_payload[:measured_finish].to_f - ff_adapter_fetch_payload[:measured_start].to_f) * 1000

          GitHub.logger.info("slow vexi.preload call", {
            "code.namespace" => self.class.name,
            "#{TELEMETRY_PREFIX}.caller.code.namespace" => payload.fetch(:"code.namespace", "n/a"),

            "#{TELEMETRY_PREFIX}.config.caching.enabled" => caching_enabled,
            "#{TELEMETRY_PREFIX}.config.memoization.enabled" => memoization_enabled,
            "#{TELEMETRY_PREFIX}.config.version" => vexi_version,

            "#{TELEMETRY_PREFIX}.preload.duration" => operation_duration_ms,
            "#{TELEMETRY_PREFIX}.preload.feature_flag.names" => feature_flag_names,
            "#{TELEMETRY_PREFIX}.preload.feature_flag.fetch_directly_from_adapter" => feature_flag_fetch_directly_from_adapter,

            "#{TELEMETRY_PREFIX}.feature_flag.cache.duration" => ff_cache_fetch_duration,
            "#{TELEMETRY_PREFIX}.feature_flag.cache.entity.count" => ff_cache_fetch_entity_count,
            "#{TELEMETRY_PREFIX}.feature_flag.adapter.duration" => ff_adapter_fetch_duration,
            "#{TELEMETRY_PREFIX}.feature_flag.adapter.entity.count" => ff_adapter_fetch_entity_count,
            "#{TELEMETRY_PREFIX}.feature_flag.adapter.circuit_breaker.open" => feature_flag_adapter_get_circuit_breaker_open,
          })
        end
      rescue => ex
        # If development, test or CI re-raise the exception.
        if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test? || ENV["GITHUB_CI"]
          raise ex
        end

        # Otherwise, report the exception to failbot and continue.
        Failbot.report(ex)
      end

      # Custom gate evaluation errors
      ActiveSupport::Notifications.subscribe("vexi.serial_gate_and_actor_evaluator.is_enabled.error") do |event|
        payload = event.payload
        operation = payload[:operation]
        error = payload[:error]

        tags = ["operation:#{operation}"]
        # these fields are all optional
        tags << "feature_flag_name:#{payload[:feature_flag]}" if payload[:feature_flag].present?
        tags << "custom_gate_names:#{payload[:custom_gate_names].join(",")}" unless payload[:custom_gate_names].empty?

        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.serial_gate_and_actor_evaluator.error.count", tags: tags)
        Failbot.report(error, feature: payload[:feature_flag], "code.function": operation)
      rescue => ex
        # If development, test or CI re-raise the exception.
        if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test? || ENV["GITHUB_CI"]
          raise ex
        end

        # Otherwise, report the exception to failbot and continue.
        Failbot.report(ex)
      end

      # Custom gate durations
      ActiveSupport::Notifications.subscribe(/vexi\..+\.is_enabled_for_custom_gate\.duration/) do |event|
        payload = event.payload
        operation = payload[:operation]
        measured_duration_ms = (payload[:measured_finish].to_f - payload[:measured_start].to_f) * 1000

        tags = ["operation:#{operation}"]
        # these fields are all optional
        tags << "result:#{payload[:result]}" unless payload[:result].nil?
        tags << "feature_flag_name:#{payload[:feature_flag]}" if payload[:feature_flag].present?
        tags << "custom_gate_names:#{payload[:custom_gate_name]}" if payload[:custom_gate_name].present?

        GitHub.dogstats.distribution("#{TELEMETRY_PREFIX}.custom_gate.duration", measured_duration_ms, tags: tags)
      rescue => ex
        # If development, test or CI re-raise the exception.
        if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test? || ENV["GITHUB_CI"]
          raise ex
        end

        # Otherwise, report the exception to failbot and continue.
        Failbot.report(ex)
      end
    end

    sig { params(vexi_version: String, entity_type: String, source: String, value: Integer).void }
    def emit_preload_hit_count_unless_zero(vexi_version, entity_type, source, value)
      if value > 0
        GitHub.dogstats.count("#{TELEMETRY_PREFIX}.preload.hit.count", value, tags: [
          "config.vexi_version:#{vexi_version}",
          "entity.type:#{entity_type}",
          "source:#{source}",
        ])
      end
    end

    sig { params(vexi_version: String, entity_type: String, stage: String, operation: String, stage_payload: T.nilable(T::Hash[Symbol, Numeric]), stage_error_present: T::Boolean).void }
    def emit_stage_duration_unless_payload_nil(vexi_version, entity_type, stage, operation, stage_payload, stage_error_present)
      return unless stage_payload

      entity_count = stage_payload.fetch(:entities_count, 0)
      duration = (stage_payload[:measured_finish].to_f - stage_payload[:measured_start].to_f) * 1000

      GitHub.dogstats.distribution("#{TELEMETRY_PREFIX}.#{stage}.duration", duration, tags: [
        "config.vexi_version:#{vexi_version}",
        "operation:#{operation}",
        "error_occurred:#{stage_error_present}",
        "entity.type:#{entity_type}",
        "entity.count:#{bucketed_entity_count(entity_count)}",
      ])
    end

    sig { params(actors_count: Integer).returns(String) }
    def bucketed_actors_count(actors_count)
      case actors_count
      when 0..5; then actors_count.to_s
      else; "6+"
      end
    end

    sig { params(entity_count: Numeric).returns(String) }
    def bucketed_entity_count(entity_count)
      case entity_count
      when 0; then "0"
      when 1..10; then "1-10"
      when 11..25; then "11-25"
      when 26..50; then "26-50"
      when 51..75; then "51-75"
      when 76..100; then "76-100"
      when 101..125; then "101-125"
      when 126..150; then "126-150"
      when 151..175; then "151-175"
      when 176..200; then "176-200"
      else ">200"
      end
    end

    sig { params(url: String, hmac_key: String, service_name: String).returns(GitHub::FaradayClient::Internal) }
    def connection(url, hmac_key, service_name)
      GitHub::FaradayClient::Internal.new(url) do |conn|
        # Depending on the url use the istio or non-istio default timeout values
        using_istio = url.include?("svc.cluster.local")
        open_timeout = using_istio ? DEFAULT_ISTIO_OPEN_TIMEOUT : DEFAULT_OPEN_TIMEOUT
        request_timeout = using_istio ? DEFAULT_ISTIO_REQUEST_TIMEOUT : DEFAULT_REQUEST_TIMEOUT
        timeout = using_istio ? DEFAULT_ISTIO_TIMEOUT : DEFAULT_TIMEOUT

        # Time alloted for opening connection in seconds.
        conn.options[:open_timeout] = open_timeout
        # This is the absolute limit for the entire request and including the open_timeout. Timeout is for per request.
        conn.options[:timeout]      = request_timeout

        conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: service_name, custom_tags: ["using_istio:#{using_istio}"]
        conn.use ::FeatureManagement::StartTime # This needs to be before the retry middleware
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_key
        conn.use ::FeatureManagement::VexiUser

        conn.request :retry,
          interval:            0.05, # Pause in seconds between retries
          interval_randomness: 0.5,  # interval = interval + (interval * interval_randomness)
          max: DEFAULT_MAX_RETRIES,  # first attempt + 2 retries = 3 total attempts
          backoff_factor:      1.2,  # The amount to multiple each successive retry's interval amount by in order to provide backoff
          retry_if: proc { |env, _exception|
            time_elapsed_seconds = (Time.now.to_f - env[:start_time].to_f)
            time_left_seconds = [request_timeout, timeout - time_elapsed_seconds].min

            # We want a fixed budget of 500ms for the entire request including retries.
            # Use a really small second because 0 doesn't mean it'll times out immediately.
            env.request.timeout = time_left_seconds > 0 ? time_left_seconds : 0.00001

            time_left_seconds > 0
          },
          retry_block: proc { GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.request_retry.count", tags: []) },
          retry_statuses: (500...600).to_a

        # This came after Retries middleware in the factory
        conn.use ::GitHub::FaradayMiddleware::Resilient, name: service_name

        conn.adapter :typhoeus
      end
    end

    sig { params(exception: T.nilable(Exception)).returns(String) }
    def parse_and_categorize_errors(exception)
      return "nil_error" if exception.nil?
      return "validation_error" if exception.is_a?(Vexi::Errors::ValidationError)
      return "timeout_error" if exception.is_a?(Faraday::TimeoutError)

      # Try to publish exception class name if it's something descriptive
      return T.must(exception.class.name) if exception.class.name.present? && exception.class.name != "StandardError"

      "unexpected_error"
    end
  end
end
