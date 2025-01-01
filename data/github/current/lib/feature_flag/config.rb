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
require "vexi/caches/in_memory"
require "vexi/observability/duration_payload"
require "vexi/observability/error_payload"
require "vexi/observability/cache_hit_or_miss_payload"
require "vexi/custom_gates_evaluators/serial_gate_and_actor_evaluator"
require_relative "./all_features"
require_relative "./i_feature_target"
require_relative "./cache"

module FeatureFlag
  class Config
    extend T::Helpers
    extend T::Sig

    SERVICE_NAME = "feature_management"
    DEFAULT_OPEN_TIMEOUT = 0.2 # 200ms
    DEFAULT_REQUEST_TIMEOUT = 0.5 # 500ms; per request
    DEFAULT_TIMEOUT = 0.5 # 500ms; across all retries and backoff
    DEFAULT_MAX_RETRIES = 2 # Retry attempts after the initial request
    TELEMETRY_PREFIX = "gh.vexi"

    ADAPTER_DEFAULT_DISABLED = "disabled_by_default"
    ADAPTER_DEFAULT_ENABLED = "enabled_by_default"
    ADAPTER_EXCLUSION_LIST_DISABLED = "disabled"
    ADAPTER_EXCLUSION_LIST_ENABLED = "enabled"

    sig { returns(T.nilable(Vexi::Adapters::InMemoryAdapter)) }
    attr_reader :vexi_test_adapter

    sig { void }
    def initialize
      @adapter = T.let(Vexi::Adapters::InMemoryAdapter.new(Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault), Vexi::Adapter)
      @cache = T.let(nil, T.nilable(Vexi::Cache))
      @cache_ttl = T.let(30, Integer)
      @cache_not_found_ttl = T.let(30, Integer)
      @vexi_test_adapter = T.let(nil, T.nilable(Vexi::Adapters::InMemoryAdapter))

      @logger = T.let(GitHub::Telemetry::Logs.logger("Vexi"), SemanticLogger::Logger)
      @logging_context = T.let({}, T::Hash[String, String])

      configure_observability
      configure_adapter
      fallback_evaluator = create_fallback_evaluator

      Vexi.configure do |builder|
        builder.adapter.custom(@adapter)
        builder.custom_gates_evaluator.serial_gate_and_actor_evaluator(custom_gates)

        if !@cache.nil?
          builder.cache.custom(@cache, @cache_ttl, @cache_not_found_ttl)
        end

        if !fallback_evaluator.nil?
          builder.fallback_evaluator(fallback_evaluator)
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
      elsif GitHub.review_lab?
        configure_review_lab
      elsif GitHub.enterprise? && !GitHub.multi_tenant_enterprise?
        configure_ghes
      else
        configure_production
      end
    end

    sig { returns(T.nilable(Vexi::Configuration::FallbackEvaluator)) }
    def create_fallback_evaluator
      if GitHub::AppEnvironment.test? || ENV["GITHUB_CI"] || ENV["VEXI_E2E_ENABLED"] == "1"
        return nil
      end

      # Fallback evaluator
      proc do |feature_flag_name, actors|
        # Note that this is a proc and return can't be used to exit early as it leads to a JumpError
        # Use next if not in a loop to return early and if inside a loop you'll need to store the return value
        # break and then use next to return it early or just the variable/value if it's the last statement.

        # If actors are empty, check flipper without actors
        if actors.empty?
          next GitHub.flipper.enabled?(feature_flag_name)
        end

        return_value = T.let(false, T::Boolean)
        # Loop through all actors and check if enabled via flipper.
        actors.each do |actor|
          return_value = GitHub.flipper.enabled?(feature_flag_name, actor)
          break if return_value
        end

        return_value
      end
    end

    sig { void }
    def configure_development
      if ENV["VEXI_E2E_ENABLED"] == "1"
        url = GitHub.feature_management_feature_flag_data_url
        ffd_con = connection(url, GitHub.feature_management_feature_flag_data_checks_hmac_shared_key)
        @adapter = Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(ffd_con)
        @cache = Vexi::Caches::InMemory.new
        @cache_ttl = 30
        @cache_not_found_ttl = 30

        @logging_context = {
          "#{TELEMETRY_PREFIX}.configured_mode" => "development-e2e",
          "#{TELEMETRY_PREFIX}.adapter.feature_flag_data_url" => url,
        }
      else
        # Local development (file adapter)
        feature_flag_path = "tmp/vexi/feature-flags"
        segment_path = "tmp/vexi/segments"
        @adapter = Vexi::Adapters::FileAdapter.new(feature_flag_path, segment_path)

        @logging_context = {
          "#{TELEMETRY_PREFIX}.configured_mode" => "development",
        }
      end
    end

    sig { void }
    def configure_test
      if ENV["TEST_ALL_FEATURES"] && !ENV["TEST_TIMERD"]
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
      # Review lab (monolith optimized feature flag data hub adapter with caching)
      url = GitHub.feature_management_feature_flag_data_url
      ffd_con = connection(url, GitHub.feature_management_feature_flag_data_checks_hmac_shared_key)
      @adapter = Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(ffd_con)
      @cache = Vexi::Caches::InMemory.new
      @cache_ttl = 30
      @cache_not_found_ttl = 30

      @logging_context = {
        "#{TELEMETRY_PREFIX}.configured_mode" => "review_lab",
        "#{TELEMETRY_PREFIX}.adapter.feature_flag_data_url" => url,
      }
    end

    sig { void }
    def configure_production
      # Production (monolith optimized feature flag data adapter with caching)
      url = GitHub.feature_management_feature_flag_data_url
      ffd_con = connection(url, GitHub.feature_management_feature_flag_data_checks_hmac_shared_key)
      @adapter = Vexi::Adapters::MonolithOptimizedFeatureFlagDataAdapter.new_from_connection(ffd_con)
      @cache = Vexi::Caches::InMemory.new
      @cache_ttl = 30
      @cache_not_found_ttl = 30

      @logging_context = {
        "#{TELEMETRY_PREFIX}.configured_mode" => "production",
        "#{TELEMETRY_PREFIX}.adapter.feature_flag_data_url" => url,
      }
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
      ActiveSupport::Notifications.subscribe(/\Avexi\..+\.error\Z/) do |event|
        payload = Vexi::Observability::ErrorPayload.new(event)

        tags = ["operation:#{payload.operation}"]
        # these fields are all optional
        tags << "feature:#{payload.feature_flag}" if payload.feature_flag.present?
        tags << "custom_gate_names:#{payload.custom_gate_names.join(",")}" unless payload.custom_gate_names.empty?
        tags << "segments:#{payload.segments.join(",")}" unless payload.segments.empty?
        tags << "stage:#{payload.stage}" if payload.stage.present?
        tags << "actor_count:#{payload.actor_ids.length}" unless payload.actor_ids.empty?
        tags << "failure_reason:#{parse_and_categorize_errors(payload.exception)}" unless payload.exception.nil?

        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.error.count", tags: tags)
        Failbot.report(payload.exception, "feature": payload.feature_flag, "code.function": payload.operation)
      end

      # Most vexi durations
      ActiveSupport::Notifications.subscribe(/vexi(\..+)?\.(is_enabled|fetch)\.duration/) do |event|
        payload = Vexi::Observability::DurationPayload.new(event)
        measured_duration_ms = (payload.measured_finish - payload.measured_start).to_f * 1000
        tags = ["operation:#{payload.operation}"]
        # these fields are all optional
        tags << "result:#{payload.result}" if !payload.result.nil?
        tags << "feature:#{payload.feature_flag}" if payload.feature_flag.present?
        tags << "memoizing:#{payload.context_tags[:memoizing]}" if payload.context_tags.present? && !payload.context_tags[:memoizing].nil?
        tags << "caching:#{payload.context_tags[:caching]}" if payload.context_tags.present? && !payload.context_tags[:caching].nil?

        GitHub.dogstats.distribution("#{TELEMETRY_PREFIX}.operation.duration", measured_duration_ms, tags: tags)
      end

      # Custom gate durations
      ActiveSupport::Notifications.subscribe(/vexi\..+\.is_enabled_for_custom_gate\.duration/) do |event|
        payload = Vexi::Observability::DurationPayload.new(event)
        measured_duration_ms = (payload.measured_finish - payload.measured_start).to_f * 1000
        tags = ["operation:#{payload.operation}"]
        # these fields are all optional
        tags << "result:#{payload.result}" if !payload.result.nil?
        tags << "custom_gate_name:#{payload.custom_gate_name}" if payload.custom_gate_name.present?
        tags << "feature:#{payload.feature_flag}" if payload.feature_flag.present?

        GitHub.dogstats.distribution("#{TELEMETRY_PREFIX}.custom_gate.duration", measured_duration_ms, tags: tags)
      end

      # Matches notifications that follow this structure "vexi.cache.*.get"
      # ActiveSupport::Notifications.subscribe() do |event|
      ActiveSupport::Notifications.subscribe(/\Avexi\.cache\..+\.get\Z/) do |event|
        payload = Vexi::Observability::CacheHitOrMissPayload.new(event)
        tags = [
          "cached_object_type:#{payload.cached_object_type}",
          "cache_hit:#{payload.cache_hit}",
          "source:#{payload.context_tags[:source]}",
        ]

        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.cache.result", tags: tags)
      end
    end

    sig { params(url: String, hmac_key: String).returns(GitHub::FaradayClient::Internal) }
    def connection(url, hmac_key)
      GitHub::FaradayClient::Internal.new(url) do |conn|
        # Time alloted for opening connection in seconds.
        conn.options[:open_timeout] = DEFAULT_OPEN_TIMEOUT
        # This is the absolute limit for the entire request and including the open_timeout. Timeout is for per request.
        conn.options[:timeout]      = DEFAULT_REQUEST_TIMEOUT

        conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
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
            time_left_seconds = [DEFAULT_REQUEST_TIMEOUT, DEFAULT_TIMEOUT - time_elapsed_seconds].min

            # We want a fixed budget of 500ms for the entire request including retries.
            # Use a really small second because 0 doesn't mean it'll times out immediately.
            env.request.timeout = time_left_seconds > 0 ? time_left_seconds : 0.00001

            time_left_seconds > 0
          },
          retry_block: proc { GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.request_retry.count", tags: []) },
          retry_statuses: (500...600).to_a

        # This came after Retries middleware in the factory
        conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME

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
