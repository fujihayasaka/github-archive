# typed: strict
# frozen_string_literal: true

module PlanHelper
  extend T::Helpers

  requires_ancestor { MoneyHelper }
  requires_ancestor { ActionView::Helpers::NumberHelper }

  abstract!

  sig { abstract.returns(T.nilable(User)) }
  def current_user; end

  sig { params(plan: GitHub::Plan, target: T.nilable(Billing::Types::Account)).returns(String) }
  def human_plan_cost(plan, target = nil)
    target ||= T.must(current_user)

    list_price = Billing::Pricing.new(
      account: target,
      plan: plan,
      seats: target.default_seats,
      plan_duration: target.plan_duration,
      coupon: target.coupon,
    ).discounted

    money(list_price)
  end

  sig { params(account: Billing::Types::Account, plan: GitHub::Plan).returns(String) }
  def full_plan_pricing(account, plan)
    "#{human_plan_cost(plan, account)}/#{account.plan_duration}"
  end

  # Returns a currency string with two decimal place precision if
  # fractional currency exists, otherwise no decimal places.
  #
  # price - Integer or Float to be converted to currency String
  # discount (optional) - percentage to take off of original price (scale of 0
  # to 100)
  #
  sig { params(price: T.nilable(Billing::Types::Numeric), discount: T.any(Integer, Float)).returns(String) }
  def casual_currency(price, discount: 0)
    price = T.let(Billing::Money.zero, Billing::Money) unless price.respond_to? :round
    price = T.must(price) * (100 - discount) / 100.0

    number_to_currency price, precision: (price.round.to_money == price.to_money) ? 0 : 2
  end

  sig { params(target: User, new_plan: GitHub::Plan).returns(String) }
  def increase_or_decrease(target, new_plan)
    target.payment_difference(new_plan) > 0 ? "increase" : "decrease"
  end

  sig { params(target: User, new_plan: GitHub::Plan).returns(String) }
  def upgrade_or_downgrade(target, new_plan)
    if new_plan == target.plan
      "change"
    elsif new_plan > target.plan
      "upgrade"
    else
      "downgrade"
    end
  end

  sig { params(repository: ::Repository, user: User).returns(T::Boolean) }
  def show_free_org_gated_feature_message?(repository, user)
    return false unless GitHub.billing_enabled?

    owner = repository.owner
    return false unless owner

    owner.organization? && owner.adminable_by?(user) && owner.plan.free?
  end
end
