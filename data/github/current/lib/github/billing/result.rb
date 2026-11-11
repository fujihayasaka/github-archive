# typed: true
# frozen_string_literal: true

module GitHub
  # A generic response/error wrapper for billing
  module Billing
    class Result
      extend Forwardable

      # Public: The Braintree result. This can be a Braintree::SuccessfulResult or a
      # Braintree::ErrorResult

      attr_accessor :braintree_result

      # Public: The Zuora result.

      attr_accessor :zuora_result

      # Public: All subscription updates that occurred within the same batch sent to Zuora

      attr_accessor :batch_zuora_results

      # Public: The status of the action. The action result will usually
      # have a `success?` method which states whether the action succeed. Otherwise
      # this can be `nil`.

      attr_reader :success

      # Public: A PaymentProcessorRecord which generally represents a customer
      # plus payment (credit card) and address information. Can be nil for failed
      # responses.

      attr_accessor :record

      # Public: A PaymentProcessorTransaction which represents some kind of payment
      # transaction, such as a charge or a refund. Can be nil for failed responses.

      attr_accessor :transaction

      # Public: A Billing::BillingTransaction. We store these transactions on our end.
      # Can be `nil`.

      attr_accessor :billing_transaction

      # Public: A Braintree::Transaction. Can be `nil`.

      attr_accessor :braintree_transaction

      # Public: Provides an instance of Github::Billing::ErrorMessage which
      # attempts to parse out the Braintree error result messages.

      attr_accessor :error_message
      alias :error :error_message
      alias :message :error_message

      attr_accessor :error_code
      alias :code :error_code

      def_delegators :@braintree_result, :credit_card, :payment_method

      # Public: Generate a Billing::Response from a Braintree API action/method.
      # This can return us a few things like:
      #
      #   - Braintree::ErrorResult
      #   - Braintree::SuccessfulResult
      #
      # result - A <Braintree::ErrorResult|Braintree::Result> instance. Primarily,
      #          any non `!` method off of the Braintree library.
      #
      # returns a Billing::Response instance.
      sig { params(result: T.any(Braintree::SuccessfulResult, Braintree::ErrorResult)).returns(GitHub::Billing::Result) }
      def self.from_braintree(result)
        response                       = new(result.try(:success?))
        response.braintree_result      = result
        response.braintree_transaction = result.transaction
        response.error_message         = ::GitHub::Billing::ErrorMessage.new(result).to_s unless result.success?
        response
      end

      # Public: Generate a Billing::Result from a Zuora API result.
      #
      # result - The Hash response from a Zuorest::RestClient request
      #
      # returns a Billing::Result instance.
      def self.from_zuora(result)
        success               = !!(result[:success] || result["success"] || result["Success"])
        error_message         = zuora_error_message(result)
        error_code            = zuora_error_code(result)
        response              = new(success, error_message, error_code)
        response.zuora_result = result
        response
      end

      # Public: Combine multiple Billing::Result into a single Billing::Result.
      sig { params(results: T::Array[GitHub::Billing::Result]).returns(GitHub::Billing::Result) }
      def self.from_results(results)
        if results.all?(&:success?)
          GitHub::Billing::Result.success
        else
          error = results.select(&:failed?).map(&:error_message).join(";")
          GitHub::Billing::Result.failure(error)
        end
      end

      def self.failure(error_message)
        new(false, error_message, nil, nil)
      end

      def self.success(billing_transaction = nil)
        new(true, nil, nil, billing_transaction)
      end

      def initialize(
        success,
        error_message = nil,
        error_code = nil,
        billing_transaction = nil
      )
        @success             = success
        @error_message       = error_message
        @error_code          = error_code
        @billing_transaction = billing_transaction
        nil
      end

      def success?
        !!@success
      end

      def failed?
        !@success
      end

      def declined?
        return true if error_message&.match(/declined/i)
        # This is an error from PayPal indicating that the account is not associated with a usable funding source.
        return true if error_message&.match(/The transaction did not complete with the customer'?s selected payment method/i)

        false
      end

      def external_result
        braintree_result || zuora_result
      end

      def on_success
        yield self if success?
        self
      end

      def on_failure
        yield self unless success?
        self
      end

      def to_s
        if success?
          "Success"
        else
          ERB::Util.force_escape("Error #{error_code}: #{error_message}")
        end
      end

      # Private: Parse an error message from a Zuora API result.
      #
      # result - The Hash response from a Zuorest::RestClient request
      #
      # Returns a String error message if it exists, otherwise nil
      def self.zuora_error_message(result)
        result.to_h.dig("reasons", 0, "message") || # REST
          result.to_h.dig("Errors", 0, "Message") # SOAP
      end
      private_class_method :zuora_error_message

      # Private: Parse an error code from a Zuora API result.
      #
      # result - The Hash response from a Zuorest::RestClient request
      #
      # Returns a Number error code if it exists, otherwise nil
      def self.zuora_error_code(result)
        result.to_h.dig("reasons", 0, "code") || # REST
          result.to_h.dig("Errors", 0, "Code") # SOAP
      end
      private_class_method :zuora_error_code
    end
  end
end
