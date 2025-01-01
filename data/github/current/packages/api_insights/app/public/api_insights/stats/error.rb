# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class Error < StandardError

    sig { returns(ErrorCode) }
    attr_reader :code

    sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    attr_reader :details

    sig { params(code: ErrorCode, details: T::Hash[T.any(String, Symbol), T.untyped]).void }
    def initialize(code, details = {})
      @code = code
      @details = details
      super("#{code.to_error_message} Details: #{details}")
    end

    sig { returns(String) }
    def to_s
      "ApiInsights::Stats::Error[#{@code.serialize}]: #{@code.to_error_message} Details: #{@details}"
    end
  end
end
