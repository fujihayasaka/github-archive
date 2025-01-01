# typed: strict
# frozen_string_literal: true

class Billing::PlanSubscription::SendFailureNotification

  sig do
    params(
      plan_subscription: Billing::PlanSubscription,
      message: String,
      details: T.nilable(String)
    ).void
  end
  def self.perform(plan_subscription, message:, details: nil)
    new(plan_subscription, message:, details:).perform
  end

  sig do
    params(
      plan_subscription: Billing::PlanSubscription,
      message: String,
      details: T.nilable(String)
    ).void
  end
  def initialize(plan_subscription, message:, details: nil)
    @message = message
    @details = details
    @billable_entity = T.let(T.must(plan_subscription.billable_entity), Billing::Types::Account)
  end

  sig { void }
  def perform
    if billable_entity.has_paypal_account?
      BillingNotificationsMailer.paypal_failure(billable_entity, message, details).deliver_later
    elsif billable_entity.card_expired?
      BillingNotificationsMailer.cc_expired_failure(billable_entity, details).deliver_later
    else
      BillingNotificationsMailer.cc_failure(billable_entity, message, details).deliver_later
    end
  end

  private

  sig { returns(Billing::Types::Account) }
  attr_reader :billable_entity

  sig { returns(String) }
  attr_reader :message

  sig { returns(T.nilable(String)) }
  attr_reader :details
end
