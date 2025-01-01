# typed: strict
# frozen_string_literal: true

module Billing
  class Error < Billing::Response

    sig { returns(T.nilable(String)) }
    attr_reader :code

    sig { returns(T.untyped) }
    attr_reader :content

    sig { returns(T.nilable(String)) }
    attr_reader :message

    sig do
      params(
        content: T.untyped,
        code:    T.nilable(String),
        message: T.nilable(String)
      ).void
    end
    def initialize(content, code: nil, message: nil)
      super(content: content, success: false)
      @code = code
      @message = message
    end
  end
end
