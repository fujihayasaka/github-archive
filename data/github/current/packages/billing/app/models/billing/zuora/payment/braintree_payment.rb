# typed: strict
# frozen_string_literal: true

# A wrapper for Zuora Payment objects that were processed by Braintree
class Billing::Zuora::Payment::BraintreePayment
  extend T::Sig

  include GitHub::Memoizer

  sig { returns(T.nilable(String)) }
  attr_reader :transaction_id

  # Public: Initialize a new Zuora::Payment::Braintree
  sig { params(zuora_payment: Billing::Zuora::Payment).void }
  def initialize(zuora_payment)
    @transaction_id = T.let(zuora_payment.reference_id, T.nilable(String))
  end

  # Public: Decorate a BillingTransaction object with Braintree details
  #
  # See Billing::Zuora::Payment#decorate_billing_transaction for more
  # information.
  sig { params(billing_transaction: Billing::BillingTransaction).void }
  def decorate_billing_transaction(billing_transaction)
    billing_transaction.payment_type = :credit_card

    # If there is no Braintree transaction, then this transaction was
    # rejected by Zuora or by Braintree before an authorization occured,
    # so we treat it as declined.
    braintree_transaction = self.braintree_transaction
    unless braintree_transaction
      billing_transaction.last_status = :failed
      return
    end

    credit_card_details = braintree_transaction.credit_card_details

    billing_transaction.bank_identification_number = credit_card_details.bin
    billing_transaction.last_four = credit_card_details.last_4
    billing_transaction.country_of_issuance = credit_card_details.country_of_issuance
    billing_transaction.last_status = braintree_transaction.status
    billing_transaction.settlement_batch_id = braintree_transaction.settlement_batch_id

    braintree_transaction.status_history.each do |status_detail|
      next if billing_transaction.statuses.any? { |status| status.status == status_detail.status }
      billing_transaction.statuses.build(status_detail: status_detail)
    end
  end

  # Public: The transaction details from the Braintree gateway
  sig { returns(T.nilable(Braintree::Transaction)) }
  memoize def braintree_transaction
    ::Braintree::Transaction.find(transaction_id)
  rescue ArgumentError, Braintree::NotFoundError
    nil
  end

  # Public: The credit card details associated with the transaction
  sig { returns(T.nilable(Braintree::Transaction::CreditCardDetails)) }
  def credit_card_details
    braintree_transaction&.credit_card_details
  end

  # Public: The processor response from Braintree
  sig { returns(T.nilable(String)) }
  def processor_response
    braintree_transaction&.processor_response_text
  end

  # Public: The processor response code from Braintree
  sig { returns(T.nilable(String)) }
  def processor_response_code
    braintree_transaction&.processor_response_code
  end
end
