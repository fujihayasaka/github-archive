# typed: strict
# frozen_string_literal: true

# A wrapper for Zuora Payment objects that provides easy access to payment
# gateway-specific transaction details
class Billing::Zuora::Payment
  include GitHub::Memoizer

  extend T::Sig

  sig { returns(Zuorest::Model::Payment) }
  attr_reader :zuora_payment

  sig { returns(T.nilable(Billing::Types::Account)) }
  attr_accessor :billable_entity

  IMPROPER_GATEWAY_METRIC = "zuora.payment.improper_payment_gateway"
  IMPROPER_GATEWAY_COUNT_METRIC = T.let("#{IMPROPER_GATEWAY_METRIC}.count", String)
  IMPROPER_GATEWAY_AMOUNT_METRIC = T.let("#{IMPROPER_GATEWAY_METRIC}.amount_in_cents", String)

  class UnknownGateway < ::Billing::Zuora::Error; end
  class UnknownGatewayState < StandardError; end

  # Public: Find a payment by its ID
  sig { params(zuora_id: T.nilable(String)).returns(Billing::Zuora::Payment) }
  def self.find(zuora_id)
    zuora_payment = Zuorest::Model::Payment.find(zuora_id)
    new(zuora_payment)
  end

  sig { params(zuora_payment: Zuorest::Model::Payment).void }
  def initialize(zuora_payment)
    @zuora_payment = zuora_payment
  end

  # Public: The Zuora-assigned payment ID
  sig { returns(String) }
  def id
    zuora_payment.id
  end

  # Public: The Zuora account ID related to this payment
  sig { returns(String) }
  def account_id
    zuora_payment["AccountId"]
  end

  # Public: The amount of the payment
  sig { returns(BigDecimal) }
  def amount
    money_amount.dollars
  end

  # Public: The amount of the payment in cents
  sig { returns(Integer) }
  def amount_in_cents
    money_amount.cents
  end

  # Public: The date when the payment was created in Zuora
  sig { returns(Time) }
  def created_date
    Time.parse(zuora_payment["CreatedDate"])
  end

  # Public: The amount of the payment that has been refunded
  sig { returns(Billing::Types::NonMoneyNumeric) }
  def refund_amount
    zuora_payment["RefundAmount"]
  end

  # Public: The status of the payment transaction
  sig { returns(String) }
  def status
    zuora_payment["Status"]
  end

  # Public: Decorate a BillingTransaction object with payment details
  #
  # This method will mutate the fields of the provided billing_transaction
  # with details about the payment that are specific to the type of payment.
  sig { params(billing_transaction: Billing::BillingTransaction).void }
  def decorate_billing_transaction(billing_transaction)
    billing_transaction.transaction_id = reference_id

    gateway_transaction.decorate_billing_transaction(billing_transaction)
  end

  # Public: The payment gateway that processed this transaction
  sig { returns(String) }
  def gateway
    zuora_payment["Gateway"]
  end

  # Public: Does the payment use the Sponsors-specific payment gateway?
  sig { returns(T::Boolean) }
  def sponsors_gateway?
    gateway == Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2
  end

  # Public: Does the payment use the general-purpose Stripe payment gateway?
  sig { returns(T::Boolean) }
  def general_purpose_stripe_gateway?
    gateway == Billing::Zuora::PaymentGateway::STRIPE_V3
  end

  # Public: Is Stripe the gateway that processed this transaction?
  sig { returns(T::Boolean) }
  def stripe?
    gateway_transaction.is_a? ::Billing::Zuora::Payment::StripePayment
  end

  # Public: Is Paypal the gateway that processed this transaction?
  sig { returns(T::Boolean) }
  def paypal?
    gateway_transaction.is_a? ::Billing::Zuora::Payment::PaypalPayment
  end

  # Public: The gateway response for this transaction
  sig { returns(T.nilable(String)) }
  def gateway_response
    zuora_payment["GatewayResponse"]
  end

  # Public: The gateway response code for this transaction
  sig { returns(T.nilable(String)) }
  def gateway_response_code
    zuora_payment["GatewayResponseCode"]
  end

  # Public: The state of the transaction in the upstream gateway, normalized
  # by Zuora
  #
  # https://knowledgecenter.zuora.com/Zuora_Billing/Billing_and_Payments/K_Payment_Operations/Electronic_Payment_Processing
  # - Submitted: The payment is submitted to the bank.
  # - NotSubmitted:  The payment is not submitted to the bank.
  # - Settled: The payment is successfully debited from the payer and credited to the payee.
  # - FailedToSettle:  A settlement error or a post-settlement exception occurs.
  #                    The payment might be rejected by the bank, or a chargeback for credit card or a reversal
  #                    for direct debit might occur.
  class GatewayState < T::Enum
    enums do
      Submitted = new("Submitted")
      NotSubmitted = new("NotSubmitted")
      Settled = new("Settled")
      FailedToSettle = new("FailedToSettle")
    end
  end
  sig { returns(GatewayState) }
  def gateway_state
    GatewayState.deserialize(zuora_payment["GatewayState"])
  end

  # Public: The gateway-specific details about the transaction
  #
  # Returns Billing::Zuora::Payment::Braintree or similar class
  sig do
    returns(
      T.any(
        Billing::Zuora::Payment::StripePayment,
        Billing::Zuora::Payment::BraintreePayment,
        Billing::Zuora::Payment::PaypalPayment
      )
    )
  end
  memoize def gateway_transaction
    name = gateway
    case name
    when *Billing::Zuora::PaymentGateway::STRIPE_GATEWAYS then ::Billing::Zuora::Payment::StripePayment.new(self)
    when "Braintree" then ::Billing::Zuora::Payment::BraintreePayment.new(self)
    when "Paypal" then ::Billing::Zuora::Payment::PaypalPayment.new(self)
    else
      raise UnknownGateway, "unknown gateway: #{name}"
    end
  end

  # Public: Is this payment a retry for a previous failed charge?
  sig { returns(T::Boolean) }
  def is_retry?
    num_consecutive_failures > 0
  end

  sig { returns(Integer) }
  def num_consecutive_failures
    payment_method_snapshot["NumConsecutiveFailures"]
  end

  sig { returns(String) }
  def payment_method_id
    zuora_payment["PaymentMethodId"]
  end

  sig { returns(T.nilable(String)) }
  def payment_method_snapshot_id
    zuora_payment["PaymentMethodSnapshotId"]
  end

  # Public: The Zuora payment method snapshot for this transaction
  sig { returns(T::Hash[String, T.untyped]) }
  memoize def payment_method_snapshot
    GitHub.zuorest_client.get_payment_method_snapshot(payment_method_snapshot_id)
  end

  # Public: The processor response from the processing gateway
  sig { returns(T.nilable(String)) }
  def processor_response
    gateway_transaction.processor_response
  end

  # Public: The processor response code from the processing gateway
  sig { returns(T.nilable(String)) }
  def processor_response_code
    gateway_transaction.processor_response_code
  end

  # Public: The reference ID (or transaction ID) for the transaction
  sig { returns(T.nilable(String)) }
  def reference_id
    zuora_payment["ReferenceId"]
  end

  # Public: A zuora provided number to reference a payment
  sig { returns(String) }
  def payment_number
    zuora_payment["PaymentNumber"]
  end
  alias_method :number, :payment_number

  # Public: Finds all the invoices the payment was applied to
  sig { returns(T::Array[Billing::Zuora::Invoice]) }
  def invoices
    ::Billing::Zuora::Invoice.invoices_for_transaction(id, billable_entity: billable_entity)
  end

  # Public: A list of invoice items that the payment was applied to
  sig do
    returns(T::Array[Billing::Zuora::InvoiceItem])
  end
  memoize def invoice_items
    invoices.flat_map(&:invoice_items)
  end

  sig { returns(T::Array[Billing::Zuora::SubscribableInvoiceItem]) }
  memoize def subscribable_invoice_items
    T.cast(invoice_items.select(&:subscribable?), T::Array[Billing::Zuora::SubscribableInvoiceItem])
  end

  # Public: The Bank Identification Number for the Payment Method used
  sig { returns(T.nilable(String)) }
  def bank_identification_number
    zuora_payment["BankIdentificationNumber"]
  end

  sig { returns(T::Hash[Symbol, String]) }
  def sponsors_metadata
    if stripe?
      { stripe_charge_id: reference_id }
    else
      { paypal_id: reference_id }
    end
  end

  # Public: Whether the payment references invoices that include sponsorship charges
  sig { returns(T::Boolean) }
  memoize def includes_sponsorship?
    subscribable_invoice_items.any? do |item|
      item.sponsors_item? && item.charge_amount.positive?
    end
  end

  # Public: Emit payment metrics
  sig { void }
  def instrument
    instrument_improper_gateway if improper_gateway_reason.present?
  end

  private

  sig { returns(Billing::Money) }
  def money_amount
    ::Billing::Money.new(zuora_payment["Amount"] * 100)
  end

  # Private: Instrument the usage of an improper/unexpected Zuora payment gateway
  #
  # Sponsorship and non-sponsorship money shouldn't use the same payment gateway, as those funds shouldn't
  # be co-mingled.
  sig { void }
  def instrument_improper_gateway
    datadog_tags = [
      "details:#{improper_gateway_reason}",
      "gateway:#{gateway.parameterize}", # e.g., "gateway:stripe-v3"
    ]
    GitHub.dogstats.increment(IMPROPER_GATEWAY_COUNT_METRIC, tags: datadog_tags)
    GitHub.dogstats.count(IMPROPER_GATEWAY_AMOUNT_METRIC, amount_in_cents, tags: datadog_tags)
    GitHub.logger.error("Improper Zuora payment gateway", {
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.billing.zuora.account.id": account_id,
      "gh.billing.zuora.payment.improper_gateway.details": improper_gateway_reason,
      "gh.billing.zuora.payment.id": id,
      "gh.billing.zuora.payment.gateway": gateway,
    })

    nil
  end

  # Private: Get reason regarding the usage of an improper gateway.
  sig { returns(T.nilable(String)) }
  memoize def improper_gateway_reason
    if includes_sponsorship?
      if !sponsors_gateway?
        "sponsorship-payment-using-non-sponsors-gateway"
      end
    else
      if sponsors_gateway?
        "general-payment-using-sponsors-gateway"
      elsif stripe? && !general_purpose_stripe_gateway?
        "general-stripe-payment-using-non-general-purpose-stripe-gateway"
      end
    end
  end
end
