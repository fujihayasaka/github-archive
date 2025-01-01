# typed: strict
# frozen_string_literal: true

require "active_support/notifications"
require "feature_management/current_user"
require "feature_management/start_time"
require "feature_flag/org_cache"
require "feature_flag/team_cache"
require "feature_flags_common/custom_gates"
require "vexi"
require "vexi/adapters/file_adapter"
require "vexi/adapters/in_memory_adapter"
require "vexi/adapters/monolith_optimized_feature_flag_data_adapter"
require "vexi_management/adapters/feature_flag_hub_adapter"
require "feature_flag/adapters/in_memory_adapter"
require "feature_flag/adapters/fm_lite_adapter"
require "feature_flag/adapters/test_adapter"
require "feature_flag/cache/memcached"
require "feature_flag/cache/null"
require "feature_flag/client/vexi_management_with_call_tracking"
require "vexi/caches/in_memory"
require "vexi/custom_gates_evaluators/serial_gate_and_actor_evaluator"
require_relative "./all_features"
require_relative "./i_feature_target"
require_relative "./cache"

module FeatureFlag
  class Config
    extend T::Helpers

    DEFAULT_OPEN_TIMEOUT = 0.1 # 100ms
    DEFAULT_REQUEST_TIMEOUT = 0.1 # 100ms; per request
    DEFAULT_TIMEOUT = 0.5 # 500ms; across all retries and backoff
    DEFAULT_ISTIO_OPEN_TIMEOUT = 0.025 # 25ms
    DEFAULT_ISTIO_REQUEST_TIMEOUT = 0.025 # 25ms; per request
    DEFAULT_ISTIO_TIMEOUT = 0.125 # 125ms; across all retries and backoff
    DEFAULT_MAX_RETRIES = 2 # Retry attempts after the initial request

    DEFAULT_MANAGEMENT_OPEN_TIMEOUT = 2.0 # seconds
    DEFAULT_MANAGEMENT_TIMEOUT = 5.0 # seconds

    ADAPTER_DEFAULT_DISABLED = "disabled_by_default"
    ADAPTER_DEFAULT_ENABLED = "enabled_by_default"
    ADAPTER_EXCLUSION_LIST_DISABLED = "disabled"
    ADAPTER_EXCLUSION_LIST_ENABLED = "enabled"

    CACHE_FEATURE_FLAG_KEY_PREFIX = "vexi:ff:"
    CACHE_SEGMENT_KEY_PREFIX = "vexi:sg:"

    NEVER_EXPIRE_TTL = 0
    PRODUCTION_CACHE_NOT_FOUND_TTL = 604800

    sig { returns(Vexi::Adapter) }
    attr_reader :vexi_data_adapter

    sig { returns(T.nilable(FeatureFlag::Cache::IMemcachedClient)) }
    attr_reader :cache_client

    sig { void }
    def initialize
      vexi_data_storage = T.let(Vexi::FeatureFlagStorage.new(default_enabled: false), Vexi::FeatureFlagStorage)
      @vexi_data_adapter = T.let(Adapters::InMemoryAdapter.new(shared_storage: vexi_data_storage), Vexi::Adapter)
      @vexi_management_adapter = T.let(VexiManagement::Adapters::InMemoryAdapter.new(shared_storage: vexi_data_storage), VexiManagement::Adapter)

      @adapter_circuit_breaker_config = T.let(nil, T.nilable(Vexi::CircuitBreakerConfig))

      @cache_client = T.let(nil, T.nilable(FeatureFlag::Cache::IMemcachedClient))
      @cache = T.let(FeatureFlag::Cache::Null.new, T.nilable(Vexi::Cache))
      @cache_ttl = T.let(30, Integer)
      @cache_not_found_ttl = T.let(30, Integer)

      @logger = T.let(GitHub::Telemetry::Logs.logger("Vexi"), SemanticLogger::Logger)
      @logging_context = T.let({}, T::Hash[String, String])

      configure_adapter

      Vexi.configure do |builder|
        builder.adapter.custom(@vexi_data_adapter)
        builder.custom_gates_evaluator.serial_gate_and_actor_evaluator(custom_gates)

        if ENV["DISABLE_VEXI_ADAPTER_BREAKER"] != "1"
          builder.circuit_breaker.with_adapter_circuit_breaker(@adapter_circuit_breaker_config)
        end

        if @cache != nil
          builder.cache.custom(@cache, @cache_ttl, @cache_not_found_ttl, CACHE_FEATURE_FLAG_KEY_PREFIX, CACHE_SEGMENT_KEY_PREFIX)
        end
      end

      @vexi_management_instance = T.let(FeatureFlag::Client::VexiManagementWithCallTracking.new(@vexi_management_adapter, Vexi::Notifications.new, vexi_instance), VexiManagement::Client)

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

    sig { returns(VexiManagement::Client) }
    def vexi_management_instance
      @vexi_management_instance
    end

    sig { returns(T::Hash[String, T.proc.params(feature_name: String, actor: T.any(String, Vexi::Actor)).returns(T::Boolean)]) }
    def custom_gates
      FeatureFlagsCommon::CustomGates::CUSTOM_GATES.each_with_object({}) do |(custom_gate, gate_proc), wrapped_gates|
        wrapped_gates[custom_gate] = proc do |feature_name, actor|
          if actor.is_a?(String)
            actor = GitHub::VexiActor.from_vexi_id(actor)
          end
          gate_proc.call(actor, feature_name)
        end
      end
    end

    private

    sig { void }
    def configure_adapter
      if GitHub.single_tenant_enterprise?
        configure_ghes
      elsif GitHub::AppEnvironment.development?
        configure_development
      elsif GitHub::AppEnvironment.test?
        configure_test
      elsif ENV["GITHUB_CI"]
        configure_ci
      elsif GitHub.employee_unicorn? || GitHub.review_lab? || GitHub.staff_host?
        configure_review_lab
      else
        configure_production
      end
    end

    sig { void }
    def configure_development
      if ENV["VEXI_E2E_ENABLED"] == "1"
        data_url = GitHub.feature_management_feature_flag_data_url
        data_conn = connection(data_url, GitHub.feature_management_feature_flag_data_checks_hmac_shared_key, "feature_flag_data")
        @vexi_data_adapter = Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(data_conn)

        management_url = GitHub.feature_management_feature_flag_hub_url
        management_conn = management_connection(management_url, GitHub.feature_management_feature_flag_hub_mgmt_hmac_key, "feature_flag_hub")
        @vexi_management_adapter = VexiManagement::Adapters::FeatureFlagHubAdapter.new_from_connection(management_conn)

        @cache_client = FeatureFlag::Cache::MemcachedClientWithFailover.new
        # Note: This has to be configured after the client is constructed, as this logger is incompatible with the info call done in the
        # constructor of ::Memcached::Rails. Setting it after similar to how it is done for GitHub.cache (although there they use a separate initializer).
        @cache_client.logger = GitHub::Logger
        @cache = FeatureFlag::Cache::Memcached.new(@cache_client)
        @cache_ttl = 30
        @cache_not_found_ttl = 30

        @logging_context = {
          "#{TELEMETRY_PREFIX}.configured_mode" => "development_e2e",
          "#{TELEMETRY_PREFIX}.adapter.feature_flag_data_url" => data_url,
          "#{TELEMETRY_MANAGEMENT_PREFIX}.configured_mode" => "development_e2e",
          "#{TELEMETRY_MANAGEMENT_PREFIX}.adapter.feature_flag_hub_url" => management_url,
        }
      elsif GitHub.use_fm_lite?
        configure_fm_lite_adapter("development")

        @cache_client = FeatureFlag::Cache::MemcachedClientWithFailover.new
        # Note: This has to be configured after the client is constructed, as this logger is incompatible with the info call done in the
        # constructor of ::Memcached::Rails. Setting it after similar to how it is done for GitHub.cache (although there they use a separate initializer).
        @cache_client.logger = GitHub::Logger
        @cache = FeatureFlag::Cache::Memcached.new(@cache_client)
        @cache_ttl = 10
        @cache_not_found_ttl = 10
      else
        configure_in_memory_adapter("development")
      end
    end

    sig { void }
    def configure_test
      if GitHub.use_fm_lite?
        configure_fm_lite_adapter("unit_tests")
      else
        configure_in_memory_adapter("unit_tests")
      end
    end

    sig { void }
    def configure_ci
      if GitHub.use_fm_lite?
        configure_fm_lite_adapter("ci")
      else
        configure_in_memory_adapter("ci")
      end
    end

    sig { void }
    def configure_review_lab
      # Review lab (monolith optimized feature flag data hub adapter with caching and circuit breakers)
      data_url = GitHub.feature_management_feature_flag_data_url
      data_conn = connection(data_url, GitHub.feature_management_feature_flag_data_checks_hmac_shared_key, "feature_flag_data")
      @vexi_data_adapter = Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(data_conn)

      # Review lab (feature flag hub adapter)
      management_url = GitHub.feature_management_feature_flag_hub_url
      management_conn = management_connection(management_url, GitHub.feature_management_feature_flag_hub_mgmt_hmac_key, "feature_flag_hub")
      @vexi_management_adapter = VexiManagement::Adapters::FeatureFlagHubAdapter.new_from_connection(management_conn)

      @cache_client = FeatureFlag::Cache::MemcachedClientWithFailover.new
      # Note: This has to be configured after the client is constructed, as this logger is incompatible with the info call done in the
      # constructor of ::Memcached::Rails. Setting it after similar to how it is done for GitHub.cache (although there they use a separate initializer).
      @cache_client.logger = GitHub::Logger
      @cache = FeatureFlag::Cache::Memcached.new(@cache_client)
      @cache_ttl = 120
      @cache_not_found_ttl = 120

      @logging_context = {
        "#{TELEMETRY_PREFIX}.configured_mode" => "review_lab",
        "#{TELEMETRY_PREFIX}.adapter.feature_flag_data_url" => data_url,
        "#{TELEMETRY_MANAGEMENT_PREFIX}.configured_mode" => "review_lab",
        "#{TELEMETRY_MANAGEMENT_PREFIX}.adapter.feature_flag_hub_url" => management_url,
      }

      @adapter_circuit_breaker_config = Vexi::CircuitBreakerConfig.new(
        error_threshold_percentage: 20,
        request_volume_threshold: 10,
        window_size_in_seconds: 30,
        bucket_size_in_seconds: 3,
        sleep_window_seconds: 5,
      )
    end

    sig { void }
    def configure_production
      # Production (monolith optimized feature flag data adapter with caching and circuit breakers)
      data_url = GitHub.feature_management_feature_flag_data_url
      data_conn = connection(data_url, GitHub.feature_management_feature_flag_data_checks_hmac_shared_key, "feature_flag_data")
      @vexi_data_adapter = Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(data_conn)

      # Production (feature flag hub adapter)
      management_url = GitHub.feature_management_feature_flag_hub_url
      management_conn = management_connection(management_url, GitHub.feature_management_feature_flag_hub_mgmt_hmac_key, "feature_flag_hub")
      @vexi_management_adapter = VexiManagement::Adapters::FeatureFlagHubAdapter.new_from_connection(management_conn)

      @cache_client = FeatureFlag::Cache::MemcachedClientWithFailover.new
      # Note: This has to be configured after the client is constructed, as this logger is incompatible with the info call done in the
      # constructor of ::Memcached::Rails. Setting it after similar to how it is done for GitHub.cache (although there they use a separate initializer).
      @cache_client.logger = GitHub::Logger
      @cache = FeatureFlag::Cache::Memcached.new(@cache_client)
      @cache_ttl = 0 # Never expire
      @cache_not_found_ttl = PRODUCTION_CACHE_NOT_FOUND_TTL

      @logging_context = {
        "#{TELEMETRY_PREFIX}.configured_mode" => "production",
        "#{TELEMETRY_PREFIX}.adapter.feature_flag_data_url" => data_url,
        "#{TELEMETRY_MANAGEMENT_PREFIX}.configured_mode" => "production",
        "#{TELEMETRY_MANAGEMENT_PREFIX}.adapter.feature_flag_hub_url" => management_url,
      }

      @adapter_circuit_breaker_config = Vexi::CircuitBreakerConfig.new(
        error_threshold_percentage: 10,
        request_volume_threshold: 50,
        window_size_in_seconds: 30,
        bucket_size_in_seconds: 3,
        sleep_window_seconds: 5,
      )
    end

    sig { void }
    def configure_ghes
      vexi_data_storage = Vexi::FeatureFlagStorage.new(default_enabled: false)
      @vexi_data_adapter = Adapters::InMemoryAdapter.new(shared_storage: vexi_data_storage)
      @vexi_management_adapter = VexiManagement::Adapters::InMemoryAdapter.new(shared_storage: vexi_data_storage)

      @logging_context = {
        "#{TELEMETRY_PREFIX}.configured_mode" => "ghes",
        "#{TELEMETRY_PREFIX}.adapter.mode" => ADAPTER_DEFAULT_DISABLED,
        "#{TELEMETRY_PREFIX}.adapter.exclusion_list" => ADAPTER_EXCLUSION_LIST_DISABLED,
        "#{TELEMETRY_MANAGEMENT_PREFIX}.configured_mode" => "ghes",
        "#{TELEMETRY_MANAGEMENT_PREFIX}.adapter.mode" => ADAPTER_DEFAULT_DISABLED,
        "#{TELEMETRY_MANAGEMENT_PREFIX}.adapter.exclusion_list" => ADAPTER_EXCLUSION_LIST_DISABLED,
      }
    end

    sig { params(env_name: String).void }
    def configure_fm_lite_adapter(env_name)
      default_enabled = !!ENV["TEST_ALL_FEATURES"]
      exception_list = T.let(default_enabled ? FeatureFlag::AllFeatures.exclusion_list.map { |f| f.to_s } : [], T::Array[String])

      data_url = GitHub.feature_management_feature_flag_data_url
      data_conn = connection(data_url, "", "feature_management_lite")

      management_url = GitHub.feature_management_feature_flag_hub_url
      management_conn = management_connection(management_url, "", "feature_management_lite")

      fm_lite_adapter = FeatureFlag::Adapters::FeatureManagementLiteAdapter.new(data_conn, management_conn, default_enabled: default_enabled, exception_feature_flags: exception_list)
      @vexi_data_adapter = @vexi_management_adapter = fm_lite_adapter

      @logging_context = {
        "#{TELEMETRY_PREFIX}.configured_mode" => "#{env_name}_fm_lite",
        "#{TELEMETRY_PREFIX}.adapter.mode" => default_enabled ? ADAPTER_DEFAULT_ENABLED : ADAPTER_DEFAULT_DISABLED,
        "#{TELEMETRY_PREFIX}.adapter.exclusion_list" => default_enabled ? ADAPTER_EXCLUSION_LIST_ENABLED : ADAPTER_EXCLUSION_LIST_DISABLED,
        "#{TELEMETRY_PREFIX}.adapter.feature_flag_data_url" => data_url,
        "#{TELEMETRY_MANAGEMENT_PREFIX}.configured_mode" => "#{env_name}_fm_lite",
        "#{TELEMETRY_MANAGEMENT_PREFIX}.adapter.mode" => default_enabled ? ADAPTER_DEFAULT_ENABLED : ADAPTER_DEFAULT_DISABLED,
        "#{TELEMETRY_MANAGEMENT_PREFIX}.adapter.exclusion_list" => default_enabled ? ADAPTER_EXCLUSION_LIST_ENABLED : ADAPTER_EXCLUSION_LIST_DISABLED,
        "#{TELEMETRY_MANAGEMENT_PREFIX}.adapter.feature_flag_hub_url" => management_url,
      }
    end

    sig { params(env_name: String).void }
    def configure_in_memory_adapter(env_name)
      default_enabled = ENV["TEST_ALL_FEATURES"] && !ENV["TEST_TIMERD"]
      exception_list = T.let(default_enabled ? FeatureFlag::AllFeatures.exclusion_list.map { |f| f.to_s } : [], T::Array[String])

      vexi_data_storage = Vexi::FeatureFlagStorage.new(default_enabled: default_enabled, exception_feature_flags: exception_list)
      @vexi_data_adapter = Adapters::InMemoryAdapter.new(shared_storage: vexi_data_storage)
      @vexi_management_adapter = VexiManagement::Adapters::InMemoryAdapter.new(shared_storage: vexi_data_storage)

      mode_type = default_enabled ? "all_enabled" : "all_disabled"
      @logging_context = {
        "#{TELEMETRY_PREFIX}.configured_mode" => "#{mode_type}_#{env_name}",
        "#{TELEMETRY_PREFIX}.adapter.mode" => default_enabled ? ADAPTER_DEFAULT_ENABLED : ADAPTER_DEFAULT_DISABLED,
        "#{TELEMETRY_PREFIX}.adapter.exclusion_list" => default_enabled ? ADAPTER_EXCLUSION_LIST_ENABLED : ADAPTER_EXCLUSION_LIST_DISABLED,
        "#{TELEMETRY_MANAGEMENT_PREFIX}.configured_mode" => "#{mode_type}_#{env_name}",
        "#{TELEMETRY_MANAGEMENT_PREFIX}.adapter.mode" => default_enabled ? ADAPTER_DEFAULT_ENABLED : ADAPTER_DEFAULT_DISABLED,
        "#{TELEMETRY_MANAGEMENT_PREFIX}.adapter.exclusion_list" => default_enabled ? ADAPTER_EXCLUSION_LIST_ENABLED : ADAPTER_EXCLUSION_LIST_DISABLED,
      }
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

    sig { params(url: String, hmac_key: String, service_name: String).returns(GitHub::FaradayClient::Internal) }
    def management_connection(url, hmac_key, service_name)
      GitHub::FaradayClient::Internal.new(url) do |conn|
        conn.options[:open_timeout] = DEFAULT_MANAGEMENT_OPEN_TIMEOUT
        conn.options[:timeout]      = DEFAULT_MANAGEMENT_TIMEOUT

        conn.request :json
        conn.request :retry,
        max: DEFAULT_MAX_RETRIES,
        backoff_factor:      1.2,
        methods:     [:post],
        retry_block: proc { GitHub.dogstats.increment("#{TELEMETRY_MANAGEMENT_PREFIX}.request_retry.count", tags: []) }

        conn.use ::GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_key
        conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: service_name, custom_tags: ["service_endpoint:#{url}"]
        conn.use ::FeatureManagement::VexiManagementUser
        conn.use ::GitHub::FaradayMiddleware::Resilient, name: service_name
        conn.adapter :typhoeus
      end
    end
  end
end
