# frozen_string_literal: true
# typed: strict

module Vexi
  class Builder
    extend T::Sig

    sig { params(config: Configuration).void }
    def initialize(config); end

    sig { returns(Builders::AdapterBuilder) }
    def adapter; end

    sig { returns(Builders::CacheBuilder) }
    def cache; end

    sig { returns(Builders::CircuitBreakerBuilder) }
    def circuit_breaker; end

    sig { returns(Builders::CustomGatesEvaluatorBuilder) }
    def custom_gates_evaluator; end

    sig { params(fallback_evaluator: Configuration::FallbackEvaluator).void }
    def fallback_evaluator(fallback_evaluator); end
  end
end
