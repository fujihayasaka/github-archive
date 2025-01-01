# typed: strict
# frozen_string_literal: true

module GitHub
  class ResilienceResult
    extend T::Generic

    ResultType = type_member

    sig { params(value: ResultType, used_fallback: T::Boolean).void }
    def initialize(value, used_fallback:)
      @value = value
      @used_fallback = used_fallback
    end

    sig { returns(T::Boolean) }
    def used_fallback?
      @used_fallback
    end

    sig { returns(ResultType) }
    attr_reader :value
  end
end
