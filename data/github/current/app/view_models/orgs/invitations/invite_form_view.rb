# typed: true
# frozen_string_literal: true

class Orgs::Invitations::InviteFormView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization, :per_seat_pricing_model, :rate_limited

  def form_add_or_invite_path_for_organization
    if GitHub.bypass_org_invites_enabled?
      urls.add_member_for_new_org_path(organization)
    else
      urls.org_invitations_create_for_new_org_path(organization)
    end
  end

  def current_plan_duration
    per_seat_pricing_model.plan_duration
  end

  def current_plan_duration_adjective
    "#{per_seat_pricing_model.plan_duration}ly"
  end

  def available_plan_duration
    per_seat_pricing_model.monthly_plan? ? User::BillingDependency::YEARLY_PLAN : User::BillingDependency::MONTHLY_PLAN
  end

  def available_plan_duration_adjective
    "#{available_plan_duration}ly"
  end

  def plan
    per_seat_pricing_model.new_plan
  end

  def coupon
    if defined? @coupon
      return @coupon
    end
    @coupon = organization.coupon
  end
end
