# typed: strict
# frozen_string_literal: true

class Billing::Stripe::Webhooks::PaymentSucceeded
  include ::GitHub::Memoizer

  class ZuoraAccountCreationError < StandardError; end

  # Public: The description field of any line items whose amount is a fee that GitHub charges will include this
  # text, case-insensitive.
  SERVICE_FEE_DESCRIPTION_REGEX = /\bservice fee\b/i

  DATADOG_PREFIX = "stripe.invoice_payment_succeeded"

  # Public: Check if the given invoice line item is one representing a fee GitHub charges.
  #
  # invoice_line_item - a Stripe::InvoiceLineItem
  #
  sig { params(invoice_line_item: ::Stripe::InvoiceLineItem).returns(T::Boolean) }
  def self.service_fee_line_item?(invoice_line_item)
    # Invoices created via Sponsors::CreateStripeInvoice will include line item metadata:
    invoice_line_item.metadata["service_fee"].to_s == "true" ||

      # Invoices created from Stripe directly won't have line item metadata, so we rely on how they're described:
      !!(invoice_line_item.description =~ SERVICE_FEE_DESCRIPTION_REGEX)
  end

  # Public: Handle the payment succeeded webhook payload
  # This webhook indicates that a customer has successfully paid an invoice.
  #
  sig { params(webhook: ::Billing::StripeWebhook).returns(T.nilable(::GitHub::Billing::Result)) }
  def self.perform(webhook)
    new(webhook).perform
  end

  # Public: Initializes a new PaymentSucceeded webhook handler
  #
  sig { params(webhook: ::Billing::StripeWebhook).void }
  def initialize(webhook)
    event = webhook.stripe_event
    stripe_invoice = T.let(T.cast(event.data.object, ::Stripe::Invoice), ::Stripe::Invoice)
    @invoice = T.let(Billing::Stripe::Invoice.from_invoice(stripe_invoice), Billing::Stripe::Invoice)
    @webhook = webhook
  end

  # Public: Handle the payment succeeded webhook payload
  sig { returns(T.nilable(::GitHub::Billing::Result)) }
  def perform
    return unless invoice.paid?
    return unless invoice.receiving_org.present?

    unless org_that_credit_balance_adjustment_is_applied_to&.sponsors_invoiced?
      create_sponsors_zuora_account
    end

    result = increase_credit_balance

    instrument_payment_succeeded
    send_credit_balance_increase_email

    result
  end

  private

  sig { returns(Billing::Stripe::Invoice) }
  attr_reader :invoice

  sig { void }
  def send_credit_balance_increase_email
    SponsorsCreditBalanceIncreaseNotificationJob.perform_later(sponsor: org_that_credit_balance_adjustment_is_applied_to)
  end

  sig { returns(Organization) }
  def create_sponsors_zuora_account
    result = Billing::CreateCustomer.perform(T.must(org_that_credit_balance_adjustment_is_applied_to),
      actor: User.staff_user,
      details: { omit_billing_info: true },
      purpose: :sponsors,
    )

    unless result.success?
      raise ZuoraAccountCreationError.new("Failed to create Zuora account for " \
        "#{org_that_credit_balance_adjustment_is_applied_to}: #{result.error_message}")
    end

    # Load new `sponsors_customer` relation and clear memoized #sponsors_invoiced? check:
    org_that_credit_balance_adjustment_is_applied_to&.reload
  end

  sig { returns(GitHub::Billing::Result) }
  def increase_credit_balance
    result = Billing::Sponsors::Invoiced::IncreaseCreditBalance.perform(
      actor: User.staff_user,
      sponsor: org_that_credit_balance_adjustment_is_applied_to,
      amount: credit_balance_adjustment_amount,
      comment: "automated payment from Stripe invoice",
      reference_id: invoice.id,
      via_automation: true,
    )

    unless result.success?
      raise "Failed to add credit balance to Zuora account for" \
        "#{org_that_credit_balance_adjustment_is_applied_to}: #{result.error_message}"
    end

    result
  end

  sig { returns(T.nilable(Organization)) }
  memoize def org_that_credit_balance_adjustment_is_applied_to
    invoice.receiving_org
  end

  sig { returns(Billing::Money) }
  memoize def credit_balance_adjustment_amount
    # We purposefully have a rule in Stripe that allows invoices to be considered "Paid"
    # if the amount paid is within $100 of the invoice amount. In these cases, we apply the
    # full invoice amount (`amount_due`), eat the difference as part of our service fee.
    invoice.amount_due - invoice.service_fee
  end

  sig { void }
  def instrument_payment_succeeded
    GitHub.dogstats.increment(DATADOG_PREFIX)
    GitHub.dogstats.count("#{DATADOG_PREFIX}.invoice_amount_in_cents", invoice.amount_paid.cents)
    GitHub.dogstats.count("#{DATADOG_PREFIX}.invoice_fees_amount_in_cents", invoice.service_fee.cents)
    GitHub.dogstats.count("#{DATADOG_PREFIX}.credit_balance_adjustment_amount_in_cents",
      credit_balance_adjustment_amount.cents)
    invoice.instrument(action: "PAY")
  end
end
