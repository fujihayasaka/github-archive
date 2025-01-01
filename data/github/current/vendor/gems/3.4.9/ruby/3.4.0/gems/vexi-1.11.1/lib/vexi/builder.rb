# frozen_string_literal: true
#              


require "vexi/configuration"
require "vexi/builders/adapter_builder"
require "vexi/builders/cache_builder"
require "vexi/builders/circuit_breaker_builder"
require "vexi/builders/custom_gates_evaluator_builder"

module Vexi
  class Builder
    class BuilderError < StandardError; end

    def initialize(config)
      @config =      (config               )

      @adapter_builder =      (Builders::AdapterBuilder.new(config)                          )
      @cache_builder =      (Builders::CacheBuilder.new(config)                        )
      @circuit_breaker_builder =      (Builders::CircuitBreakerBuilder.new(config)                                 )
      @custom_gates_evaluator_builder =      (Builders::CustomGatesEvaluatorBuilder.new(config)                                       )
    end

    def adapter
      @adapter_builder
    end

    def cache
      @cache_builder
    end

    def circuit_breaker
      @circuit_breaker_builder
    end

    def custom_gates_evaluator
      @custom_gates_evaluator_builder
    end
  end
end
