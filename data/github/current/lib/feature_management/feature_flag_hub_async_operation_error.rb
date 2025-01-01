# typed: strict
# frozen_string_literal: true

module FeatureManagement
  class FeatureFlagHubAsyncOperationError < StandardError
    sig { returns(Integer) }
    attr_reader :status_code

    sig { returns(T.nilable(String)) }
    attr_reader :message

    sig { returns(T.nilable(String)) }
    attr_reader :response_body

    sig { params(status_code: Integer, message: T.nilable(String), response_body: T.nilable(String)).void }
    def initialize(status_code, message, response_body)
      @status_code = T.let(status_code, Integer)
      @message = T.let(message, T.nilable(String))
      @response_body = T.let(response_body, T.nilable(String))
    end
  end
end
