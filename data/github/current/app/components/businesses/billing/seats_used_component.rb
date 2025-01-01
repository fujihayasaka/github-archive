# typed: true
# frozen_string_literal: true

class Businesses::Billing::SeatsUsedComponent < ApplicationComponent

  attr_reader :business, :plan_duration, :plan

  def initialize(business:, plan_duration:, plan: GitHub::Plan.business_plus)
    @business = business
    @plan_duration = plan_duration
    @plan = plan
  end

  def show_seat_breakdown?
    pending_admin_invitation_count > 0 || pending_member_invitation_count > 0 || outside_collaborator_count > 0
  end

  def show_current_enterprise_usage?
    !business&.organization_upgrade_initiated?
  end

  private

  memoize def plan_name
    "GitHub #{plan.titleized_display_name}"
  end

  memoize def price_per_seat
    if plan_duration == User::BillingDependency::YEARLY_PLAN
      unit_cost = business&.annual_discount_allowed?(plan: plan, billing_cycle: User::BillingDependency::YEARLY_PLAN) ? plan.yearly_cost_in_cents_with_discount : plan.yearly_cost_in_cents
    else
      unit_cost = plan.unit_cost_in_cents
    end
    seat_money = Billing::Money.new(unit_cost)
    seat_money.format(no_cents_if_whole: true)
  end

  memoize def total_seats
    [business.total_consumed_licenses, 1].max
  end

  memoize def pending_admin_invitation_count
    business.pending_admin_invitations.count
  end

  memoize def pending_member_invitation_count
    business.filtered_pending_invitations.count
  end

  memoize def outside_collaborator_count
    business.filtered_outside_collaborators.count
  end
end
