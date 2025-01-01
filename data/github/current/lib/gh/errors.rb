# typed: strict
# frozen_string_literal: true

module GH
  module Errors
    DomainError = Class.new(StandardError)
    DataStoreUnavailableError = Class.new(DomainError)

    class ObjectNotFound < DomainError
      extend T::Helpers

      sig { params(expected_type: Module).void }
      def initialize(expected_type:)
        super "#{expected_type} could not be found"
        @expected_type = expected_type
      end

      sig { returns(Module) }
      attr_reader :expected_type
    end
  end
end
