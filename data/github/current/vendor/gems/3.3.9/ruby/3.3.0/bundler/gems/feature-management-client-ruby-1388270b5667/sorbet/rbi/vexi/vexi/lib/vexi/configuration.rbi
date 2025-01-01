# frozen_string_literal: true
# typed: strict

module Vexi
  class Configuration
    extend T::Sig

    sig { returns(T.nilable(CircuitBreakerConfig)) }
    attr_accessor :adapter_breaker_config

    sig { returns(T.nilable(CircuitBreakerConfig)) }
    attr_accessor :cache_breaker_config

    sig { returns(T.nilable(CacheConfig)) }
    attr_reader :cache_config

    sig { returns(T.nilable(CustomGatesEvaluator)) }
    attr_reader :custom_gates_evaluator

    sig { returns(FallbackEvaluator) }
    attr_reader :fallback_evaluator

    sig { returns(T::Array[String]) }
    attr_reader :errors

    sig do
      params(
        adapter: T.nilable(Adapter),
        cache_config: T.nilable(CacheConfig),
        custom_gates_evaluator: T.nilable(CustomGatesEvaluator)
      ).void
    end
    def initialize(adapter: nil, cache_config: nil, custom_gates_evaluator: nil); end

    sig { returns(T::Boolean) }
    def configured?; end

    sig { returns(Client) }
    def create_instance; end

    sig { returns(Adapter) }
    def adapter; end

    sig { params(adapter: Adapter).void }
    def adapter=(adapter); end

    sig { params(cache_config: CacheConfig).void }
    def cache_config=(cache_config); end

    sig { params(custom_gates_evaluator: CustomGatesEvaluator).void }
    def custom_gates_evaluator=(custom_gates_evaluator); end

    sig { params(fallback_evaluator: FallbackEvaluator).void }
    def fallback_evaluator=(fallback_evaluator);  end

    sig { returns(T::Hash[Symbol, String]) }
    def context; end

    sig { returns(T::Boolean) }
    def valid?; end
  end
end
