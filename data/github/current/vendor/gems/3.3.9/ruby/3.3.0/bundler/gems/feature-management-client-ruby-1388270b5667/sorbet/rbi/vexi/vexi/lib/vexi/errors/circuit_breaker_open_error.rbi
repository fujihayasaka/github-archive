# frozen_string_literal: true
# typed: strict

module Vexi
  module Errors
    class CircuitBreakerOpenError < StandardError
      extend T::Helpers
      extend T::Sig

      sig { returns(String) }
      attr_reader :entity_type_name

      sig { returns(String) }
      attr_reader :operation

      sig { params(entity_type_name: String, operation: String).void }
      def initialize(entity_type_name, operation); end
    end
  end
end
