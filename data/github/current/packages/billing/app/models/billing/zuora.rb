# typed: strict
# frozen_string_literal: true

module Billing
  module Zuora
    class Error < StandardError
      sig { params(message: T.nilable(String), code: T.untyped).void }
      def initialize(message = nil, code = nil)
        @code = code
        message = format_zuora_error_code_message(message, code) if code
        super(message)
        set_backtrace caller
      end

      sig { params(message: T.nilable(String), code: T.untyped).returns(String) }
      def format_zuora_error_code_message(message, code)
        "#{message} – Zuora Error Code: #{code}"
      end
    end

    class ResourceNotFoundError < Error; end

    class WebhookError < Error; end

    class MissingPaymentMethodError < Error; end
    class SynchronizationError < Error; end
    class InternalError < Error; end
    class LockCompetitionError < Error; end
    class InvalidFormatOrValueError < Error; end
    class SubscriptionCancelledError < Error; end
    class PendingTaxCalculationError < Error; end
    class OneTimeChargeUpdateError < Error; end
    SynchronizationCleanupError = Class.new(StandardError)

    RETRYABLE_ERRORS = T.let([
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::ETIMEDOUT,
      Faraday::ConnectionFailed,
      Faraday::ParsingError,
      Faraday::SSLError,
      Faraday::TimeoutError,
      Net::HTTPRequestTimeOut,
      Net::OpenTimeout,
      Net::ReadTimeout,
      Zuorest::HttpError,
    ], T::Array[T.untyped])
  end
end
