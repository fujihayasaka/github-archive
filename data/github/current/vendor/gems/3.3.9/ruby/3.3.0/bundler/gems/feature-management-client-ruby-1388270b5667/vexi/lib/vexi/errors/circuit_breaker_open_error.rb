# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module Vexi
  module Errors
    class CircuitBreakerOpenError < StandardError
      attr_reader :entity_type_name

      attr_reader :operation

      def initialize(entity_type_name, operation)
        @entity_type_name = T.let(entity_type_name, String)
        @operation = T.let(operation, String)
        super("service #{@entity_type_name} attempted to perform operation #{@operation} but the circuit breaker was open")
      end
    end
  end
end
