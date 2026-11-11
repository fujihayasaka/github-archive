# typed: strict
# frozen_string_literal: true

module CodeScanning
  class AgenticAutofixError < StandardError
    sig { returns(T.any(Symbol, Integer)) }
    attr_reader :status

    sig { returns(T.nilable(Symbol)) }
    attr_reader :error_type

    sig { params(message: String, error_type: T.nilable(Symbol), status: T.any(Symbol, Integer)).void }
    def initialize(message, error_type: nil, status: :internal_server_error)
      super(message)
      @error_type = error_type
      @status = status
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        message:,
        error_type:,
        error_source: "agentic_autofix",
      }.compact
    end
  end
end
