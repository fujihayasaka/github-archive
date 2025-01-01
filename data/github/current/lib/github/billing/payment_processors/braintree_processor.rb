# typed: strict
# frozen_string_literal: true

module GitHub::Billing
  # Our primary payment processor is Braintree which we use to process all
  # credit card and PayPal payments on GitHub.com.
  class PaymentProcessors::BraintreeProcessor < PaymentProcessors::PaymentProcessor

    SUCCESS_STATUSES = T.let(%w(settled settling submitted_for_settlement settlement_pending), T::Array[String])
    SLUG = "braintree"

    PROCESSOR_UNAVAILABLE_EXCEPTIONS = T.let([
      Timeout::Error,
      Errno::EINVAL,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      EOFError,
      Net::HTTPBadResponse,
      Net::HTTPHeaderSyntaxError,
      Net::ProtocolError,
      Braintree::ServiceUnavailableError,
      Braintree::ServerError,
      Errno::ETIMEDOUT,
      GitHub::Restraint::UnableToLock,
      Net::ReadTimeout,
    ], T::Array[T::Class[T.any(StandardError, Exception)]])

    # Public: Update a customer record with new payment instrument/billing details.
    sig do
      override.params(
        payment_details: PaymentProcessorPaymentDetails,
        blk: T.nilable(T.proc.params(arg0: PaymentProcessorRecord).void)
      ).returns(GitHub::Billing::Result)
    end
    def update_payment_details(payment_details, &blk)
      if customer_id.blank?
        return GitHub::Billing::Result.failure("No customer record")
      end

      begin
        response = persist_payment_details(payment_details)
      rescue *PROCESSOR_UNAVAILABLE_EXCEPTIONS => e
        Failbot.report(e, { "gh.customer.id" => customer_id })
        return GitHub::Billing::Result.failure \
          "We're having trouble connecting to our payment processor. Please try again later"
      end

      result = GitHub::Billing::Result.from_braintree(response)

      if response.success?
        response = T.cast(response, Braintree::SuccessfulResult)
        record = payment_processor_record_for_payment_method(response.credit_card || response.payment_method)
        yield record if block_given?
        result.record = record
      end
      result
    end

    sig { override.params(payment_details: PaymentProcessorPaymentDetails).returns(T::Hash[Symbol, T.untyped]) }
    def update_customer_contact(payment_details:)
      {}
    end

    # create or update or even use paypal when persisting the new payment details
    #
    # payment_details - A PaymentProcessorPaymentDetails of payment details.
    #
    # Returns a Braintree::SuccessfulResult or Braintree::ErrorResult
    sig { params(payment_details: PaymentProcessorPaymentDetails).returns(BraintreeResult) }
    def persist_payment_details(payment_details)
      if payment_details.update_card_on_file?
        update_credit_card(payment_details)
      elsif payment_details.credit_card?
        create_credit_card(payment_details)
      else
        create_paypal_account(payment_details)
      end
    end

    # Public: Clear all payment details.
    # It will no longer be possible to process payment for this customer.
    sig { override.returns(T::Boolean) }
    def clear_payment_details
      return false if customer_id.blank?

      begin
        customer = GitHub.dogstats.time("braintree.timing.customer_find") do
          Braintree::Customer.find(customer_id)
        end

        customer.payment_methods.map do |instrument|
          GitHub.dogstats.time("braintree.timing.payment_method_delete") do
            begin
              Braintree::PaymentMethod.delete(instrument.token)
            rescue Braintree::NotFoundError
              # This payment method has already been deleted from Braintree.
              true
            end
          end
        end.all?

      rescue Braintree::BraintreeError => boom
        Failbot.report(boom)
        false
      end
    end

    private

    ##
    # GitHub -> Braintree
    ##
    BraintreeResult = T.type_alias { T.any(Braintree::SuccessfulResult, Braintree::ErrorResult) }

    sig { params(payment_details: PaymentProcessorPaymentDetails).returns(BraintreeResult) }
    def create_credit_card(payment_details)
      credit_card = credit_card_params_from_payment_details(payment_details)

      GitHub.dogstats.time("braintree.timing.customer_create") do
        Braintree::CreditCard.create(credit_card)
      end
    end

    sig { params(payment_details: PaymentProcessorPaymentDetails).returns(BraintreeResult) }
    def update_credit_card(payment_details)
      credit_card = credit_card_params_from_payment_details(payment_details)
        .except(:number, :customer_id)

      GitHub.dogstats.time("braintree.timing.customer_update") do
        Braintree::CreditCard.update(payment_details.token, credit_card)
      end
    end

    PaymentMethodParams = T.type_alias { T::Hash[Symbol, T.untyped] }

    sig { params(payment_details: PaymentProcessorPaymentDetails).returns(PaymentMethodParams) }
    def credit_card_params_from_payment_details(payment_details)
      {
        customer_id: customer_id,
        number: payment_details.card_number,
        expiration_month: payment_details.expiration_month,
        expiration_year: payment_details.expiration_year,
        cvv: payment_details.cvv,

        billing_address: {
          country_code_alpha3: payment_details.country_code_alpha3,
          region: payment_details.region,
          postal_code: payment_details.postal_code },

        options: { make_default: true, verify_card: true },
      }
    end

    sig { params(payment_details: PaymentProcessorPaymentDetails).returns(BraintreeResult) }
    def create_paypal_account(payment_details)
      payment_method = payment_method_params_from_payment_details(payment_details)

      Braintree::PaymentMethod.create(payment_method)
    end

    sig { params(payment_details: PaymentProcessorPaymentDetails).returns(PaymentMethodParams) }
    def payment_method_params_from_payment_details(payment_details)
      {
        customer_id: customer_id,
        payment_method_nonce: payment_details.paypal_nonce,
        options: { make_default: true },
      }
    end

    ##
    # Braintree -> GitHub
    ##


    # Private: Create a PaymentProcessorRecord from a braintree payment method record.
    sig do
      params(
        payment_method: T.any(Braintree::CreditCard, Braintree::PayPalAccount),
        record: T.nilable(PaymentProcessorRecord)
      ).returns(PaymentProcessorRecord)
    end
    def payment_processor_record_for_payment_method(payment_method, record = nil)
      record ||= PaymentProcessorRecord.new(customer_id: customer_id)

      record.token = payment_method.token

      if payment_method.is_a?(Braintree::CreditCard)
        record.masked_number            = payment_method.masked_number
        record.expiration_month         = payment_method.expiration_month
        record.expiration_year          = payment_method.expiration_year
        record.card_type                = payment_method.card_type
        record.unique_number_identifier = payment_method.unique_number_identifier
      elsif payment_method.is_a?(Braintree::PayPalAccount)
        record.paypal_email = payment_method.email
      end

      if billing_address = payment_method.try(:billing_address)
        record.region              = billing_address.region
        record.postal_code         = billing_address.postal_code
        record.country_code_alpha3 = billing_address.country_code_alpha3
      end

      record
    end
  end
end
