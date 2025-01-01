# typed: true
# frozen_string_literal: true

class Billing::Settings::CurrentOrUpcomingBillComponent < ApplicationComponent
  # account - a User or Organization
  def initialize(account:)
    @account = account
  end

  private

  attr_reader :account

  delegate :subscription, :plan, :alternative_plan_duration, to: :account

  def render?
    GitHub.billing_enabled? && logged_in? && account.present?
  end

  memoize def change_billing_duration_message
    account.change_billing_duration_message
  end

  memoize def pending_cycle_with_addons
    account.pending_cycle(include_addons: true)
  end

  memoize def pending_cycle_without_addons_payment_amount_using_balance
    account.pending_cycle(include_addons: false).payment_amount(use_balance: true)
  end

  # Private: Returns a Billing::Money.
  memoize def subscription_balance
    subscription.balance
  end

  def manage_seats_link_text
    text = "Manage seats"
    text += " (#{account.available_invitable_seats} unused)" if account.has_downgradable_seats?
    text
  end

  def manage_seats_path
    account.has_downgradable_seats? ? remove_org_seats_path(account) : org_seats_path(account)
  end

  def header_text
    if pending_cycle_with_addons.changing_duration?
      "Upcoming #{pending_cycle_with_addons.plan_duration.downcase}ly bill"
    else
      "Current #{account.plan_duration.downcase}ly bill"
    end
  end

  memoize def change_duration_path
    if account.user?
      upgrade_path(plan_duration: alternative_plan_duration, plan: plan)
    elsif !plan.per_repository?
      upgrade_path(org: account, target: "organization", plan_duration: alternative_plan_duration, plan: plan)
    end
  end
end
