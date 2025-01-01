# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require "vexi/configuration"
require "vexi/builders/adapter_builder"
require "vexi/builders/cache_builder"
require "vexi/builders/circuit_breaker_builder"
require "vexi/builders/custom_gates_evaluator_builder"

module Vexi
  class Builder
    class BuilderError < StandardError; end

    def initialize(config)
      @config = T.let(config, Configuration)

      @adapter_builder = T.let(Builders::AdapterBuilder.new(config), Builders::AdapterBuilder)
      @cache_builder = T.let(Builders::CacheBuilder.new(config), Builders::CacheBuilder)
      @circuit_breaker_builder = T.let(Builders::CircuitBreakerBuilder.new(config), Builders::CircuitBreakerBuilder)
      @custom_gates_evaluator_builder = T.let(Builders::CustomGatesEvaluatorBuilder.new(config), Builders::CustomGatesEvaluatorBuilder)
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

    def fallback_evaluator(fallback_evaluator)
      @config.fallback_evaluator = fallback_evaluator
    end
  end
end
