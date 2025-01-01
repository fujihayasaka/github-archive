# typed: strict
# frozen_string_literal: true

require "vexi"

module FeatureFlag
  TELEMETRY_PREFIX = "gh.vexi"
  TELEMETRY_MANAGEMENT_PREFIX = "gh.vexi_management"
  IS_ENABLED_MEMOIZED_SAMPLING_PERCENTAGE = 1

  class Observability
    extend T::Helpers

    sig { void }
    def initialize
      # Vexi enabled? durations
      ActiveSupport::Notifications.subscribe("vexi.is_enabled.duration") do |event|
        payload = event.payload

        feature_flag_adapter_error_present = payload.has_key?(:"feature_flag.adapter.error")
        feature_flag_cache_get_error_present = payload.has_key?(:"feature_flag.cache.fetch.error")
        feature_flag_cache_set_error_present = payload.has_key?(:"feature_flag.cache.set.error")
        custom_gate_evaluator_error_present = payload.has_key?(:"custom_gate_evaluator.error")
        segment_adapter_error_present = payload.has_key?(:"segment.adapter.error")

        feature_flag_memoization_hit_count = payload.dig(:"feature_flag.memoization.fetch", :entities_count).to_i

        if feature_flag_memoization_hit_count >= 1
          sample_call = rand(100) < IS_ENABLED_MEMOIZED_SAMPLING_PERCENTAGE
          error_present = feature_flag_adapter_error_present || feature_flag_cache_get_error_present || feature_flag_cache_set_error_present || custom_gate_evaluator_error_present || segment_adapter_error_present

          unless error_present || sample_call
            next
          end
        end

        feature_flag_cache_hit_count = payload.dig(:"feature_flag.cache.fetch", :entities_count).to_i
        feature_flag_source = if feature_flag_memoization_hit_count >= 1
          "memoized"
        elsif feature_flag_cache_hit_count >= 1
          "cached"
        else
          "adapter_called"
        end

        operation = payload[:operation]
        method = payload[:method]
        feature_flag_name = payload[:feature_flag_name]
        default_value = payload[:default_value]
        caching_enabled = payload.dig(:config, :caching_enabled)
        memoization_enabled = payload.dig(:config, :memoization_enabled)
        vexi_version = payload.dig(:config, :vexi_version)

        measured_duration_with_custom_gates_ms = (payload[:measured_finish].to_f - payload[:measured_start].to_f) * 1000
        custom_gates_duration_ms = (payload.dig(:custom_gates, :measured_finish).to_f - payload.dig(:custom_gates, :measured_start).to_f) * 1000
        measured_duration_ms = measured_duration_with_custom_gates_ms - custom_gates_duration_ms

        custom_gates_evaluator_executed = payload.has_key?(:"custom_gates")

        feature_flag_adapter_get_circuit_breaker_open = payload.has_key?(:"feature_flag.adapter.fetch.circuit_breaker_open")
        evaluation_unsuccessful = payload.has_key?(:evaluation_unsuccessful)
        responded_with_default_value = payload.has_key?(:responded_with_default_value) && payload[:responded_with_default_value]

        # Ignore segments since we currently don't have any segments right now.

        operation_duration_tags = [
          "method:#{method}",

          "result:#{payload[:result]}",
          "result_reason:#{payload[:result_reason]}",
          "feature_flag.key:#{feature_flag_name}",
          "default_value:#{default_value}",
          "number_of_actors_being_checked:#{bucketed_actors_count(payload[:number_of_actors_being_checked])}",

          "config.memoization.enabled:#{memoization_enabled}",
          "config.vexi_version:#{vexi_version}",

          "feature_flag.source:#{feature_flag_source}",

          "custom_gate.error:#{custom_gate_evaluator_error_present}",
          "evaluation_unsuccessful:#{evaluation_unsuccessful}",
          "responded_with_default_value:#{responded_with_default_value}",
        ]

        # Cache errors could be the cause for falling back to adapter
        if feature_flag_source == "cached" || feature_flag_source == "adapter_called"
          operation_duration_tags.push(
            "feature_flag.cache.get.error:#{feature_flag_cache_get_error_present}",
            "feature_flag.cache.set.error:#{feature_flag_cache_set_error_present}",
          )
        end

        if feature_flag_source == "adapter_called"
          operation_duration_tags.push(
            "feature_flag.adapter.error:#{feature_flag_adapter_error_present}",
            "segment.adapter.error:#{segment_adapter_error_present}",
            "feature_flag.adapter.get.circuit_breaker_open:#{feature_flag_adapter_get_circuit_breaker_open}",
          )
        end

        GitHub.dogstats.distribution("#{TELEMETRY_PREFIX}.#{operation}.duration.#{feature_flag_source}", measured_duration_ms, tags: operation_duration_tags)

        nil_actors = payload.has_key?(:"nil_actor_indices")
        invalid_actors = payload.has_key?(:"invalid_actor_type_indices")
        flipper_actors = payload.has_key?(:"only_flipper_actor_indices")

        unexpected_actors_reason = if nil_actors
          "nil_actors"
        elsif flipper_actors
          "flipper_actors"
        elsif invalid_actors
          "invalid_actors"
        end

        if unexpected_actors_reason
          GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.unexpected_actors", tags: [
            "reason:#{unexpected_actors_reason}",
            "feature_flag.key:#{feature_flag_name}",
          ])
        end

        if feature_flag_cache_get_error_present
          Failbot.report(
            payload[:"feature_flag.cache.fetch.error"][:error],
            feature: feature_flag_name,
            "code.namespace": Vexi.instance.class.name,
            "code.function": operation,
            "exception.message": payload[:"feature_flag.cache.fetch.error"][:message],
          )
        end

        if feature_flag_cache_set_error_present
          Failbot.report(
            payload[:"feature_flag.cache.set.error"][:error],
            feature: feature_flag_name,
            "code.namespace": Vexi.instance.class.name,
            "code.function": operation,
            "exception.message": payload[:"feature_flag.cache.set.error"][:message],
          )
        end

        if feature_flag_adapter_error = payload[:"feature_flag.adapter.error"]
          Failbot.report(
            feature_flag_adapter_error[:error],
            feature: feature_flag_name,
            "code.namespace": Vexi.instance.class.name,
            "code.function": operation,
            "exception.message": feature_flag_adapter_error[:message],
          )
        end

        if segment_adapter_error = payload[:"segment.adapter.error"]
          Failbot.report(
            segment_adapter_error[:error],
            feature: feature_flag_name,
            "code.namespace": Vexi.instance.class.name,
            "code.function": operation,
            "exception.message": segment_adapter_error[:message],
          )
        end

        if custom_gate_error = payload[:"custom_gate_evaluator.error"]
          Failbot.report(
            custom_gate_error[:error],
            feature: feature_flag_name,
            "code.namespace": Vexi.instance.class.name,
            "code.function": operation,
            "exception.message": custom_gate_error[:message],
          )
        end
      rescue => ex # rubocop:disable Lint/RescueException
        # If development, test or CI re-raise the exception.
        if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test? || ENV["GITHUB_CI"]
          raise ex
        end

        # Otherwise, report the exception to failbot and continue.
        Failbot.report(ex, "code.namespace": "FeatureFlag::Config", "code.function": "configure_observability")
      end

      # Vexi actors_value duration
      ActiveSupport::Notifications.subscribe("vexi.actors_value.duration") do |event|
        handle_compatibility_event(event)
      end

      # Vexi percentage_of_actors_value duration
      ActiveSupport::Notifications.subscribe("vexi.percentage_of_actors_value.duration") do |event|
        handle_compatibility_event(event)
      end

      # Vexi percentage_of_calls_value duration
      ActiveSupport::Notifications.subscribe("vexi.percentage_of_calls_value.duration") do |event|
        handle_compatibility_event(event)
      end

      # Vexi fully_enabled duration
      ActiveSupport::Notifications.subscribe("vexi.fully_enabled.duration") do |event|
        handle_compatibility_event(event)
      end

      # Vexi fully_disabled duration
      ActiveSupport::Notifications.subscribe("vexi.fully_disabled.duration") do |event|
        handle_compatibility_event(event)
      end

      # Vexi exists duration
      ActiveSupport::Notifications.subscribe("vexi.exists.duration") do |event|
        handle_compatibility_event(event)
      end

      # Vexi get_feature_flag duration
      ActiveSupport::Notifications.subscribe("vexi.get_feature_flag.duration") do |event|
        handle_management_event(event)
      end

      # Vexi enable_feature_flag duration
      ActiveSupport::Notifications.subscribe("vexi.enable_feature_flag.duration") do |event|
        handle_management_event(event)
      end

      # Vexi disable_feature_flag duration
      ActiveSupport::Notifications.subscribe("vexi.disable_feature_flag.duration") do |event|
        handle_management_event(event)
      end

      # Vexi add_feature_flag_actors duration
      ActiveSupport::Notifications.subscribe("vexi.add_feature_flag_actors.duration") do |event|
        handle_management_event(event)
      end

      # Vexi remove_feature_flag_actors duration
      ActiveSupport::Notifications.subscribe("vexi.remove_feature_flag_actors.duration") do |event|
        handle_management_event(event)
      end

      # Vexi set_feature_flag_percentage_of_calls duration
      ActiveSupport::Notifications.subscribe("vexi.set_feature_flag_percentage_of_calls.duration") do |event|
        handle_management_event(event)
      end

      # Vexi set_feature_flag_percentage_of_actors duration
      ActiveSupport::Notifications.subscribe("vexi.set_feature_flag_percentage_of_actors.duration") do |event|
        handle_management_event(event)
      end

      # Vexi add_feature_flag_custom_gate duration
      ActiveSupport::Notifications.subscribe("vexi.add_feature_flag_custom_gate.duration") do |event|
        handle_management_event(event)
      end

      # Vexi remove_feature_flag_custom_gate duration
      ActiveSupport::Notifications.subscribe("vexi.remove_feature_flag_custom_gate.duration") do |event|
        handle_management_event(event)
      end

      # Vexi preload durations
      ActiveSupport::Notifications.subscribe("vexi.preload.duration") do |event|
        payload = event.payload
        operation = payload[:operation]
        method = payload[:method]
        caching_enabled = payload.dig(:config, :caching_enabled)
        memoization_enabled = payload.dig(:config, :memoization_enabled)
        vexi_version = payload.dig(:config, :vexi_version)

        operation_duration_ms = (payload[:measured_finish].to_f - payload[:measured_start].to_f) * 1000

        feature_flag_names = payload.fetch(:feature_flag_names, [])
        feature_flags_count = feature_flag_names.count
        feature_flag_fetch_directly_from_adapter = payload.fetch(:"feature_flag.fetch_directly_from_adapter", false)
        feature_flag_memoization_hit_count = payload.dig(:"feature_flag.memoization.fetch", :entities_count).to_i
        feature_flag_cache_hit_count = payload.dig(:"feature_flag.cache.fetch", :entities_count).to_i
        feature_flag_adapter_hit_count = payload.dig(:"feature_flag.adapter.fetch", :entities_count).to_i

        segment_cache_hit_count = payload.dig(:"segment.cache.fetch", :entities_count).to_i
        segment_adapter_hit_count = payload.dig(:"segment.adapter.fetch", :entities_count).to_i

        feature_flag_adapter_error_present = payload.has_key?(:"feature_flag.adapter.error")

        feature_flag_cache_get_error_present = payload.has_key?(:"feature_flag.cache.fetch.error")
        feature_flag_cache_set_error_present = payload.has_key?(:"feature_flag.cache.set.error")
        feature_flag_cache_mset_error_present = payload.has_key?(:"feature_flag.cache.mset.error")
        feature_flag_cache_not_found_mset_error_present = payload.has_key?(:"feature_flag.cache.not_found.mset.error")

        feature_flag_adapter_get_circuit_breaker_open = payload.has_key?(:"feature_flag.adapter.fetch.circuit_breaker_open")

        evaluation_unsuccessful = payload.has_key?(:evaluation_unsuccessful)

        operation_duration_tags = [
          "method:#{method}",

          "config.memoization.enabled:#{memoization_enabled}",
          "config.caching.enabled:#{caching_enabled}",
          "config.vexi_version:#{vexi_version}",

          "feature_flag.fetch_directly_from_adapter:#{feature_flag_fetch_directly_from_adapter}",
          "feature_flag.adapter.error:#{feature_flag_adapter_error_present}",

          "feature_flag.cache.get.error:#{feature_flag_cache_get_error_present}",
          "feature_flag.cache.set.error:#{feature_flag_cache_set_error_present}",
          "feature_flag.cache.mset.error:#{feature_flag_cache_mset_error_present}",
          "feature_flag.cache.not_found.mset.error:#{feature_flag_cache_not_found_mset_error_present}",

          "feature_flag.adapter.get.circuit_breaker_open:#{feature_flag_adapter_get_circuit_breaker_open}",

          "feature_flag.count:#{bucketed_entity_count(feature_flags_count)}",

          "evaluation_unsuccessful:#{evaluation_unsuccessful}",
        ]


        code_namespace = "unknown"
        if payload[:"code.namespace"]
          code_namespace = payload[:"code.namespace"]
        end
        operation_duration_tags << "code.namespace:#{code_namespace}"

        hit_count_tags = [
          "config.vexi_version:#{vexi_version}",
          "code.namespace:#{code_namespace}",
          "feature_flag.fetch_directly_from_adapter:#{feature_flag_fetch_directly_from_adapter}"
        ]

        GitHub.dogstats.distribution("#{TELEMETRY_PREFIX}.#{operation}.duration", operation_duration_ms, tags: operation_duration_tags)

        if memoization_enabled
          emit_preload_hit_count_unless_zero("feature_flag", "memoization", feature_flag_memoization_hit_count, hit_count_tags)
        end

        if caching_enabled
          emit_preload_hit_count_unless_zero("feature_flag", "cache", feature_flag_cache_hit_count, hit_count_tags)
          emit_stage_duration_unless_payload_nil(vexi_version, "feature_flag", "cache", operation, payload[:"feature_flag.cache.fetch"], feature_flag_cache_get_error_present)
          emit_stage_duration_unless_payload_nil(vexi_version, "feature_flag", "cache.mset", operation, payload[:"feature_flag.cache.mset"], feature_flag_cache_mset_error_present)
          emit_stage_duration_unless_payload_nil(vexi_version, "feature_flag", "cache.not_found.mset", operation, payload[:"feature_flag.cache.not_found.mset"], feature_flag_cache_not_found_mset_error_present)

          emit_preload_hit_count_unless_zero("segment", "cache", segment_cache_hit_count, hit_count_tags)
        end

        if feature_flag_adapter_error_present
          Failbot.report(
            payload[:"feature_flag.adapter.error"][:error],
            "code.namespace": Vexi.instance.class.name,
            "code.function": operation,
            "exception.message": payload[:"feature_flag.adapter.error"][:message],
          )
        end

        if feature_flag_cache_get_error_present
          Failbot.report(
            payload[:"feature_flag.cache.fetch.error"][:error],
            "code.namespace": Vexi.instance.class.name,
            "code.function": operation,
            "exception.message": payload[:"feature_flag.cache.fetch.error"][:message],
          )
        end

        if feature_flag_cache_set_error_present
          Failbot.report(
            payload[:"feature_flag.cache.set.error"][:error],
            "code.namespace": Vexi.instance.class.name,
            "code.function": operation,
            "exception.message": payload[:"feature_flag.cache.set.error"][:message],
          )
        end

        if feature_flag_cache_mset_error_present
          Failbot.report(
            payload[:"feature_flag.cache.mset.error"][:error],
            "code.namespace": Vexi.instance.class.name,
            "code.function": operation,
            "exception.message": payload[:"feature_flag.cache.mset.error"][:message],
          )
        end

        if feature_flag_cache_not_found_mset_error_present
          Failbot.report(
            payload[:"feature_flag.cache.not_found.mset.error"][:error],
            "code.namespace": Vexi.instance.class.name,
            "code.function": operation,
            "exception.message": payload[:"feature_flag.cache.not_found.mset.error"][:message],
          )
        end

        emit_preload_hit_count_unless_zero("feature_flag", "adapter", feature_flag_adapter_hit_count, hit_count_tags)
        emit_preload_hit_count_unless_zero("segment", "adapter", segment_adapter_hit_count, hit_count_tags)

        # Note that in case of a memoization hit or cache hit payload[:"feature_flag.adapter.fetch"] will be nil and emit_stage_duration returns early
        # Not passing the feature_flag_cache_set_error_present here since it's not related the the adapter fetch.
        # Cache set duration should be a separate stage altogether. We also are not capturing adapter duration in case of an exception.
        emit_stage_duration_unless_payload_nil(vexi_version, "feature_flag", "adapter", operation, payload[:"feature_flag.adapter.fetch"], feature_flag_adapter_error_present)
      rescue => ex # rubocop:disable Lint/RescueException
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
        tags << "custom_gate_name:#{payload[:custom_gate_name]}" if payload[:custom_gate_name].present?

        GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.serial_gate_and_actor_evaluator.error.count", tags: tags)
        Failbot.report(
          error,
          feature: payload[:feature_flag],
          "code.namespace": Vexi.instance.class.name,
          "code.function": operation,
        )
      rescue => ex # rubocop:disable Lint/RescueException
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
        tags << "custom_gate_name:#{payload[:custom_gate_name]}" if payload[:custom_gate_name].present?

        GitHub.dogstats.distribution("#{TELEMETRY_PREFIX}.custom_gate.duration", measured_duration_ms, tags: tags)
      rescue => ex # rubocop:disable Lint/RescueException
        # If development, test or CI re-raise the exception.
        if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test? || ENV["GITHUB_CI"]
          raise ex
        end

        # Otherwise, report the exception to failbot and continue.
        Failbot.report(ex)
      end
    end

    sig { params(event: T.untyped).void }
    def handle_compatibility_event(event)
      payload = event.payload
      operation = payload[:operation]
      evaluation_unsuccessful = payload.has_key?(:evaluation_unsuccessful)
      operation_duration_ms = (payload[:measured_finish].to_f - payload[:measured_start].to_f) * 1000

      operation_duration_tags = [
        "feature_flag.key:#{payload[:feature_flag_name]}",
        "evaluation_unsuccessful:#{evaluation_unsuccessful}",
        "result_reason:#{payload[:result_reason]}",
      ]
      if payload.has_key?(:result)
        operation_duration_tags << "result:#{payload[:result]}"
      end

      GitHub.dogstats.distribution("#{TELEMETRY_PREFIX}.#{operation}.duration", operation_duration_ms, tags: operation_duration_tags)
    rescue => ex # rubocop:disable Lint/RescueException
      # If development, test or CI re-raise the exception.
      if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test? || ENV["GITHUB_CI"]
        raise ex
      end

      # Otherwise, report the exception to failbot and continue.
      Failbot.report(ex, "code.namespace": "FeatureFlag::Config", "code.function": "handle_compatibility_event")
    end

    sig { params(event: T.untyped).void }
    def handle_management_event(event)
      payload = event.payload
      operation = payload[:operation]
      operation_duration_ms = (payload[:measured_finish].to_f - payload[:measured_start].to_f) * 1000

      operation_duration_tags = [
        "feature_flag.key:#{payload[:feature_flag_name]}",
      ]

      GitHub.dogstats.distribution("#{TELEMETRY_MANAGEMENT_PREFIX}.#{operation}.duration", operation_duration_ms, tags: operation_duration_tags)
    rescue => ex # rubocop:disable Lint/RescueException
      # If development, test or CI re-raise the exception.
      if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test? || ENV["GITHUB_CI"]
        raise ex
      end

      # Otherwise, report the exception to failbot and continue.
      Failbot.report(ex, "code.namespace": "FeatureFlag::Config", "code.function": "handle_management_event")
    end

    sig { params(entity_type: String, source: String, value: Integer, common_tags: T::Array[String]).void }
    def emit_preload_hit_count_unless_zero(entity_type, source, value, common_tags)
      if value > 0
        # Create a new array that includes both the original tags and the new ones
        combined_tags = common_tags.dup + ["entity.type:#{entity_type}", "source:#{source}"]
        GitHub.dogstats.count("#{TELEMETRY_PREFIX}.preload.hit.count", value, tags: combined_tags)
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
  end
end
