# typed: true
# frozen_string_literal: true

module GitHub
  module Billing
    # Wrapper around Braintree transaction results that gives the best possible
    # error message to a user. Hopefully.
    class ErrorMessage
      # Public: Get the Braintree result.
      attr :result

      # Public: Initialize the message.
      #
      # result - The result object from Braintree
      def initialize(result)
        @result = result
      end

      # Public: Get a human readable error message.
      #
      # Returns a String.
      def to_s
        @to_s ||= begin
          base = ["Error processing payment"]

          if gateway_verification_failed?
            base << "Credit or debit card information is invalid. Please ensure the expiration date and CVV " \
              "are correct."
          else
            base << "Please contact your payment provider to resolve this issue."
          end

          base.join(" - ")
        end
      end

      # Returns `true` if the card failed at the processor. For example, because
      # it did not have enough funds.
      def card_processing_failed?
        transaction.status == "processor_declined" &&
          transaction.processor_response_text.present?
      end

      # Returns `true` if the card failed verifying the CVV or expiration date.
      def gateway_verification_failed?
        transaction.status == "gateway_rejected" &&
          transaction.gateway_rejection_reason.present?
      end

      # Public: generate a long description, including this error's metadata, so
      # that we can log this in stafftools or elsewhere for future reference.
      #
      # title - A String title of sorts, defaults to "Credit Card Failure".
      #
      # Returns a String.
      def description(title = "Credit Card Failure")
        [title, metadata.to_yaml].join("\n\n")
      end

      # Public: Hash of metadata associated with this failure message.
      #
      # Returns a Hash.
      def metadata
        {
          errors: self.to_s,
          result_message: result.message,
          result_params: result.params,
          result_errors: result.errors,
          result_credit_card_verification: result.credit_card_verification,
          transaction_status: transaction.status,
          transaction_response_code: transaction.processor_response_code,
          transaction_response_text: transaction.processor_response_text,
        }
      end

      # The "transaction" that can give us information about the status. Tries
      # for Braintree's `transaction` first, but since it might be nil, we
      # delegate to the `credit_card_verification`.
      #
      # Which can also be nil, if the CC number is invalid, for example.
      #
      # Returns an object that understands :status, :processor_response_code,
      # :processor_response_text.
      def transaction
        @transaction ||= if !result.transaction.nil?
          result.transaction
        elsif !result.credit_card_verification.nil?
          result.credit_card_verification
        else
          NullTransaction.new
        end
      end

      # When EVERYTHING that comes from Braintree is nil, fall back to this.
      # This is internal and should never reach the users (but will reach
      # Failbot).
      class NullTransaction
        def status
          nil
        end

        def processor_response_code
          nil
        end

        def processor_response_text
          "Braintree returned both a nil transaction and a nil credit_card_verification"
        end
      end
    end
  end
end
