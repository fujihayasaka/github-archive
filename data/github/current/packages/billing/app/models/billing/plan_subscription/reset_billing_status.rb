# typed: strict
# frozen_string_literal: true

class Billing::PlanSubscription::ResetBillingStatus

  sig do
    params(
      plan_subscription: Billing::PlanSubscription,
      next_billing_date: T.any(Date, String),
      balance: Integer
    ).void
  end
  def self.perform(plan_subscription, next_billing_date:, balance: 0)
    new(plan_subscription, balance: balance, next_billing_date: next_billing_date).perform
  end

  sig do
    params(
      plan_subscription: Billing::PlanSubscription,
      next_billing_date: T.any(Date, String),
      balance: Integer
    ).void
  end
  def initialize(plan_subscription, next_billing_date:, balance: 0)
    @plan_subscription      = plan_subscription
    @balance                = balance
    @next_billing_date      = T.let(next_billing_date.to_s.to_date, Date)
    @billable_entity        = T.let(T.must(plan_subscription.billable_entity), ::Billing::Types::Account)
  end

  sig { void }
  def perform
    plan_subscription.update(balance_in_cents: balance)
    billable_entity = self.billable_entity
    billable_entity.manual_dunning_period&.destroy if balance.zero?
    # Currently, the billed_on date is set at the User/Org level, we
    # need to avoid changing it unless the we're resetting the status of
    # the general-purpose customer.
    if plan_subscription.general_purpose_customer?
      # We're using `update_column` here to avoid spikes in user search indexing.
      #
      # https://github.com/github/availability/issues/658
      billable_entity.update_billing_date(next_billing_date: next_billing_date, billing_attempts: 0)

      billable_entity.enable_or_disable! if can_enable_or_disable_billable_entity?(billable_entity)
      billable_entity.rebuild_asset_status unless billable_entity.is_a?(::Business)
    end
  end

  private

  sig { returns(Integer) }
  attr_reader :balance

  sig { returns(Date) }
  attr_reader :next_billing_date

  sig { returns(::Billing::PlanSubscription) }
  attr_reader :plan_subscription

  sig { returns(::Billing::Types::Account) }
  attr_reader :billable_entity

  sig { params(billable_entity: ::Billing::Types::Account).returns(T::Boolean) }
  def can_enable_or_disable_billable_entity?(billable_entity)
    return true unless billable_entity.is_a?(::Business)
    return false if billable_entity.trial_expired?
    return false if billable_entity.trial_cancelled?
    true
  end
end
