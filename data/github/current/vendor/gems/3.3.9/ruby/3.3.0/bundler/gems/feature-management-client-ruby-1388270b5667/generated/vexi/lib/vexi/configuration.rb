# frozen_string_literal: true
#              

require "resilient/circuit_breaker"

require "vexi/actor"
require "vexi/circuit_breaker_config"
require "vexi/client"
require "vexi/version"

module Vexi
  class Configuration
    FallbackEvaluator = T.type_alias { T.proc.params(feature_flag_name: String, actors: T::Array[T.any(Actor, String)]).returns(T::Boolean) }
    DEFAULT_FALLBACK_EVALUATOR =       (-> (_feature_flag_name, _actors) { false }                   )

    attr_accessor :adapter_breaker_config

    attr_accessor :cache_breaker_config

    attr_reader :cache_config

    attr_reader :custom_gates_evaluator

    attr_reader :fallback_evaluator

    attr_reader :errors

    class ConfigurationError < StandardError; end

    def initialize(adapter: nil, cache_config: nil, custom_gates_evaluator: nil)
      @adapter =      (adapter                    )
      @adapter_breaker_config =      (nil                                 )
      @cache_config =      (cache_config                        )
      @cache_breaker_config =      (nil                                 )
      @custom_gates_evaluator =      (custom_gates_evaluator                                 )
      @fallback_evaluator =      (DEFAULT_FALLBACK_EVALUATOR                   )

      @errors =      ([]                  )
    end

    def configured?
      !!@adapter # We assume that Vexi was configured if an adapter was set
    end

    def create_instance
      unless valid?
        raise ConfigurationError, "Invalid configuration: #{errors.join(", ")}"
      end

      adapter_breaker =      (nil                                      )
      if adapter_breaker_config
        adapter_breaker = Resilient::CircuitBreaker.get("adapter_breaker", adapter_breaker_config.to_h)
      end

      cache_breaker =      (nil                                      )
      if cache_breaker_config
        cache_breaker = Resilient::CircuitBreaker.get("cache_breaker", cache_breaker_config.to_h)
      end

      feature_flag_service = Services::FeatureFlagService.new(adapter, cache_config, adapter_breaker, cache_breaker)
      segment_service = Services::SegmentService.new(adapter, cache_config, adapter_breaker, cache_breaker)

      Client.new(self, feature_flag_service, segment_service)
    end

    def adapter
      if !@adapter
        raise ConfigurationError, "Adapter was not configured"
      end

      @adapter
    end

    def adapter=(adapter)
      if @adapter
        raise ConfigurationError, "Adapter already configured: #{@adapter.adapter_name}"
      end

      @adapter = adapter
    end

    def cache_config=(cache_config)
      if @cache_config
        raise ConfigurationError, "Cache already configured: #{@cache_config.cache.cache_name}"
      end

      @cache_config = cache_config
    end

    def custom_gates_evaluator=(custom_gates_evaluator)
      if @custom_gates_evaluator
        raise ConfigurationError, "CustomGatesEvaluator already configured: #{@custom_gates_evaluator.custom_gates_evaluator_name}"
      end

      @custom_gates_evaluator = custom_gates_evaluator
    end

    def fallback_evaluator=(fallback_evaluator)
      # Fallback evaluator is set up with a default
      @fallback_evaluator = fallback_evaluator
    end

    def context
      {
        adapter_name: adapter.adapter_name,
        adapter_version: nil,
        caching_enabled: !!@cache_config,
        cache_name: @cache_config ? @cache_config.cache.cache_name : nil,
        custom_gates_evaluator_enabled: !!@custom_gates_evaluator,
        custom_gates_evaluator_name: @custom_gates_evaluator ? @custom_gates_evaluator.custom_gates_evaluator_name: nil,
        vexi_version: VERSION,
      }
    end

    def valid?
      @errors = [] # Reset errors to get accurate results

      if !@adapter
        @errors << "adapter was not configured"
        return false
      end

      true
    end
  end
end
