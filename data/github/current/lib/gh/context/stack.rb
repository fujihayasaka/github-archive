# typed: strict
# frozen_string_literal: true

module GH
  module Context
    class Stack
      extend T::Generic

      Value = type_member

      sig { params(seed: Value).void }
      def initialize(seed)
        @values = T.let([], T::Array[Value])
        @values.push(seed)
      end

      sig { params(service: Value).returns(Value) }
      def push(service)
        @values.push(service)
        service
      end

      sig { returns(T.nilable(Value)) }
      def pop
        @values.pop
      end

      sig { returns(T.nilable(Value)) }
      def peek
        @values.last
      end

      delegate :each, :map, to: :@values
    end
  end
end
