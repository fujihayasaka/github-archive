# typed: true
# frozen_string_literal: true

class SponsorsBillingCreditBalanceInvoiceCollectionJob < ApplicationJob
  extend T::Sig
  include GitHub::Billing::ZuoraRateLimitHandler
  include GitHub::Memoizer

  queue_as :billing

  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

  class InvoiceAccountMismatchError < StandardError; end
  class InsufficientCreditBalanceError < StandardError; end
  INSUFFICIENT_FUNDS_REGEXP = Regexp.union("apply more than the Credit Balance", "no credit balance to apply")
  # Adapter to account for different Zuora endpoints using different naming conventions
  Invoice = Struct.new(:id, :balance, :status, :zuora)

  sig { returns GitHubSponsors::Types::Sponsor }
  attr_reader :user

  sig { returns T.nilable(String) }
  attr_reader :invoice_id

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, SponsorsBillingCreditBalanceInvoiceCollectionJob)
    zuora_rate_limit_handler(self, error)
  end

  retry_on ::Billing::Zuora::InternalError, ::Billing::Zuora::LockCompetitionError, Zuorest::GatewayTimeoutError,
    wait: :polynomially_longer,
    attempts: ::Billing::PlanSubscription::SynchronizationEvents::EXTRA_RETRYABLE_ATTEMPTS

  # Public: Pay invoice(s) via credit balance adjustment for Premium Sponsors
  #
  # user - Organization whose invoices will be paid via credit balance adjustment
  # invoice_id - (Optional) used to pay a single invoice, defaults to paying all recent invoices
  sig { params(user: T.nilable(GitHubSponsors::Types::Sponsor), invoice_id: T.nilable(String)).void }
  def perform(user, invoice_id: nil)
    @user = user
    @invoice_id = invoice_id

    return unless user&.sponsors_invoiced? && user.sponsors_plan_subscription.present?

    invoices_to_pay.each do |invoice|
      begin
        pay_invoice(invoice)
      rescue InsufficientCreditBalanceError
        rollback_subscription_items(invoice)
        Billing::Zuora::ZeroOutInvoice.run(invoice: invoice.zuora)
      end
    end
  end

  private

  sig { returns T.nilable(String) }
  def zuora_account_id
    user.invoiced_sponsor_zuora_account_id
  end

  sig { returns Invoice }
  def single_invoice
    invoice = GitHub.zuorest_client.get_object_invoice(invoice_id)
    if invoice["AccountId"] != zuora_account_id
      raise InvoiceAccountMismatchError.new("account #{zuora_account_id} has no invoice with id #{invoice["Id"]}")
    end

    invoice_id = invoice["Id"]
    Invoice.new(invoice_id, invoice["Balance"], invoice["Status"], Billing::Zuora::Invoice.new(invoice_id))
  end

  sig { returns T::Array[Invoice] }
  def recent_invoices
    # TODO use get_account_summary once https://github.com/github/zuorest/pull/43 lands
    zuorest_client = GitHub.zuorest_client
    account_summary = zuorest_client.get("/v1/accounts/#{zuora_account_id}/summary")
    account_summary["invoices"].map do |invoice|
      invoice_id = invoice["id"]
      Invoice.new(invoice_id, invoice["balance"], invoice["status"], Billing::Zuora::Invoice.new(invoice_id))
    end
  end

  sig { returns T::Array[Invoice] }
  def invoices
    if invoice_id.present?
      [single_invoice]
    else
      recent_invoices
    end
  end

  sig { returns T::Array[Invoice] }
  def invoices_to_pay
    invoices.select do |invoice|
      invoice.balance.positive? && invoice.status == "Posted"
    end
  end

  sig { params(invoice: Invoice).void }
  def pay_invoice(invoice)
    begin
      GitHub.zuorest_client.create_credit_balance_adjustment(
        {
          "Amount" => invoice.balance,
          "SourceTransactionId" => invoice.id,
          "Type" => "Decrease",
        }
      )
      emit_metrics(amount_in_cents: invoice_balance_in_cents(invoice))
    rescue Zuorest::HttpError => error
      raise_or_report_zuora_error(error)
    end
  end

  sig { params(error: StandardError).void }
  def raise_or_report_zuora_error(error)
    case error.message
    when INSUFFICIENT_FUNDS_REGEXP
      raise InsufficientCreditBalanceError
    else
      raise
    end
  end

  sig { returns Billing::PlanSubscription }
  memoize def plan_subscription
    T.must_because(user.sponsors_plan_subscription) { "#perform returns early when no Sponsors plan subscription" }
  end

  sig { params(invoice: Invoice).void }
  def rollback_subscription_items(invoice)
    invoice.zuora.invoice_items.each do |invoice_item|
      next unless invoice_item.subscribable?
      sub_item = Billing::SubscriptionItem.find_by(
        plan_subscription: plan_subscription,
        subscribable: invoice_item.subscribable
      )
      with_write { sub_item&.cancel!(force: true, skip_sync: true) }
    end
    plan_subscription.synchronize_later
  end

  sig { params(invoice: Invoice).returns(Integer) }
  def invoice_balance_in_cents(invoice)
    (invoice.balance * 100).to_i
  end

  sig { params(amount_in_cents: Integer).void }
  def emit_metrics(amount_in_cents:)
    GitHub.dogstats.increment("sponsors.payment_run.invoice_paid")
    GitHub.dogstats.count("sponsors.payment_run.amount_in_cents", amount_in_cents)
  end
end
