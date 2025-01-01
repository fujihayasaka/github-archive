# frozen_string_literal: true
#              



module Vexi
  module Errors
    class CircuitBreakerOpenError < StandardError
      attr_reader :entity_type_name

      attr_reader :operation

      def initialize(entity_type_name, operation)
        @entity_type_name =      (entity_type_name        )
        @operation =      (operation        )
        super("service #{@entity_type_name} attempted to perform operation #{@operation} but the circuit breaker was open")
      end
    end
  end
end
