# typed: strict
# frozen_string_literal: true

module Billing
  class Response

    sig { params(content: T.untyped).returns(Billing::Success) }
    def self.success(content)
      Billing::Success.new(content)
    end

    sig do
      params(
        content: T.untyped,
        code:    T.nilable(String),
        message: T.nilable(String)
      ).returns(Billing::Error)
    end
    def self.error(content, code: nil, message: nil)
      Billing::Error.new(content, code: code, message: message)
    end

    sig { returns(T.untyped) }
    attr_reader :content

    sig { returns(T::Boolean) }
    attr_reader :success

    sig { params(content: T.untyped, success: T::Boolean).void }
    def initialize(content:, success:)
      @content = content
      @success = success
    end

    sig { returns(T::Boolean) }
    def success?
      success
    end

    sig { returns(T::Boolean) }
    def error?
      !success
    end
  end
end
