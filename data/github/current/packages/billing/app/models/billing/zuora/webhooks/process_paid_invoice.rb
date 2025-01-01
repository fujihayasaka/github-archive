# typed: true
# frozen_string_literal: true

class Billing::Zuora::Webhooks::ProcessPaidInvoice
  include GitHub::Memoizer
  include ::ApplicationMailer::Helpers

  DATADOG_PREFIX = "zuora.process_paid_invoice"

  attr_reader :plan_subscription, :zuora_account, :zuora_subscription, :zuora_transaction, :billing_transaction,
    :account, :payment_method

  # args - a Hash with the following keys:
  #   :plan_subscription - a Billing::PlanSubscription
  #   :zuora_account
  #   :zuora_subscription
  #   :zuora_transaction - a Billing::Zuora::Payment
  #   :email_receipt_and_invoice - a Boolean
  def self.perform(args)
    new(**args).perform
  end

  def initialize(plan_subscription:, zuora_account:, zuora_subscription:, zuora_transaction:, email_receipt_and_invoice: true)
    @plan_subscription = plan_subscription
    @account = plan_subscription.billable_entity
    @zuora_account = zuora_account
    @zuora_subscription = zuora_subscription
    @zuora_transaction = zuora_transaction
    @email_receipt_and_invoice = email_receipt_and_invoice
  end

  def perform
    reset_billing_status
    create_billing_transaction
    if @email_receipt_and_invoice
      send_receipt
      send_invoice
    end
    transfer_sponsors_payment
    handle_paypal_sponsors_items
  end

  private

  def reset_billing_status
    # A successful payment is an accepted alternative to a successful authorization.
    # Remove the disabled reason (if present) to ensure we don't keep the customer locked for this reason.
    plan_subscription.customer.remove_disabled_by_authorization_failure_reason

    account = T.must(self.account)

    account.plan_subscriptions.each { |plan_sub| plan_sub.update_balance_from_zuora(origin: self.class.name, zuora_account: zuora_account) }

    ::Billing::ResetBillingStatus.perform(
      plan_subscription.customer,
      balance_in_cents: zuora_account.balance.cents,
      next_billing_date: zuora_subscription.charged_through_date.to_s,
    )
  end

  def create_billing_transaction
    @billing_transaction = ::Billing::PlanSubscription::CreateBillingTransaction.perform \
      plan_subscription,
      service_ends_at: zuora_subscription.charged_through_date,
      zuora_transaction: zuora_transaction
  end

  def send_receipt
    ::Billing::PlanSubscription::SendReceipt.perform \
      plan_subscription,
      billing_transaction: billing_transaction
  end

  def send_invoice
    return if !account.self_serve_invoice_enabled? && !account.requires_invoice_by_email?

    invoice_ids = zuora_transaction.invoices.map { |invoice| invoice.invoice_id }
    emails = billing_emails(account, include_name: false).join(",")
    invoice_ids.each do |invoice_id|
      next if invoice_id.nil?
      EmailInvoiceJob.perform_later(invoice_id: invoice_id, emails: emails)
    end
  end

  # Internal: Create a Transfer to a Stripe Connect account to pay
  # maintainers for their sponsorships
  def transfer_sponsors_payment
    return unless can_transfer_sponsors_payment?

    ::Billing::Stripe::TransferPayments.perform \
      sponsorship_line_items,
      zuora_transaction
  end

  # Internal: Are their sponsorships that are able to be transferred to
  # Stripe connect?
  #
  # Returns Boolean
  def can_transfer_sponsors_payment?
    return false if sponsorship_invoice_items_with_invalid_payment_method?

    # Can only figure out what to transfer if Billing::BillingTransaction::LineItem records were created
    # where the maintainer's Stripe Connect account details are known:
    sponsorship_line_items.any?(&:stripe_transfers_enabled?)
  end

  memoize def sponsorship_invoice_items_with_invalid_payment_method?
    # PayPal is deprecated as a payment method for GitHub Sponsors sponsorships;
    # see https://github.com/github/sponsors/issues/4555.
    billing_transaction.paypal? && positive_sponsorship_invoice_items.any?
  end

  memoize def positive_sponsorship_invoice_items
    items = zuora_transaction.invoice_items.select do |item|
      item.subscribable? && item.sponsors_item? && item.charge_amount.positive?
    end
    GitHub::PrefillAssociations.prefill_associations(items.map(&:subscribable), :sponsorable)
    items
  end

  memoize def sponsorship_line_items
    billing_transaction.line_items.sponsorships.to_a
  end

  def handle_paypal_sponsors_items
    return unless sponsorship_invoice_items_with_invalid_payment_method?

    instrument_paid_sponsorship_invoice_with_invalid_payment_method
    log_paid_sponsorship_invoice_with_invalid_payment_method
    Sponsors::CancelSponsorshipsFromPaypalSponsors.call(account)
    refund_result = refund_sponsorship_items_paid_with_invalid_payment_method
    add_staff_note_about_refund_for_invalid_sponsorship_payment(refund_result)
  end

  def instrument_paid_sponsorship_invoice_with_invalid_payment_method
    datadog_tags = ["sponsor_type:#{billing_transaction.user_type.capitalize}",
      "payment_type:#{billing_transaction.payment_type}"]
    GitHub.dogstats.increment("#{DATADOG_PREFIX}.invalid_sponsorship_payment_method", tags: datadog_tags)

    total_sponsors_cents = positive_sponsorship_invoice_items.map { |item| item.charge_amount.cents }.sum
    GitHub.dogstats.count("#{DATADOG_PREFIX}.invalid_sponsorship_payment_method.amount_in_cents",
      total_sponsors_cents, tags: datadog_tags)
  end

  memoize def zuora_transaction_id
    zuora_transaction.reference_id || zuora_transaction.payment_number
  end

  def log_paid_sponsorship_invoice_with_invalid_payment_method
    user_type_key = billing_transaction.user_type.downcase
    user_type_key = "org" if user_type_key == "organization"
    positive_sponsorship_invoice_items.each do |item|
      sponsorable = item.subscribable.sponsorable
      GitHub.logger.warn(
        "Processing paid invoice where a disallowed payment type was used for a sponsorship item",
        "catalog_service" => "github/github_sponsors",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.#{user_type_key}.id" => billing_transaction.user_id,
        "gh.#{user_type_key}" => billing_transaction.user_login,
        "sponsor_id" => billing_transaction.user_id,
        "sponsor_type" => billing_transaction.user_type,
        "payment_type" => billing_transaction.payment_type,
        "item_id" => item.id,
        "item_amount_in_cents" => item.charge_amount.cents,
        "tier_amount_in_cents" => item.subscribable.monthly_price_in_cents,
        "sponsorable_id" => sponsorable&.id,
        "sponsorable_type" => sponsorable&.type,
        "zuora_transaction_id" => zuora_transaction_id,
        "zuora_payment_creation_date" => zuora_transaction.created_date,
      )
    end
  end

  memoize def sponsorables_included_in_sponsorship_items_paid_with_invalid_payment_method
    positive_sponsorship_invoice_items.map { |item| item.subscribable.sponsorable }.compact.uniq
  end

  def refund_sponsorship_items_paid_with_invalid_payment_method
    amount_in_cents = positive_sponsorship_invoice_items.sum { |item| item.charge_amount.cents }
    money = ::Billing::Money.new(amount_in_cents)
    prefix = "We're refunding #{money.format} paid (reference: #{zuora_transaction_id}) for"
    suffix = "because GitHub Sponsors no longer accepts PayPal. The original charge was accidental. " \
      "We apologize for any inconvenience."
    whose_money = account&.user? ? "your" : "@#{billing_transaction.user_login}'s"
    sponsorables = sponsorables_included_in_sponsorship_items_paid_with_invalid_payment_method
    sponsorship_units = "sponsorship".pluralize(sponsorables.size)
    sponsorables_list = sponsorables.map { |sponsorable| "@#{sponsorable}" }.to_sentence
    sponsorables_summary = sponsorables.present? ? " of #{sponsorables_list}" : ""
    custom_text = "#{prefix} #{whose_money} #{sponsorship_units}#{sponsorables_summary} #{suffix}"

    result = GitHub::Billing.refund_transaction(zuora_transaction_id, amount_in_cents, skip_email: false,
      email_refund_custom_text: custom_text)

    if result.success?
      datadog_tags = ["sponsor_type:#{billing_transaction.user_type.capitalize}",
        "payment_type:#{billing_transaction.payment_type}"]
      GitHub.dogstats.increment("#{DATADOG_PREFIX}.invalid_sponsorship_payment_method_refund", tags: datadog_tags)
      GitHub.dogstats.count("#{DATADOG_PREFIX}.invalid_sponsorship_payment_method_refund.amount_in_cents",
        amount_in_cents, tags: datadog_tags)
    else
      user_type_key = billing_transaction.user_type.downcase
      user_type_key = "org" if user_type_key == "organization"
      GitHub.logger.warn(
        "Failed to refund sponsorship item where an invalid payment method was originally used",
        "catalog_service" => "github/github_sponsors",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.#{user_type_key}.id" => billing_transaction.user_id,
        "gh.#{user_type_key}" => billing_transaction.user_login,
        "sponsor_id" => billing_transaction.user_id,
        "sponsor_type" => billing_transaction.user_type,
        "payment_type" => billing_transaction.payment_type,
        "item_ids" => positive_sponsorship_invoice_items.map { |item| item.id.to_s }.join(","),
        "amount_in_cents" => amount_in_cents,
        "sponsorable_ids" => sponsorables.map { |sponsorable| sponsorable.id.to_s }.join(","),
        "zuora_transaction_id" => zuora_transaction_id,
        "zuora_payment_creation_date" => zuora_transaction.created_date,
        "exception.message" => result.error_message,
      )
    end

    result
  end

  def add_staff_note_about_refund_for_invalid_sponsorship_payment(refund_result)
    return unless account

    author = User.find_by(login: "cheshire137")
    author = User.staff_user unless author&.employee?
    amount_in_cents = positive_sponsorship_invoice_items.sum { |item| item.charge_amount.cents }
    money = ::Billing::Money.new(amount_in_cents)
    issue_url = "https://github.com/github/sponsors/issues/4727"
    sponsorables = sponsorables_included_in_sponsorship_items_paid_with_invalid_payment_method
    sponsorship_units = "sponsorship".pluralize(sponsorables.size)
    sponsorables_list = sponsorables.map { |sponsorable| "@#{sponsorable}" }.to_sentence
    sponsorables_summary = sponsorables.present? ? " of #{sponsorables_list}" : ""
    sponsorship_article = sponsorables.size == 1 ? "a " : ""
    refund_error = refund_result&.error_message.present? ? " (error: #{refund_result.error_message})" : ""

    message = if refund_result&.success?
      "#{money.format} was refunded to the #{account.type.downcase} for transaction #{zuora_transaction_id} " \
        "because they were wrongly charged for #{sponsorship_article}#{sponsorship_units}" \
        "#{sponsorables_summary} via PayPal after PayPal was deprecated for GitHub Sponsors. See #{issue_url}."
    else
      "A refund of #{money.format} was attempted for transaction #{zuora_transaction_id}, but was unsuccessful" \
        "#{refund_error}. We wanted to refund their sponsorship money for #{sponsorship_article}" \
        "#{sponsorship_units}#{sponsorables_summary} because they were wrongly charged via PayPal after PayPal " \
        "was deprecated for GitHub Sponsors. See #{issue_url}."
    end

    account.staff_notes.create(user: author, note: message)
  end
end
