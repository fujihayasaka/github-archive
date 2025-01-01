# typed: strict
# frozen_string_literal: true

module Authz
  class Result < GH::Result
    Value = type_member { { upper: T::Boolean } }

    sig { returns(T::Array[StandardError]) }
    attr_reader :errors

    sig { params(allowed: T::Boolean, indeterminate: T::Boolean, errors: T::Array[StandardError]).void }
    def initialize(allowed:, indeterminate: false, errors: [])
      @allowed = T.let(allowed, T::Boolean)
      @errors = T.let(errors, T::Array[StandardError])
      @indeterminate = T.let(indeterminate, T::Boolean)
    end

    sig { returns(T::Boolean) }
    def allow?
      @allowed && !@indeterminate
    end

    sig { returns(T::Boolean) }
    def deny?
      !allow?
    end

    sig { returns(T::Boolean) }
    def indeterminate?
      @indeterminate
    end

    sig { override.returns(T::Boolean) }
    def ok?
      !indeterminate?
    end

    sig { override.returns(T.nilable(Value)) }
    def ok
      raise "not implemented"
    end

    sig { override.returns(T.nilable(Error[Value])) }
    def error
      raise "not implemented"
    end

    sig do
      override
      .type_parameters(:U)
      .params(
        block: T.proc.params(value: Value).returns(GH::Result[T.type_parameter(:U)])
      )
      .returns(GH::Result[T.type_parameter(:U)])
    end
    def and_then(&block)
      # this would be tricky to implement as this type wraps two distinct values (@allowed and @indeterminate)
      raise "not implemented"
    end

    sig do
      override
        .type_parameters(:U)
        .params(block: T.proc.params(value: GH::Result::Error[Value]).returns(GH::Result[T.type_parameter(:U)]))
        .returns(GH::Result[T.type_parameter(:U)])
    end
    def or_else(&block)
      raise "not implemented"
    end

    sig { override.returns(Value) }
    def unwrap!
      # this would be tricky to implement as this type wraps two distinct values (@allowed and @indeterminate)
      raise "not implemented"
    end
  end
end
