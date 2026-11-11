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
    class TemporaryError < Error; end
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

    # These errors are not raised automatically by the Zuorest client, instead the caller
    # should use error_from_response to check for and raise these errors as necessary.
    RETRYABLE_RESPONSE_ERRORS = T.let([
      ::Billing::Zuora::InternalError,
      ::Billing::Zuora::TemporaryError,
      ::Billing::Zuora::LockCompetitionError,
    ], T::Array[T.untyped])

    # https://developer.zuora.com/docs/guides/error-codes
    ERROR_CATEGORY_CODES = T.let({
      20 => InvalidFormatOrValueError,
      50 => LockCompetitionError,
      60 => InternalError,
      61 => TemporaryError,
    }.freeze, T::Hash[Integer, T.class_of(Billing::Zuora::Error)])

    sig { params(response: T.untyped).returns(T.nilable(Billing::Zuora::Error)) }
    def self.error_from_response(response)
      return if response.nil?

      result = GitHub::Billing::Result.from_zuora(response)
      return if result.success?

      error_category_code = result.error_code.to_i % 100
      error = ERROR_CATEGORY_CODES[error_category_code]
      return if error.nil?

      error.new(result.error_message, result.error_code)
    end
  end
end
