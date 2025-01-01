# typed: strict
# frozen_string_literal: true

class Billing::PlanSubscription::SendReceipt
  sig { params(plan_subscription: Billing::PlanSubscription, billing_transaction: Billing::BillingTransaction).void }
  def self.perform(plan_subscription, billing_transaction:); new(plan_subscription, billing_transaction: billing_transaction).perform; end

  sig { params(plan_subscription: Billing::PlanSubscription, billing_transaction: Billing::BillingTransaction).void }
  def initialize(plan_subscription, billing_transaction:)
    @plan_subscription   = plan_subscription
    @billing_transaction = billing_transaction
  end

  sig { void }
  def perform
    BillingNotificationsMailer.receipt(
      plan_subscription.billable_entity,
      billing_transaction,
    ).deliver_later

    BillingNotificationsMailer.receipt_bcc(
      plan_subscription.billable_entity,
      billing_transaction,
    ).deliver_later if BillingNotificationsMailer.send_receipt_bcc?
  end

  private

  sig { returns(Billing::PlanSubscription) }
  attr_reader :plan_subscription
  sig { returns(Billing::BillingTransaction) }
  attr_reader :billing_transaction
end
