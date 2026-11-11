# typed: strict
# frozen_string_literal: true

module OctoCore
  module Context
    class Stack
      extend T::Sig
      extend T::Generic
      extend Forwardable

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

      def_delegator :@values, :each
    end
  end
end
