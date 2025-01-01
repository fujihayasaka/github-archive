# frozen_string_literal: true
# typed: strict

module Vexi
  module Builders
    class CircuitBreakerBuilder
      extend T::Sig

      sig { params(config: Configuration).void }
      def initialize(config)
        @config = T.let(config, Configuration)
      end

      sig { params(circuit_breaker_config: CircuitBreakerConfig).void }
      def with_adapter_circuit_breaker(circuit_breaker_config); end

      sig { params(circuit_breaker_config: CircuitBreakerConfig).void }
      def with_cache_circuit_breaker(circuit_breaker_config); end
    end
  end
end
