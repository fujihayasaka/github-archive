# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require "vexi/configuration"
require "vexi/caches/in_memory"

module Vexi
  module Builders
    class CircuitBreakerBuilder
      def initialize(config)
        @config = T.let(config, Configuration)
      end

      def with_adapter_circuit_breaker(circuit_breaker_config)
        @config.adapter_breaker_config = circuit_breaker_config
      end

      def with_cache_circuit_breaker(circuit_breaker_config)
        @config.cache_breaker_config = circuit_breaker_config
      end
    end
  end
end
