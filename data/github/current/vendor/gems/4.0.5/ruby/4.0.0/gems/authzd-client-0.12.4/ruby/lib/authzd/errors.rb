# frozen_string_literal: true

module Authzd
  class Error < StandardError; end
  class DecorationError < Error; end
  class IndeterminateError < Error; end
  class CAPUnknownError < Error; end

  # Twirp error codes that indicate the caller made a bad request.
  # These are deterministic — retrying won't change the outcome,
  # and they don't indicate server health issues.
  CLIENT_ERROR_CODES = %i[
    invalid_argument
    malformed
    not_found
    bad_route
    already_exists
    permission_denied
    unauthenticated
    failed_precondition
    out_of_range
  ].freeze

  # Raised when authzd returns a Twirp error caused by the client (e.g., invalid_argument).
  # These should NOT be retried and should NOT count toward circuit breaker failures.
  class ClientError < Error
    attr_reader :twirp_error

    def initialize(twirp_error)
      @twirp_error = twirp_error
      super(twirp_error.to_s)
    end

    def self.client_error?(res)
      res&.error.is_a?(::Twirp::Error) && CLIENT_ERROR_CODES.include?(res.error.code)
    end
  end

  class BatchError < IndeterminateError
    attr_reader :request

    def initialize(batch_request:)
      @request = batch_request
    end
  end
end
