# typed: true
# frozen_string_literal: true

# A wrapper for Zuora Payment objects that were processed by PayPal
class Billing::Zuora::Payment::PaypalPayment
  extend T::Sig

  sig { returns(T.nilable(String)) }
  attr_reader :processor_response
  sig { returns(T.nilable(String)) }
  attr_reader :processor_response_code

  delegate :gateway_state, :payment_method_snapshot, to: :zuora_payment
  delegate :payment_number, :reference_id, to: :zuora_payment, private: true

  # Public: Initialize a new Zuora::Payment::PayPal
  sig { params(zuora_payment: Billing::Zuora::Payment).void }
  def initialize(zuora_payment)
    @zuora_payment = zuora_payment
    @processor_response = zuora_payment.gateway_response
    @processor_response_code = zuora_payment.gateway_response_code
  end

  # Public: Decorate a BillingTransaction object with PayPal details
  #
  # See Billing::Zuora::Payment#decorate_billing_transaction for more
  # information.
  sig { params(billing_transaction: Billing::BillingTransaction).void }
  def decorate_billing_transaction(billing_transaction)
    billing_transaction.payment_type = :paypal
    billing_transaction.paypal_email = payment_method_snapshot["PaypalEmail"]
    billing_transaction.last_status = transaction_status
    billing_transaction.transaction_id = transaction_id
  end

  # Public: The Billing::BillingTransactionStatuses status of the transaction
  # based on the normalized state from Zuora
  sig { returns(T.nilable(Integer)) }
  def transaction_status
    case gateway_state
    when Billing::Zuora::Payment::GatewayState::Settled
      Billing::BillingTransactionStatuses::ALL[:settled]
    when Billing::Zuora::Payment::GatewayState::Submitted
      Billing::BillingTransactionStatuses::ALL[:submitted_for_settlement]
    when Billing::Zuora::Payment::GatewayState::NotSubmitted, Billing::Zuora::Payment::GatewayState::FailedToSettle
      Billing::BillingTransactionStatuses::ALL[:processor_declined]
    else
      Failbot.report(
        Billing::Zuora::Payment::UnknownGatewayState.new("received unknown Paypal gateway state `#{gateway_state}` from Zuora for `#{payment_number}`"),
      )

      nil
    end
  end

  private

  sig { returns(Billing::Zuora::Payment) }
  attr_reader :zuora_payment

  # Private: the reference number for the transaction.
  # Since Paypal does not give Zuora a transaction ID for failed transactions
  # we use Zuora's payment number to reference it
  sig { returns(String) }
  def transaction_id
    if Billing::BillingTransactionStatuses.success?(transaction_status)
      reference_id
    else
      payment_number
    end
  end
end
