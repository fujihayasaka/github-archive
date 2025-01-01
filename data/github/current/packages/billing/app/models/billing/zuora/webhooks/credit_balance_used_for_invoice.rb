# typed: true
# frozen_string_literal: true

class Billing::Zuora::Webhooks::CreditBalanceUsedForInvoice < ::Billing::Zuora::Webhooks::WebhookHandler
  include GitHub::Memoizer
  before_perform :ignore!, if: -> {
    T.bind(self, Billing::Zuora::Webhooks::CreditBalanceUsedForInvoice)

    !invoice_fully_paid_by_credit_balance? ||
    account_deleted_or_suspended? ||
    already_processed_transaction?
  }
  before_perform :ensure_zuora_subscription_exists

  after_perform :instrument_credit_balance_adjustment

  def perform
    Billing::Zuora::Webhooks::ProcessPaidInvoice.perform(
      plan_subscription: plan_subscription,
      zuora_account: zuora_object_account,
      zuora_subscription: zuora_subscription,
      zuora_transaction: zuora_credit_balance_adjustment,
      email_receipt_and_invoice: false
    )
  end

  private

  # An account may have multiple Zuora subscriptions (e.g. general and sponsors purpose) and therefore there is
  # a possibility that the current plan_subscription method defined in Billing::ZuoraWebhook will return the plan subscription
  # that doesn't match the plan subscription targeted by the webhook.
  # To ensure that the correct subscription is used, the subscription number is extracted from the invoice from the payload
  sig { returns(T.nilable(Billing::PlanSubscription)) }
  memoize def plan_subscription
    return super unless account_has_multiple_zuora_subscriptions?
    return super unless invoice_id = payload["InvoiceId"]
    invoice = Billing::Zuora::Invoice.new(invoice_id)

    subscription_number = invoice.subscription_number_from_billable_line_items
    return super unless subscription_number
    plan_subscription = Billing::PlanSubscription.find_by(zuora_subscription_number: subscription_number)
    plan_subscription
  end

  sig { returns(T::Boolean) }
  memoize def account_has_multiple_zuora_subscriptions?
    T.must(account).plan_subscriptions.where.not(zuora_subscription_id: nil).size > 1
  end

  sig { returns(T::Boolean) }
  def invoice_fully_paid_by_credit_balance?
    (credit_balance_adjustment_amount + invoice_amount).zero?
  end

  sig { returns(T::Boolean) }
  def already_processed_transaction?
    T.must(account).billing_transactions.where(transaction_id: zuora_credit_balance_adjustment.reference_id).exists?
  end

  sig { returns(String) }
  def credit_balance_adjustment_id
    payload["CreditBalanceAdjustmentId"]
  end

  sig { returns(BigDecimal) }
  def credit_balance_adjustment_amount
    @credit_balance_adjustment_amount ||= T.let(payload["InvoiceCreditBalanceAdjustmentAmount"].to_d, T.nilable(BigDecimal))
  end

  sig { returns(BigDecimal) }
  def invoice_amount
    @invoice_amount ||= T.let(payload["InvoiceAmount"].to_d, T.nilable(BigDecimal))
  end

  sig { returns(::Billing::Zuora::CreditBalanceAdjustment) }
  def zuora_credit_balance_adjustment
    @zuora_credit_balance_adjustment ||= T.let(Billing::Zuora::CreditBalanceAdjustment.find(credit_balance_adjustment_id), T.nilable(::Billing::Zuora::CreditBalanceAdjustment))
  end

  sig { void }
  def instrument_credit_balance_adjustment
    GitHub.dogstats.increment("zuora.credit_balance_adjustment.count", tags: ["class:credit_balance_used_for_invoice"])
    GitHub.dogstats.count(
      "zuora.credit_balance_adjustment.amount_in_cents",
      zuora_credit_balance_adjustment.amount_in_cents,
      tags: ["class:credit_balance_used_for_invoice"]
    )

    GitHub.logger.info(
      "Credit balance used for invoice",
      "code.namespace" => self.class.name,
      "gh.billing.zuora.account.id" => account_id,
      "gh.billing.zuora.invoice.id" => invoice_id,
      "gh.billing.zuora.credit_balance_adjustment.id" => credit_balance_adjustment_id,
      "gh.billing.zuora.credit_balance_adjustment.amount" => credit_balance_adjustment_amount.to_s,
      "gh.billing.zuora.invoice.amount" => invoice_amount.to_s
    )
  end
end
