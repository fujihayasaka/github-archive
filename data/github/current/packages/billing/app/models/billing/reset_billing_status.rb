# typed: true
# frozen_string_literal: true

class Billing::ResetBillingStatus
  DEFAULT_BALANCE_IN_CENTS = 0

  sig { params(customer: Customer, next_billing_date: T.any(String, Date), balance_in_cents: Integer).void }
  def self.perform(customer, next_billing_date:, balance_in_cents: DEFAULT_BALANCE_IN_CENTS)
    new(customer, next_billing_date:, balance_in_cents: balance_in_cents).perform
  end

  sig { params(customer: Customer, next_billing_date: T.any(String, Date), balance_in_cents: Integer).void }
  def initialize(customer, next_billing_date:, balance_in_cents: DEFAULT_BALANCE_IN_CENTS)
    @customer               = customer
    @plan_subscriptions     = customer.plan_subscriptions
    @balance_in_cents       = balance_in_cents
    @next_billing_date      = next_billing_date.to_s.to_date
    @billable_entity        = customer.billable_owner
  end

  def perform
    return record_missing_billable_entity unless billable_entity

    update_balance
    reset_status
  end

  private

  attr_reader :customer,
              :balance_in_cents,
              :next_billing_date,
              :plan_subscriptions,
              :billable_entity

  sig { void }
  def record_missing_billable_entity
    GitHub.logger.warn("Missing billable entity for customer",
      "customer.id" => customer.id,
      "code.namespace" => self.class.name.to_s,
      "code.function" => __method__.to_s,
    )
    GitHub.dogstats.increment("billing.reset_billing_status.missing_billable_entity")
    nil
  end

  sig { void }
  def update_balance
    # TODO balances exist at the Zuora account level, so all plan subscriptions should be updated
    # to reflect the same balance until we migrate away from this data being on plan subscriptions
    # to store them on customers (our domain model for Zuora accounts).
    plan_subscriptions.each { |plan_sub| plan_sub.update(balance_in_cents: balance_in_cents) }
    nil
  end

  sig { void }
  def reset_status
    # Sponsors-purpose customers pay via credit balance and are not subject to dunning. They manage
    # their own billing dates instead of leveraging the billable entity level billing date to support
    # billing at a different cadence than the general-purpose customer.
    return unless customer.general_purpose?

    update_next_billing_date
    billable_entity.manual_dunning_period&.destroy if balance_in_cents.zero?
    billable_entity.enable_or_disable! if can_enable_or_disable_billable_entity?(billable_entity)
    billable_entity.rebuild_asset_status unless billable_entity.is_a?(::Business)
    nil
  end

  sig { void }
  def update_next_billing_date
    existing_billing_date = billable_entity.next_billing_date

    # It's possible for this to be called based on payments for different subscriptions, so we
    # want to ensure we're always using the earliest next billing date.
    future_next_billing_date = [existing_billing_date, next_billing_date]
      .compact
      .filter { |date| GitHub::Billing.future?(date) }
      .min
    billing_date = future_next_billing_date || existing_billing_date

    # We're using `update_column` here to avoid spikes in user search indexing.
    #
    # https://github.com/github/availability/issues/658
    billable_entity.update_billing_date(next_billing_date: billing_date, billing_attempts: 0)
    nil
  end

  sig { params(billable_entity: T.any(User, Business)).returns(T::Boolean) }
  def can_enable_or_disable_billable_entity?(billable_entity)
    return true unless billable_entity.is_a?(::Business)
    return false if billable_entity.trial_expired?
    return false if billable_entity.trial_cancelled?
    true
  end
end
