# typed: strict
# frozen_string_literal: true

class Billing::Zuora::Payment::StripePayment
  include GitHub::Memoizer

  sig { returns(T.nilable(String)) }
  attr_reader :transaction_id
  sig { returns(T.nilable(String)) }
  attr_reader :processor_response
  sig { returns(T.nilable(String)) }
  attr_reader :processor_response_code
  sig { returns(String) }
  attr_reader :gateway

  sig { params(zuora_payment: Billing::Zuora::Payment).void }
  def initialize(zuora_payment)
    @transaction_id = T.let(zuora_payment.reference_id, T.nilable(String))
    @processor_response = T.let(zuora_payment.gateway_response, T.nilable(String))
    @processor_response_code = T.let(zuora_payment.gateway_response_code, T.nilable(String))
    @bank_identification_number = T.let(zuora_payment.bank_identification_number, T.nilable(String))
    @gateway = T.let(zuora_payment.gateway, String)
  end

  sig { params(billing_transaction: Billing::BillingTransaction).void }
  def decorate_billing_transaction(billing_transaction)
    billing_transaction.payment_type = :credit_card

    unless stripe_transaction
      billing_transaction.last_status = :failed
      return
    end

    billing_transaction.bank_identification_number = bank_identification_number.to_i
    if credit_card_details = self.credit_card_details
      billing_transaction.last_four = credit_card_details.last4
      billing_transaction.country_of_issuance = credit_card_details.country
    end
    billing_transaction.last_status = transaction_status
  end

  private

  sig { returns(T.nilable(String)) }
  attr_reader :bank_identification_number

  sig { returns(T.nilable(Stripe::Charge)) }
  memoize def stripe_transaction
    api_key = if gateway == Billing::Zuora::PaymentGateway::STRIPE_V3
      GitHub.stripe_v3_api_key
    else
      GitHub.stripe_api_key
    end
    return nil unless transaction_id = self.transaction_id

    begin
      ::Stripe::Charge.retrieve(transaction_id,
        { api_key: api_key }
      )
    rescue ::Stripe::InvalidRequestError
      nil
    end
  end

  # T.untyped and T.unsafe because the method chain here is not defined in the Stripe gem
  # and is dynamically generated from the Stripe API response
  # via method missing on Stripe::StripeObject
  # See https://docs.stripe.com/api/charges/object#charge_object-payment_method_details
  sig { returns(T.untyped) }
  def credit_card_details
    T.unsafe(stripe_transaction&.payment_method_details)&.card
  end

  sig { returns(T.nilable(Integer)) }
  def transaction_status
    case stripe_transaction&.status
    when "succeeded"
      Billing::BillingTransactionStatuses::ALL[:settled]
    when "pending"
      Billing::BillingTransactionStatuses::ALL[:settlement_pending]
    when "failed"
      Billing::BillingTransactionStatuses::ALL[:processor_declined]
    else
      Failbot.report(
        Billing::Zuora::Payment::UnknownGatewayState.new("received unknown Stripe gateway state `#{stripe_transaction&.status}`"),
        { "gh.billing.transaction.id" => transaction_id },
      )

      nil
    end
  end
end
