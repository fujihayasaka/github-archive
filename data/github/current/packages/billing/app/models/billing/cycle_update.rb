# typed: strict
# frozen_string_literal: true

# CycleUpdate is responsible for dealing with switching billing cycle
# eg, from yearly -> monthly or monthly -> yearly
class Billing::CycleUpdate

  sig { returns(::User) }
  attr_reader :actor

  sig { returns(T.nilable(Date)) }
  attr_reader :last_billed_on

  sig { returns(Integer) }
  attr_reader :months_left

  sig { returns(String) }
  attr_reader :old_duration

  sig { returns(String) }
  attr_reader :new_duration

  sig { returns(::User) }
  attr_reader :target

  sig { params(target: ::User, new_duration: String, options: T::Hash[Symbol, T.untyped]).returns(GitHub::Billing::Result) }
  def self.perform(target, new_duration, options = {})
    new(target, new_duration, options).perform
  end

  # Public: Initializes a new instance of CycleUpdate
  #
  # Examples
  #
  #   CycleUpdate.new(user, "year")
  #   CycleUpdate.new(user, "month")
  #   CycleUpdate.new(organization, "year")
  #   CycleUpdate.new(organization, "month"
  # target - User or Org whose cycle should change
  # new_duration - "year" or "month"
  # options      - :actor (optional, defaults to target)
  #                the user making this change (used for tracking)
  sig { params(target: ::User, new_duration: String, options: T::Hash[Symbol, T.untyped]).void }
  def initialize(target, new_duration, options = {})
    @actor        = T.let(options[:actor] || target, ::User)
    @target       = target
    @old_duration = T.let(target.plan_duration, String)
    @new_duration = T.let(valid_plan_duration(new_duration), String)
    months_left, last_billed_on = calculate_months_left_and_last_billed_on
    @months_left = T.let(months_left, Integer)
    @last_billed_on   = T.let(last_billed_on, T.nilable(Date))
  end

  # Public: Updates the account billing cycle and relevant billing attributes
  sig { returns(GitHub::Billing::Result) }
  def perform
    return GitHub::Billing::Result.success if target.invoiced? || same_duration?

    if target.external_subscription?
      schedule_change
    else
      target.plan_duration = new_duration
      set_billed_on if was_yearly?
    end

    target.save!

    track_change if should_track_change?
    GitHub::Billing::Result.success
  end

  # Public: The amount (in cents) we owe the user if they switch yearly -> monthly
  sig { returns(Integer) }
  def refund_in_cents
    return 0 if was_monthly? || months_left.zero?

    -1 * months_left * plan_price.cents
  end

  # Public: The date the user will next be billed
  sig { returns(Date) }
  def next_billed_on
    if was_yearly?
      target.new_billed_on(last_billed_on, "month")
    else
      target.next_billing_date
    end
  end

  sig { returns(Billing::Money) }
  def plan_price
    Billing::Pricing.new(
      account: target,
      plan: target.plan,
      seats: target.seats,
      plan_duration: new_duration,
      coupon: target.coupon,
    ).discounted
  end

  private

  # Internal: checks if the new duration for billing the user is
  # the same as the old one
  sig { returns(T::Boolean) }
  def same_duration?
    target.plan_duration == new_duration
  end

  # Internal: offloads processing of subscription changes
  sig { returns(GitHub::Billing::Result) }
  def schedule_change
    ::Billing::ChangeSubscription.perform \
      target,
      plan: target.plan,
      actor: actor,
      plan_duration: new_duration,
      seat_delta: nil
  end

  sig { returns([Integer, T.nilable(Date)]) }
  def calculate_months_left_and_last_billed_on
    today          = GitHub::Billing.today
    til            = target.billed_on || today
    months_left    = 0
    last_billed_on = T.let(nil, T.nilable(Date))

    return [0, nil] unless was_yearly?
    return [0, til] unless til > today

    while !last_billed_on do
      potential = til << months_left + 1
      last_billed_on = potential if potential <= today
      months_left += 1 unless last_billed_on
    end

    [months_left, last_billed_on]
  end

  sig { returns(GitHub::Billing::Result) }
  def refund_failure
    GitHub::Billing::Result.failure "We were unable to process a refund at this time."
  end

  sig { void }
  def set_billed_on
    target.billing_attempts = 0
    target.billed_on = target.new_billed_on(last_billed_on)
  end

  sig { returns(T::Boolean) }
  def should_track_change?
    !!(target.has_billing_record? && !target.plan.free?)
  end

  sig { void }
  def track_change
    target.track_plan_duration_change(actor, old_duration)
  end

  sig { params(plan_duration: String).returns(String) }
  def valid_plan_duration(plan_duration)
    plan_duration == User::BillingDependency::YEARLY_PLAN ? User::BillingDependency::YEARLY_PLAN : User::BillingDependency::MONTHLY_PLAN
  end

  sig { returns(T::Boolean) }
  def was_yearly?
    old_duration == User::BillingDependency::YEARLY_PLAN
  end

  sig { returns(T::Boolean) }
  def was_monthly?
    old_duration == User::BillingDependency::MONTHLY_PLAN
  end
end
