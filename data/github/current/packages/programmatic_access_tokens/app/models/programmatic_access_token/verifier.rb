# typed: true
# frozen_string_literal: true

module ProgrammaticAccessToken
  class Verifier
    SUCCESS_RESULT = :RESULT_SUCCESS
    IGNORE_RESULTS = %w[RESULT_EXPIRED RESULT_REVOKED].freeze

    def initialize(tokens)
      @tokens = tokens
    end

    def self.perform(tokens)
      new(tokens).perform
    end

    def perform
      verify_credentials_response = credential_manager.verify_credentials(credentials)
      # We cannot return early if the result isn't RESULT_SUCCESS
      # as that will affect all the other tokens in the request
      # Let the caller decide how to handle the responses
      verify_credentials = verify_credentials_response.responses
      Result.success(verify_credentials)
    rescue ::Authnd::Proto::Error, Faraday::Error => err
      Failbot.report!(err) unless ignorable_error?(err)
      Result.failed(err.message)
    end

    private

    def ignorable_error?(error)
      error.is_a?(Result::Error) && IGNORE_RESULTS.include?(error.message)
    end

    def credential_manager
      ::GitHub::Authnd.credential_manager
    end

    def credentials
      credentials = []
      @tokens.map do |token|
        # Currently, we are only verifying access_tokens (FG-PATs)
        # When we need to verify other types of tokens, we can check the token prefix
        # and use the Proto::Credentials...
        credentials << ::Authnd::Proto::Credentials::access_token(token)
      end
      credentials
    end
  end
end
