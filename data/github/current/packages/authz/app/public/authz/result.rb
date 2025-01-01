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
  end
end
