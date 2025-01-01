# typed: strict
# frozen_string_literal: true

class Billing::PlanSubscription::SendFailureNotification

  sig do
    params(
      plan_subscription: Billing::PlanSubscription,
      message: String,
      marketplace: T::Boolean
    ).void
  end
  def self.perform(plan_subscription, message:, marketplace: false)
    new(plan_subscription, marketplace: marketplace, message: message).perform
  end

  sig do
    params(
      plan_subscription: Billing::PlanSubscription,
      message: String,
      marketplace: T::Boolean
    ).void
  end
  def initialize(plan_subscription, message:, marketplace: false)
    @message = message
    @marketplace = marketplace
    @billable_entity = T.let(T.must(plan_subscription.billable_entity), Billing::Types::Account)
  end

  sig { void }
  def perform
    if billable_entity.has_paypal_account?
      BillingNotificationsMailer.paypal_failure(billable_entity, message).deliver_later
    elsif billable_entity.card_expired?
      BillingNotificationsMailer.cc_expired_failure(billable_entity).deliver_later
    elsif marketplace
      BillingNotificationsMailer.marketplace_failure(billable_entity, message).deliver_later
    else
      BillingNotificationsMailer.cc_failure(billable_entity, message).deliver_later
    end
  end

  private

  sig { returns(Billing::Types::Account) }
  attr_reader :billable_entity

  sig { returns(String) }
  attr_reader :message

  sig { returns(T::Boolean) }
  attr_reader :marketplace
end
