# typed: strict
# frozen_string_literal: true

module FeatureManagement
  module Core
    class Operation
      sig { returns(String) }
      attr_reader :id

      sig { returns(T::Boolean) }
      attr_reader :done

      sig { returns(Integer) }
      attr_reader :status_code

      sig { params(id: String, done: T::Boolean, status_code: Integer).void }
      def initialize(id, done, status_code)
        @id = T.let(id, String)
        @done = T.let(done, T::Boolean)
        @status_code = T.let(status_code, Integer)
      end
    end
  end
end
