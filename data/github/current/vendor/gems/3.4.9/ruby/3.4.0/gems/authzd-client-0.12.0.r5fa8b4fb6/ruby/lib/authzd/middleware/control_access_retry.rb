# frozen_string_literal: true

require_relative "base"

module Authzd
  module Middleware
    class ControlAccessRetry < Base

      DEFAULT_MAX_ATTEMPTS = 2
      DEFAULT_RETRYABLE_ERRORS = [StandardError]
      INTERNAL_METADATA_TIMEOUT_FACTOR = "__timeout_factor__"

      # Initializes a new instance of the middleware
      # - max_attempts an integer representing how many times the middleware
      # will retry the request, in case it keeps failing.
      # - retryable_errors, an array of exception classes to rescue and retry
      # - options, a Hash of options to pass when building the Retry middleware
      # - options[:instrumenter] an object responding to `instrument` for the purpose of
      #  having observability about the events happening in the middelware.
      # - options[:wait_seconds] a float representing the time to wait (by calling
      # `sleep`) between tries
      #
      def initialize(instrumenter: Instrumenters::Noop, max_attempts: DEFAULT_MAX_ATTEMPTS, retryable_errors: DEFAULT_RETRYABLE_ERRORS, **options)
        @instrumenter = instrumenter
        @max_attempts = max_attempts
        @retryable_errors = Array(retryable_errors)
        # always retry on indeterminate
        @retryable_errors << Authzd::IndeterminateError
        @options = options
        @wait_seconds = options.delete(:wait_seconds)&.to_f
        @retry_factor = options.delete(:retry_factor)
      end

      # Applies retry logic to request execution
      def perform(req, metadata = {})
        attempt ||= 1

        rpc = req.rpc_name
        instrument("tried", attempt: attempt, authz_request: req, rpc: rpc)

        metadata[INTERNAL_METADATA_TIMEOUT_FACTOR] = attempt if @retry_factor
        res = request.perform(req, metadata)

        raise Authzd::IndeterminateError.new(extract_twirp_error(res)) if indeterminate?(res)

        instrument("succeeded", attempt: attempt, authz_request: req, rpc: rpc)

        res
      rescue *@retryable_errors => err
        if attempt == @max_attempts
          instrument("failed", attempt: attempt, authz_request: req, error: err, rpc: rpc, indeterminate: indeterminate?(res))
          raise
        end
        if @wait_seconds
          sleep @wait_seconds
          instrument("waited", attempt: attempt, wait_seconds: @wait_seconds, authz_request: req, error: err, rpc: rpc)
        end
        attempt += 1
        retry
      rescue => err
        instrument("failed", attempt: attempt, authz_request: req, error: err, rpc: rpc)
        raise
      end

      protected

      def middleware_name
        :control_access_retry
      end

      def extract_twirp_error(res)
        return "unknown error" if res.error.nil?

        res.error.to_s
      end

      def indeterminate?(res)
        return true if res.nil?
        return true if res.data.nil?
        return true if res.data.result.nil?

        Authzd::Proto::Result::resolve(res.data.result.outcome) == Authzd::Proto::Result::INDETERMINATE
      end
    end
  end
end
