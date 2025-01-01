# typed: strict
# frozen_string_literal: true

module Billing
  module PlanSubscription::SynchronizationEvents

    # Errors that should be retried when attempting to synchronize a plan subscription
    # Note: We need to include the exact error classes that we want to retry on, specifying
    #       superclasses won't work correctly.
    RETRYABLE_ERRORS = T.let(::Billing::Zuora::RETRYABLE_ERRORS + Billing::Braintree::RETRYABLE_ERRORS + [
      ::Billing::Zuora::SubscriptionCancelledError,
      ::Billing::Zuora::SynchronizationError,
    ], T::Array[T.class_of(StandardError)])

    # Errors that should be retried with more attempts than RETRYABLE_ERRORS
    EXTRA_RETRYABLE_ERRORS = T.let([
      GitHub::Restraint::UnableToLock,
      ::Billing::Zuora::InternalError,
      ::Billing::Zuora::LockCompetitionError,
    ], T::Array[T.class_of(StandardError)])

    # Errors that should be retried with a longer wait time than RETRYABLE_ERRORS
    DELAYED_RETRYABLE_ERRORS = T.let([
      ::Billing::Zuora::PendingTaxCalculationError,
      ::Billing::Zuora::OneTimeChargeUpdateError,
      Zuorest::GatewayTimeoutError,
    ], T::Array[T.class_of(StandardError)])

    # The total number of synchronization attempts that should be made for each category of retryable errors.
    RETRYABLE_ATTEMPTS = 5
    EXTRA_RETRYABLE_ATTEMPTS = 12
    DELAYED_RETRYABLE_ATTEMPTS = 8

    ACCOUNT_NOT_ACTIVE_ERROR = "Zuora account not active"
    TRADE_CONTROLS_ERROR = "Suspended due to trade restrictions"
    CANCELLED_SUBSCRIPTION_ERROR = "This action could not be performed, because you are trying to amend an cancelled subscription"
    PENDING_TAX_CALCULATION_ERROR = "There is an invoice pending tax calculation in progress for this account"
    MISSING_PAYMENT_METHOD_ERROR = "To collect payment, the customer account must have a default payment method"
    ONETIME_CHARGE_UPDATE_ERROR = "OneTime Charge can't be updated"

    # Base class for all other synchronization events
    class SynchronizationEvent
      extend T::Sig
      extend T::Helpers

      include GitHub::Memoizer

      abstract!

      sig { returns(T::Hash[String, Integer]) }
      attr_reader :attempts_per_exception

      # Internal: Initialize a SynchronizationEvent.
      #
      # result                 - A GitHub::Billing::Result returned from PlanSubscription::Synchronizer#create or #update
      # error                  - An Exception returned from PlanSubscription::Synchronizer#create or #update
      # attempts_per_exception - The number of synchronization attempts that have been made for each exception that has occurred
      sig { params(attempts_per_exception: T::Hash[String, Integer], result: T.nilable(GitHub::Billing::Result), error: T.nilable(StandardError)).void }
      def initialize(attempts_per_exception:, result: nil, error: nil)
        @result = result
        @error = error
        @attempts_per_exception = attempts_per_exception
      end

      sig { returns(T::Boolean) }
      def success?
        !failure?
      end

      sig { abstract.returns(T::Boolean) }
      def failure?; end

      sig { abstract.returns(T.nilable(String)) }
      def error_message; end

      # Internal: Error code associated with this event. May be nil.
      sig { overridable.returns(T.nilable(Billing::Types::NonMoneyNumeric)) }
      def error_code
        nil
      end

      # Internal: The underlying error associated with this result
      sig { returns(T.nilable(StandardError)) }
      def error
        @error
      end

      # Internal: Attributes that uniquely describe this event.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def attributes
        {
          attempts_per_exception: @attempts_per_exception,
          error: error_message
        }
      end

      # Internal: Whether this event should be tracked for SLO purposes.
      # We don't want to track declines or failures that will be retried.
      sig { returns(T::Boolean) }
      def track?
        return false if declined?
        success? || non_retryable_failure? || (failure? && final_attempt?)
      end

      # Internal: Whether synchronization should be retried for this event.
      #
      # Note: This needs to match what we actually retry in SynchronizePlanSubscriptionJob. Otherwise, we
      #       can end up tracking failures that are retryable, causing our SLO metrics to be incorrect.
      sig { returns(T::Boolean) }
      def retryable?
        return true if zuora_rate_limit_error?
        (RETRYABLE_ERRORS + EXTRA_RETRYABLE_ERRORS + DELAYED_RETRYABLE_ERRORS).include?(error.class)
      end

      # Internal: The total number of synchronization attempts that should be made for this event.
      sig { returns(Integer) }
      def max_attempts
        return 1 unless retryable?
        return GitHub::Billing::ZuoraRateLimitHandler::ZUORA_RATE_LIMIT_MAX_ATTEMPTS if zuora_rate_limit_error?
        return EXTRA_RETRYABLE_ATTEMPTS if EXTRA_RETRYABLE_ERRORS.include?(error.class)
        return DELAYED_RETRYABLE_ATTEMPTS if DELAYED_RETRYABLE_ERRORS.include?(error.class)
        RETRYABLE_ATTEMPTS
      end

      # Internal: Whether or not this is the final synchronization attempt for this event.
      sig { returns(T::Boolean) }
      def final_attempt?
        attempts == max_attempts
      end

      sig { returns(Integer) }
      def number_of_attempts_remaining
        max_attempts - attempts
      end

      sig { returns(T.nilable(T::Boolean)) }
      def declined?
        @result&.respond_to?(:declined?) && @result.declined?
      end

      sig { returns(T::Boolean) }
      def suspended_due_to_trade_restrictions?
        @result&.message == TRADE_CONTROLS_ERROR
      end

      sig { returns(T::Boolean) }
      def zuora_account_not_active?
        @result&.message == ACCOUNT_NOT_ACTIVE_ERROR
      end

      # Internal: The ID of the invoice that was created as a result of this synchronization event.
      sig { returns(T.nilable(String)) }
      memoize def invoice_id
        @result&.zuora_result&.dig("invoiceId")
      end

      protected

      # Return the number of attempts that have been made for this error
      sig { returns(Integer) }
      def attempts
        # Notes on @attempts_per_exception:
        #
        # The keys for this hash contain the names of the exceptions that have been retried, but
        # depending on what was passed to `retry_on` at the job level, it could look like:
        #
        #   { "[Zuorest::HttpError]" => 2, "[Billing::Zuora::SynchronizationError]" => 2 }
        #   OR
        #   { "[Zuorest::HttpError, Billing::Zuora::SynchronizationError]" => 4 }
        #
        # For more information, see the `exception_executions` variable in:
        #   https://github.com/rails/rails/blob/main/activejob/lib/active_job/exceptions.rb
        return 0 if error.nil?
        previous_attempts = @attempts_per_exception.find { |k, _| k.include?(error.class.to_s) }&.last
        (previous_attempts || 0) + 1
      end

      sig { returns(T::Boolean) }
      def non_retryable_failure?
        failure? && !retryable?
      end

      sig { returns(T::Boolean) }
      def zuora_rate_limit_error?
        error.class == Zuorest::TooManyRequestsError
      end
    end

    class SynchronizationResultEvent < SynchronizationEvent
      extend T::Sig
      extend T::Helpers
      # See: https://www.zuora.com/developer/api-reference/#section/Error-Handling/Error-Category-Codes
      ZUORA_ERROR_CATEGORY_CODES = T.let({
        20 => :invalid_format_or_value_error,
        50 => :lock_competition_error,
        60 => :internal_error
      }.freeze, T::Hash[Integer, Symbol])

      sig { override.returns(T::Boolean) }
      def failure?
        @result&.respond_to?(:failed?) && @result.failed?
      end

      sig { override.returns(T.nilable(String)) }
      def error_message
        @result&.error_message
      end

      sig { override.returns(T.nilable(Billing::Types::NonMoneyNumeric)) }
      def error_code
        @result&.error_code
      end

      sig { override.returns(T.nilable(StandardError)) }
      def error
        # Check for specific errors based on the message
        if missing_payment_method?
          return Billing::Zuora::MissingPaymentMethodError.new(error_message, error_code)
        elsif one_time_charge_update_error?
          return Billing::Zuora::OneTimeChargeUpdateError.new(error_message, error_code)
        elsif pending_tax_calculation?
          return Billing::Zuora::PendingTaxCalculationError.new(error_message, error_code)
        elsif subscription_cancelled?
          return Billing::Zuora::SubscriptionCancelledError.new(error_message, error_code)
        end

        # Check for specific errors based on the error category code
        if internal_error?
          return Billing::Zuora::InternalError.new(error_message, error_code)
        elsif lock_competition_error?
          return Billing::Zuora::LockCompetitionError.new(error_message, error_code)
        elsif invalid_format_or_value_error?
          return Billing::Zuora::InvalidFormatOrValueError.new(error_message, error_code)
        end

        # For all other failures that are not related to payment declines, return a generic error
        if failure? && !declined?
          Billing::Zuora::SynchronizationError.new(error_message, error_code)
        else
          nil
        end
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def attributes
        return {} if success?
        super.merge({
          external_result: @result&.external_result
        })
      end

      private

      sig { returns(T::Boolean) }
      def internal_error?
        ZUORA_ERROR_CATEGORY_CODES[error_category_code] == :internal_error
      end

      sig { returns(T::Boolean) }
      def lock_competition_error?
        ZUORA_ERROR_CATEGORY_CODES[error_category_code] == :lock_competition_error
      end

      sig { returns(T::Boolean) }
      def invalid_format_or_value_error?
        ZUORA_ERROR_CATEGORY_CODES[error_category_code] == :invalid_format_or_value_error
      end

      sig { returns(T.nilable(T::Boolean)) }
      def missing_payment_method?
        @result&.message&.include?(MISSING_PAYMENT_METHOD_ERROR)
      end

      sig { returns(T.nilable(T::Boolean)) }
      def one_time_charge_update_error?
        @result&.message&.include?(ONETIME_CHARGE_UPDATE_ERROR)
      end

      sig { returns(T.nilable(T::Boolean)) }
      def pending_tax_calculation?
        @result&.message&.include?(PENDING_TAX_CALCULATION_ERROR)
      end

      sig { returns(T.nilable(T::Boolean)) }
      def subscription_cancelled?
        @result&.message&.include?(CANCELLED_SUBSCRIPTION_ERROR)
      end

      # The last two digits of the error code represent the error category
      sig { returns(Integer) }
      def error_category_code
        error_code.to_i % 100
      end
    end

    class SynchronizationErrorEvent < SynchronizationEvent
      extend T::Sig
      extend T::Helpers

      sig { override.returns(T::Boolean) }
      def failure?
        true
      end

      sig { override.returns(T.nilable(String)) }
      def error_message
        error.try(:original_message) || error.to_s
      end
    end

    class SynchronizationSkippedEvent < SynchronizationEvent
      extend T::Sig
      extend T::Helpers

      sig { override.returns(T::Boolean) }
      def failure?
        true
      end

      sig { override.returns(T::Boolean) }
      def retryable?
        false
      end

      sig { override.returns(T.nilable(String)) }
      def error_message
        @result&.error_message
      end

      sig { override.returns(T::Boolean) }
      def track?
        false
      end
    end
  end
end
